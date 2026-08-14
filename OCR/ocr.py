#!/usr/bin/env python3
"""
Robust standalone OCR tool.

Turns scanned / image-based PDFs and image files into searchable PDFs (an
invisible, selectable text layer laid over the original page image) and,
optionally, plain-text sidecar files. Built on OCRmyPDF + Tesseract +
Ghostscript.

Highlights
    * Batch: pass any mix of files, folders (optionally recursive) and globs.
    * Handles PDFs and images (png/jpg/tif/bmp/webp/gif/heic...).
    * Skips pages that already contain text by default (never corrupts a file
      that is already searchable) -- override with --force / --redo.
    * Per-file error isolation: one bad file never aborts the batch; a summary
      with exit code is printed at the end.
    * Auto-locates Tesseract and Ghostscript even when they are not on PATH.

Usage
    python ocr.py scan.pdf
    python ocr.py .\inbox --recursive --sidecar --output-dir .\searchable
    python ocr.py page.jpg --lang eng+deu --deskew --rotate

Run  python ocr.py --help  for the full option list.
"""

from __future__ import annotations

import argparse
import glob
import logging
import os
import shutil
import sys
import time
from pathlib import Path

# ---------------------------------------------------------------------------
# Dependency discovery: make sure Tesseract and Ghostscript are reachable via
# PATH *before* ocrmypdf is imported/used, so it can find them even when they
# were installed to a per-user location that is not on the system PATH.
# ---------------------------------------------------------------------------

IMAGE_EXTS = {
    ".png", ".jpg", ".jpeg", ".tif", ".tiff", ".bmp",
    ".gif", ".webp", ".heic", ".heif", ".jp2", ".pnm", ".ppm",
}

log = logging.getLogger("ocr")


def _first_existing(paths):
    for p in paths:
        if p and Path(p).is_file():
            return Path(p)
    return None


def _glob_bin(patterns):
    """Return the first file matching any of the given glob patterns."""
    for pat in patterns:
        matches = sorted(glob.glob(pat))
        if matches:
            return Path(matches[-1])  # last = highest version when sorted
    return None


def locate_tesseract() -> Path | None:
    found = shutil.which("tesseract")
    if found:
        return Path(found)
    lad = os.environ.get("LOCALAPPDATA", "")
    pf = os.environ.get("ProgramFiles", r"C:\Program Files")
    pf86 = os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")
    return _first_existing([
        os.path.join(lad, "Programs", "Tesseract-OCR", "tesseract.exe"),
        os.path.join(pf, "Tesseract-OCR", "tesseract.exe"),
        os.path.join(pf86, "Tesseract-OCR", "tesseract.exe"),
    ])


def locate_ghostscript() -> Path | None:
    for name in ("gswin64c", "gswin32c", "gs"):
        found = shutil.which(name)
        if found:
            return Path(found)
    lad = os.environ.get("LOCALAPPDATA", "")
    pf = os.environ.get("ProgramFiles", r"C:\Program Files")
    return _glob_bin([
        os.path.join(lad, "Programs", "gs", "bin", "gswin64c.exe"),
        os.path.join(lad, "Programs", "gs", "gs*", "bin", "gswin64c.exe"),
        os.path.join(pf, "gs", "gs*", "bin", "gswin64c.exe"),
        os.path.join(pf, "gs", "gs*", "bin", "gswin32c.exe"),
    ])


def ensure_dependencies() -> dict:
    """Locate binaries, prepend their dirs to PATH, and return a report."""
    report = {}

    tess = locate_tesseract()
    if tess:
        os.environ["PATH"] = str(tess.parent) + os.pathsep + os.environ.get("PATH", "")
        report["tesseract"] = tess
    else:
        report["tesseract"] = None

    gs = locate_ghostscript()
    if gs:
        os.environ["PATH"] = str(gs.parent) + os.pathsep + os.environ.get("PATH", "")
        report["ghostscript"] = gs
    else:
        report["ghostscript"] = None

    return report


# ---------------------------------------------------------------------------
# Input collection
# ---------------------------------------------------------------------------

SUPPORTED_EXTS = IMAGE_EXTS | {".pdf"}


def collect_inputs(raw_inputs, recursive: bool):
    """Expand files / folders / globs into a de-duplicated, sorted file list."""
    files: list[Path] = []
    seen: set[Path] = set()

    def add(p: Path):
        try:
            rp = p.resolve()
        except OSError:
            rp = p
        if rp in seen:
            return
        if p.suffix.lower() in SUPPORTED_EXTS:
            seen.add(rp)
            files.append(p)

    for item in raw_inputs:
        # Expand shell-style globs that the shell did not expand itself.
        expanded = glob.glob(item, recursive=recursive)
        candidates = [Path(e) for e in expanded] if expanded else [Path(item)]

        for c in candidates:
            if c.is_dir():
                walker = c.rglob("*") if recursive else c.glob("*")
                for f in sorted(walker):
                    if f.is_file():
                        add(f)
            elif c.is_file():
                add(c)
            else:
                log.warning("Skipping (not found): %s", item)

    return files


def output_path_for(src: Path, output_dir: Path | None, suffix: str) -> Path:
    stem = src.stem + suffix + ".pdf"
    if output_dir:
        return output_dir / stem
    return src.with_name(stem)


# ---------------------------------------------------------------------------
# OCR
# ---------------------------------------------------------------------------

def base_ocr_kwargs(lang="eng", deskew=False, rotate=False, optimize=1,
                    force=False, redo=False, clean=False,
                    image_dpi=300) -> dict:
    """Assemble the keyword args shared by every OCRmyPDF call in a batch."""
    kwargs = dict(
        language=lang,
        deskew=deskew,
        rotate_pages=rotate,
        optimize=optimize,
        progress_bar=False,
    )

    # Mutually exclusive text-handling modes.
    if force:
        kwargs["force_ocr"] = True
    elif redo:
        kwargs["redo_ocr"] = True
    else:
        kwargs["skip_text"] = True

    if clean:
        kwargs["clean"] = True

    kwargs["_image_dpi"] = image_dpi
    return kwargs


def ocr_one(src: Path, dest: Path, sidecar: bool, base_kwargs: dict) -> str:
    """OCR a single file. Returns a short status string; raises on failure."""
    import ocrmypdf
    from ocrmypdf.exceptions import PriorOcrFoundError

    dest.parent.mkdir(parents=True, exist_ok=True)
    kwargs = dict(base_kwargs)

    # Images have no intrinsic page size until we tell OCRmyPDF the DPI.
    if src.suffix.lower() in IMAGE_EXTS:
        kwargs["image_dpi"] = base_kwargs.get("_image_dpi", 300)
    kwargs.pop("_image_dpi", None)

    if sidecar:
        kwargs["sidecar"] = str(dest.with_suffix(".txt"))

    try:
        ocrmypdf.ocr(str(src), str(dest), **kwargs)
    except PriorOcrFoundError:
        # Should not happen with skip_text, but be defensive across versions.
        return "skipped (already has text)"
    return "ok"


def ocr_batch(files, *, sidecar=False, output_dir=None, suffix=".ocr",
              overwrite=False, base_kwargs=None, on_event=None,
              should_stop=None):
    """Run OCR over a list of files with per-file error isolation.

    ``on_event(kind, **data)`` is called for progress reporting; ``kind`` is one
    of: start, done, skip, error, summary. ``should_stop()`` may return True to
    abort the batch between files. Returns a summary dict.
    """
    def emit(kind, **data):
        if on_event:
            on_event(kind, **data)

    base_kwargs = dict(base_kwargs or base_ocr_kwargs())
    out_dir = Path(output_dir) if output_dir else None
    if out_dir:
        out_dir.mkdir(parents=True, exist_ok=True)

    total = len(files)
    ok = skipped = failed = 0
    failures: list[tuple[Path, str]] = []
    t0 = time.perf_counter()

    for i, src in enumerate(files, 1):
        if should_stop and should_stop():
            emit("skip", index=i, total=total, src=src,
                 reason="cancelled")
            break

        src = Path(src)
        dest = output_path_for(src, out_dir, suffix)

        if dest == src:
            skipped += 1
            emit("skip", index=i, total=total, src=src,
                 reason="output equals input")
            continue

        if dest.exists() and not overwrite:
            skipped += 1
            emit("skip", index=i, total=total, src=src, dest=dest,
                 reason="output exists")
            continue

        emit("start", index=i, total=total, src=src, dest=dest)
        try:
            status = ocr_one(src, dest, sidecar, base_kwargs)
            if status.startswith("skipped"):
                skipped += 1
                emit("skip", index=i, total=total, src=src, reason=status)
            else:
                ok += 1
                emit("done", index=i, total=total, src=src, dest=dest,
                     sidecar=sidecar)
        except KeyboardInterrupt:
            raise
        except Exception as exc:  # isolate per-file failures
            failed += 1
            msg = f"{type(exc).__name__}: {exc}"
            failures.append((src, msg))
            emit("error", index=i, total=total, src=src, msg=msg)

    summary = dict(ok=ok, skipped=skipped, failed=failed,
                   failures=failures, seconds=time.perf_counter() - t0)
    emit("summary", **summary)
    return summary


def run(args) -> int:
    report = ensure_dependencies()

    log.info("Tesseract:   %s", report["tesseract"] or "NOT FOUND")
    log.info("Ghostscript: %s", report["ghostscript"] or "NOT FOUND")

    missing = [k for k, v in report.items() if v is None]
    if missing:
        log.error(
            "Missing dependency: %s. Install it, then re-run. "
            "See README.md for instructions.", ", ".join(missing))
        return 2

    files = collect_inputs(args.inputs, args.recursive)
    if not files:
        log.error("No supported input files found (%s).",
                  ", ".join(sorted(SUPPORTED_EXTS)))
        return 2

    log.info("Found %d file(s) to process.", len(files))

    def on_event(kind, **d):
        if kind == "start":
            log.info("[%d/%d] %s", d["index"], d["total"], d["src"].name)
        elif kind == "done":
            log.info("        -> %s", d["dest"].name +
                     (" (+ .txt)" if d["sidecar"] else ""))
        elif kind == "skip":
            log.info("[%d/%d] %s -> skipped (%s)",
                     d["index"], d["total"], d["src"].name, d["reason"])
        elif kind == "error":
            log.error("        FAILED: %s", d["msg"])
        elif kind == "summary":
            log.info("-" * 60)
            log.info("Done in %.1fs  |  ok=%d  skipped=%d  failed=%d",
                     d["seconds"], d["ok"], d["skipped"], d["failed"])
            for src, msg in d["failures"]:
                log.info("  %s\n    %s", src, msg)

    base_kwargs = base_ocr_kwargs(
        lang=args.lang, deskew=args.deskew, rotate=args.rotate,
        optimize=args.optimize, force=args.force, redo=args.redo,
        clean=args.clean, image_dpi=args.image_dpi)

    summary = ocr_batch(
        files, sidecar=args.sidecar,
        output_dir=args.output_dir, suffix=args.suffix,
        overwrite=args.overwrite, base_kwargs=base_kwargs, on_event=on_event)

    return 1 if summary["failed"] else 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="ocr",
        description="Make scanned PDFs and images searchable (OCR).",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument("inputs", nargs="+",
                   help="Files, folders, or globs to OCR (PDF or image).")
    p.add_argument("-r", "--recursive", action="store_true",
                   help="Recurse into subfolders.")
    p.add_argument("-o", "--output-dir", metavar="DIR",
                   help="Write outputs here instead of next to each source.")
    p.add_argument("--suffix", default=".ocr",
                   help="Suffix added to output filenames.")
    p.add_argument("--overwrite", action="store_true",
                   help="Overwrite existing output files.")
    p.add_argument("--sidecar", action="store_true",
                   help="Also write a plain-text .txt next to each output.")

    p.add_argument("-l", "--lang", default="eng",
                   help="Tesseract language(s), e.g. 'eng' or 'eng+deu'.")
    p.add_argument("--image-dpi", type=int, default=300,
                   help="Assumed DPI for image inputs lacking DPI metadata.")
    p.add_argument("--optimize", type=int, choices=[0, 1, 2, 3], default=1,
                   help="Output size optimization (0=off .. 3=max).")

    p.add_argument("--deskew", action="store_true",
                   help="Straighten crooked scans before OCR.")
    p.add_argument("--rotate", action="store_true",
                   help="Auto-rotate pages to correct orientation.")
    p.add_argument("--clean", action="store_true",
                   help="Clean pages before OCR (requires 'unpaper').")

    mode = p.add_mutually_exclusive_group()
    mode.add_argument("--force", action="store_true",
                      help="Re-OCR every page, rasterizing existing text.")
    mode.add_argument("--redo", action="store_true",
                      help="Replace existing OCR text layer only.")

    p.add_argument("-q", "--quiet", action="store_true", help="Less output.")
    p.add_argument("-v", "--verbose", action="store_true", help="More output.")
    return p


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)

    level = logging.INFO
    if args.quiet:
        level = logging.WARNING
    elif args.verbose:
        level = logging.DEBUG
    logging.basicConfig(level=level, format="%(message)s", stream=sys.stdout)
    # Keep third-party libraries from drowning us unless -v.
    noisy_level = logging.INFO if args.verbose else logging.WARNING
    for name in ("ocrmypdf", "fontTools", "fontTools.subset",
                 "pikepdf", "PIL", "img2pdf"):
        logging.getLogger(name).setLevel(noisy_level)

    try:
        return run(args)
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    sys.exit(main())
