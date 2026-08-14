#!/usr/bin/env pythonw
"""
OCR Tool — graphical front-end.

A small Tkinter window that makes scanned PDFs / images searchable. You can:
    * drag & drop files or folders onto the window,
    * drag files onto the desktop shortcut (they arrive via argv), or
    * use the Add Files / Add Folder buttons.

It launches ocr.py as a subprocess and streams progress into the log, so the
window stays responsive and Cancel can stop a run cleanly. Started with
pythonw.exe there is no console and it opens near-instantly (nothing to unpack).
"""

import os
import queue
import re
import subprocess
import sys
import threading
from pathlib import Path

import tkinter as tk
from tkinter import ttk, filedialog, messagebox

HERE = Path(__file__).resolve().parent
OCR_PY = HERE / "ocr.py"

# Drag-and-drop into the window is optional; Browse/Add still work without it.
try:
    from tkinterdnd2 import TkinterDnD, DND_FILES
    _HAS_DND = True
except Exception:
    _HAS_DND = False

# Reuse the CLI's definitions so the two never drift apart.
try:
    from ocr import SUPPORTED_EXTS, ensure_dependencies
except Exception:
    SUPPORTED_EXTS = {".pdf", ".png", ".jpg", ".jpeg", ".tif", ".tiff",
                      ".bmp", ".gif", ".webp", ".heic", ".heif"}
    ensure_dependencies = None

PROGRESS_RE = re.compile(r"^\[(\d+)/(\d+)\]")


class OcrApp:
    def __init__(self, root):
        self.root = root
        self.paths: list[str] = []       # files and/or folders, in order
        self.proc: subprocess.Popen | None = None
        self.q: queue.Queue = queue.Queue()

        root.title("OCR — Searchable PDF Maker")
        root.geometry("760x600")
        root.minsize(620, 480)

        self._build_ui()
        self._check_dependencies()
        self._poll_queue()

        # Files dropped onto the shortcut arrive as command-line arguments.
        self.add_paths(sys.argv[1:])

    # -- UI ----------------------------------------------------------------
    def _build_ui(self):
        pad = dict(padx=8, pady=4)

        # File list + drop area
        top = ttk.LabelFrame(self.root, text="Files to OCR")
        top.pack(fill="both", expand=True, **pad)

        hint = ("Drag files or folders here"
                if _HAS_DND else "Use the buttons below to add files")
        self.hint = ttk.Label(top, text=hint, foreground="#666")
        self.hint.pack(anchor="w", padx=8, pady=(6, 0))

        listwrap = ttk.Frame(top)
        listwrap.pack(fill="both", expand=True, padx=8, pady=6)
        self.listbox = tk.Listbox(listwrap, selectmode="extended",
                                  activestyle="none")
        sb = ttk.Scrollbar(listwrap, orient="vertical",
                           command=self.listbox.yview)
        self.listbox.configure(yscrollcommand=sb.set)
        self.listbox.pack(side="left", fill="both", expand=True)
        sb.pack(side="right", fill="y")

        if _HAS_DND:
            for w in (self.listbox, top):
                w.drop_target_register(DND_FILES)
                w.dnd_bind("<<Drop>>", self._on_drop)

        btns = ttk.Frame(top)
        btns.pack(fill="x", padx=8, pady=(0, 8))
        ttk.Button(btns, text="Add Files…", command=self._browse_files).pack(side="left")
        ttk.Button(btns, text="Add Folder…", command=self._browse_folder).pack(side="left", padx=4)
        ttk.Button(btns, text="Remove Selected", command=self._remove_selected).pack(side="left")
        ttk.Button(btns, text="Clear", command=self._clear).pack(side="left", padx=4)

        # Options
        opts = ttk.LabelFrame(self.root, text="Options")
        opts.pack(fill="x", **pad)

        row1 = ttk.Frame(opts)
        row1.pack(fill="x", padx=8, pady=4)
        ttk.Label(row1, text="Language:").pack(side="left")
        self.lang = tk.StringVar(value="eng")
        ttk.Entry(row1, textvariable=self.lang, width=12).pack(side="left", padx=(4, 16))

        self.sidecar = tk.BooleanVar(value=True)
        self.deskew = tk.BooleanVar(value=False)
        self.rotate = tk.BooleanVar(value=False)
        self.recursive = tk.BooleanVar(value=True)
        self.overwrite = tk.BooleanVar(value=False)
        ttk.Checkbutton(row1, text="Save .txt", variable=self.sidecar).pack(side="left")
        ttk.Checkbutton(row1, text="Deskew", variable=self.deskew).pack(side="left", padx=8)
        ttk.Checkbutton(row1, text="Auto-rotate", variable=self.rotate).pack(side="left")
        ttk.Checkbutton(row1, text="Recurse folders", variable=self.recursive).pack(side="left", padx=8)
        ttk.Checkbutton(row1, text="Overwrite", variable=self.overwrite).pack(side="left")

        row2 = ttk.Frame(opts)
        row2.pack(fill="x", padx=8, pady=4)
        ttk.Label(row2, text="Output:").pack(side="left")
        self.out_mode = tk.StringVar(value="beside")
        ttk.Radiobutton(row2, text="Beside originals", value="beside",
                        variable=self.out_mode, command=self._sync_out).pack(side="left", padx=(4, 8))
        ttk.Radiobutton(row2, text="Folder:", value="folder",
                        variable=self.out_mode, command=self._sync_out).pack(side="left")
        self.out_dir = tk.StringVar(value="")
        self.out_entry = ttk.Entry(row2, textvariable=self.out_dir)
        self.out_entry.pack(side="left", fill="x", expand=True, padx=4)
        self.out_btn = ttk.Button(row2, text="…", width=3, command=self._browse_outdir)
        self.out_btn.pack(side="left")
        self._sync_out()

        # Action row + progress
        action = ttk.Frame(self.root)
        action.pack(fill="x", **pad)
        self.run_btn = ttk.Button(action, text="Run OCR", command=self._start)
        self.run_btn.pack(side="left")
        self.cancel_btn = ttk.Button(action, text="Cancel", command=self._cancel, state="disabled")
        self.cancel_btn.pack(side="left", padx=4)
        self.progress = ttk.Progressbar(action, mode="determinate")
        self.progress.pack(side="left", fill="x", expand=True, padx=8)

        self.status = ttk.Label(self.root, text="", anchor="w")
        self.status.pack(fill="x", padx=8)

        # Log
        logframe = ttk.LabelFrame(self.root, text="Log")
        logframe.pack(fill="both", expand=True, **pad)
        self.log = tk.Text(logframe, height=10, wrap="word", state="disabled",
                           font=("Consolas", 9))
        logsb = ttk.Scrollbar(logframe, orient="vertical", command=self.log.yview)
        self.log.configure(yscrollcommand=logsb.set)
        self.log.pack(side="left", fill="both", expand=True, padx=(8, 0), pady=8)
        logsb.pack(side="right", fill="y", pady=8)

    # -- dependency banner -------------------------------------------------
    def _check_dependencies(self):
        if ensure_dependencies is None:
            self._set_status("Could not import ocr.py — keep it next to this file.", bad=True)
            return
        rep = ensure_dependencies()
        missing = [k for k, v in rep.items() if v is None]
        if missing:
            self._set_status("Missing: " + ", ".join(missing) +
                             " — see README.md.", bad=True)
        else:
            self._set_status("Ready. Tesseract + Ghostscript found.")

    def _set_status(self, text, bad=False):
        self.status.configure(text=text, foreground="#b00" if bad else "#070")

    # -- file management ---------------------------------------------------
    def _on_drop(self, event):
        self.add_paths(self.root.tk.splitlist(event.data))

    def add_paths(self, items):
        added = 0
        for raw in items:
            p = Path(str(raw))
            if not p.exists():
                continue
            key = str(p)
            if key in self.paths:
                continue
            if p.is_dir() or p.suffix.lower() in SUPPORTED_EXTS:
                self.paths.append(key)
                label = key + ("  [folder]" if p.is_dir() else "")
                self.listbox.insert("end", label)
                added += 1
        if added:
            self._set_status(f"{len(self.paths)} item(s) queued.")

    def _browse_files(self):
        exts = " ".join("*" + e for e in sorted(SUPPORTED_EXTS))
        files = filedialog.askopenfilenames(
            title="Select PDFs or images",
            filetypes=[("Supported", exts), ("All files", "*.*")])
        self.add_paths(files)

    def _browse_folder(self):
        d = filedialog.askdirectory(title="Select a folder")
        if d:
            self.add_paths([d])

    def _browse_outdir(self):
        d = filedialog.askdirectory(title="Select output folder")
        if d:
            self.out_dir.set(d)
            self.out_mode.set("folder")
            self._sync_out()

    def _remove_selected(self):
        for idx in reversed(self.listbox.curselection()):
            self.listbox.delete(idx)
            del self.paths[idx]

    def _clear(self):
        self.listbox.delete(0, "end")
        self.paths.clear()

    def _sync_out(self):
        state = "normal" if self.out_mode.get() == "folder" else "disabled"
        self.out_entry.configure(state=state)
        self.out_btn.configure(state=state)

    # -- running -----------------------------------------------------------
    def _start(self):
        if self.proc is not None:
            return
        if not self.paths:
            messagebox.showinfo("OCR", "Add some files or folders first.")
            return

        argv = [sys.executable, str(OCR_PY), *self.paths,
                "--lang", (self.lang.get().strip() or "eng")]
        if self.recursive.get():
            argv.append("--recursive")
        if self.sidecar.get():
            argv.append("--sidecar")
        if self.deskew.get():
            argv.append("--deskew")
        if self.rotate.get():
            argv.append("--rotate")
        if self.overwrite.get():
            argv.append("--overwrite")
        if self.out_mode.get() == "folder" and self.out_dir.get().strip():
            argv += ["--output-dir", self.out_dir.get().strip()]

        self._log_clear()
        self.progress.configure(value=0, maximum=len(self.paths))
        self._set_running(True)
        threading.Thread(target=self._worker, args=(argv,), daemon=True).start()

    def _worker(self, argv):
        flags = 0x08000000 if os.name == "nt" else 0  # CREATE_NO_WINDOW
        try:
            self.proc = subprocess.Popen(
                argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, encoding="utf-8", errors="replace",
                creationflags=flags, cwd=str(HERE))
        except Exception as exc:
            self.q.put(("line", f"Failed to launch OCR: {exc}"))
            self.q.put(("done", 1))
            return
        for line in self.proc.stdout:
            self.q.put(("line", line.rstrip("\n")))
        code = self.proc.wait()
        self.proc = None
        self.q.put(("done", code))

    def _cancel(self):
        if self.proc is not None:
            try:
                self.proc.terminate()
                self._append("— cancelling —")
            except Exception:
                pass

    def _set_running(self, running):
        self.run_btn.configure(state="disabled" if running else "normal")
        self.cancel_btn.configure(state="normal" if running else "disabled")

    # -- queue pump --------------------------------------------------------
    def _poll_queue(self):
        try:
            while True:
                kind, payload = self.q.get_nowait()
                if kind == "line":
                    self._append(payload)
                    m = PROGRESS_RE.match(payload)
                    if m:
                        self.progress.configure(value=int(m.group(1)),
                                                 maximum=int(m.group(2)))
                elif kind == "done":
                    self._set_running(False)
                    if payload == 0:
                        self._set_status("Finished successfully.")
                        self.progress.configure(value=self.progress["maximum"])
                    elif payload == 130:
                        self._set_status("Cancelled.")
                    else:
                        self._set_status(f"Finished with errors (code {payload}).",
                                         bad=True)
        except queue.Empty:
            pass
        self.root.after(100, self._poll_queue)

    def _append(self, text):
        self.log.configure(state="normal")
        self.log.insert("end", text + "\n")
        self.log.see("end")
        self.log.configure(state="disabled")

    def _log_clear(self):
        self.log.configure(state="normal")
        self.log.delete("1.0", "end")
        self.log.configure(state="disabled")


def main():
    root = TkinterDnD.Tk() if _HAS_DND else tk.Tk()
    OcrApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
