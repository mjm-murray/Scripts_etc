# OCR — make scanned PDFs & images searchable

Turns scanned/image-based PDFs and image files into **searchable PDFs** (an
invisible, selectable text layer over the original page image) and, optionally,
plain-text `.txt` files. Built on
[OCRmyPDF](https://ocrmypdf.readthedocs.io) + Tesseract + Ghostscript.

There are two ways to use it: a **GUI** (double-click, drag & drop or browse) and
a **command line** for scripting/batches.

## Quick start — the GUI

Double-click **`OCR Tool`** (shortcut on your Desktop and in this folder). Then:

- **Drag & drop** files or folders onto the window, **or** click **Add Files… /
  Add Folder…**, **or** drag files straight onto the `OCR Tool` shortcut icon.
- Tick options (language, save `.txt`, deskew, auto-rotate, output location).
- Click **Run OCR**. Progress streams into the log; **Cancel** stops cleanly.

Each source becomes `<name>.ocr.pdf` next to the original (or in the output
folder you choose). Originals are never modified.

> **Why not a `.exe`?** The GUI runs on Python that's already installed, launched
> through `pythonw.exe` (no console window). It opens **instantly** because
> there's nothing to unpack — unlike one-file PyInstaller `.exe`s, which extract
> themselves to a temp folder on every launch and feel slow to start.

## Command line

```powershell
python ocr.py scan.pdf                                    # -> scan.ocr.pdf
python ocr.py .\inbox --recursive --sidecar -o .\searchable
python ocr.py page.jpg --lang eng+deu --deskew --rotate
python ocr.py old.pdf --redo                              # replace a bad OCR layer
python ocr.py --help
```

### Options (CLI + GUI equivalents)

| Option | Meaning |
|--------|---------|
| `-r, --recursive` | Recurse into subfolders |
| `-o, --output-dir DIR` | Write outputs here instead of beside each source |
| `--suffix S` | Output filename suffix (default `.ocr`) |
| `--overwrite` | Overwrite existing outputs (otherwise skipped) |
| `--sidecar` | Also write a `.txt` of the recognized text |
| `-l, --lang L` | Tesseract language(s), e.g. `eng`, `eng+deu` |
| `--image-dpi N` | Assumed DPI for images lacking DPI metadata (default 300) |
| `--optimize 0-3` | Output size optimization (default 1) |
| `--deskew` | Straighten crooked scans |
| `--rotate` | Auto-rotate pages to correct orientation |
| `--clean` | Clean pages before OCR (needs `unpaper`) |
| `--force` | Re-OCR every page, rasterizing existing text |
| `--redo` | Replace an existing OCR text layer only |
| `-q / -v` | Quieter / more verbose output |

`--force` and `--redo` are mutually exclusive; with neither, pages that already
contain text are left untouched (so a searchable file is never corrupted).

## Files in this folder

| File | Purpose |
|------|---------|
| `OCR Tool.lnk` | Launches the GUI (also copied to your Desktop) |
| `ocr_gui.pyw` | The GUI (Tkinter) |
| `ocr.py` | The engine + command-line interface |

## Requirements (already installed on this machine)

| Tool | Version here | Location |
|------|--------------|----------|
| Python | 3.11 | on PATH |
| OCRmyPDF | 17.8 | pip (user) |
| tkinterdnd2 | 0.6.2 | pip (user) — enables drag-into-window |
| Tesseract | 5.5.0 | `%LOCALAPPDATA%\Programs\Tesseract-OCR\` |
| Ghostscript | 10.07.1 | `%LOCALAPPDATA%\Programs\gs\` |

Reinstall on another machine:

```powershell
python -m pip install --user ocrmypdf tkinterdnd2
winget install --id UB-Mannheim.TesseractOCR      # or the UB-Mannheim installer
# Ghostscript: https://ghostscript.com/releases/gsdnld.html  (silent: gsXXXXw64.exe /S)
```

To recreate the shortcut, run `make_shortcut.ps1`.

## Notes

- The tool **auto-locates** Tesseract and Ghostscript even when they aren't on
  `PATH`, so nothing extra needs configuring.
- Available OCR languages depend on the installed Tesseract packs
  (`tesseract --list-langs`). This machine has `eng` plus many script models;
  drop extra `*.traineddata` files into Tesseract's `tessdata` folder to add more.
- Exit codes: `0` success, `1` one or more files failed, `2` bad
  arguments / missing dependency.
- Drag-into-window needs `tkinterdnd2`; without it the GUI still works via the
  Add Files / Add Folder buttons.
