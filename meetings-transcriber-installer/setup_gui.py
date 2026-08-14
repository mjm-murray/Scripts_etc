"""Meetings Transcriber - Setup GUI.

Installs prerequisites, deploys scripts into a chosen folder, and registers a
scheduled task so new MP4 files dropped into the folder are auto-transcribed.

Run directly with `python setup_gui.py` during development, or build into a
single-file .exe via `build.ps1`.
"""
from __future__ import annotations

import json
import os
import queue
import shutil
import subprocess
import sys
import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, scrolledtext, ttk

APP_TITLE = "Meetings Transcriber - Setup"
APP_VERSION = "1.0"
DEFAULT_TASK_NAME = "MeetingTranscriber"
WHISPER_MODELS = ["tiny", "base", "small", "medium", "large-v3", "turbo"]

# ---------------------------------------------------------------------------
# Resource paths (work in dev and when bundled by PyInstaller)
# ---------------------------------------------------------------------------

def app_dir() -> Path:
    """Where bundled resources live at runtime."""
    if hasattr(sys, "_MEIPASS"):
        return Path(sys._MEIPASS)  # type: ignore[attr-defined]
    return Path(__file__).resolve().parent


def resource(name: str) -> Path:
    return app_dir() / "resources" / name


SCRIPTS_TO_DEPLOY = ["transcribe.ps1", "watch.ps1", "md-to-docx.py"]


# ---------------------------------------------------------------------------
# Shell helpers
# ---------------------------------------------------------------------------

def run(cmd: list[str], capture: bool = True, check: bool = False) -> subprocess.CompletedProcess:
    """Run a command, hide the console window if we're a windowed PyInstaller build."""
    kwargs: dict = {"text": True}
    if capture:
        kwargs["stdout"] = subprocess.PIPE
        kwargs["stderr"] = subprocess.STDOUT
    if os.name == "nt":
        # Hide child console windows in --windowed builds.
        si = subprocess.STARTUPINFO()
        si.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        kwargs["startupinfo"] = si
        kwargs["creationflags"] = subprocess.CREATE_NO_WINDOW
    return subprocess.run(cmd, check=check, **kwargs)


def which(name: str) -> str | None:
    return shutil.which(name)


def powershell(script: str) -> subprocess.CompletedProcess:
    return run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script])


# ---------------------------------------------------------------------------
# Prerequisite detection
# ---------------------------------------------------------------------------

class Prereq:
    def __init__(self, key: str, label: str, required: bool, check, install_hint: str):
        self.key = key
        self.label = label
        self.required = required
        self.check = check  # callable -> (ok: bool, detail: str)
        self.install_hint = install_hint


def _check_python() -> tuple[bool, str]:
    p = which("python") or which("py")
    if not p:
        return (False, "not found on PATH")
    try:
        r = run([p, "--version"])
        return (r.returncode == 0, (r.stdout or "").strip())
    except Exception as e:  # pragma: no cover
        return (False, str(e))


def _check_pip_pkg(pkg: str) -> tuple[bool, str]:
    p = which("python") or which("py")
    if not p:
        return (False, "python missing")
    r = run([p, "-m", "pip", "show", pkg])
    if r.returncode != 0:
        return (False, "not installed")
    version = ""
    for line in (r.stdout or "").splitlines():
        if line.lower().startswith("version:"):
            version = line.split(":", 1)[1].strip()
            break
    return (True, version or "installed")


def _check_ffmpeg() -> tuple[bool, str]:
    p = which("ffmpeg")
    if not p:
        return (False, "not found on PATH")
    try:
        r = run([p, "-version"])
        first = (r.stdout or "").splitlines()[0] if r.stdout else ""
        return (r.returncode == 0, first[:80])
    except Exception as e:
        return (False, str(e))


def _check_claude() -> tuple[bool, str]:
    p = which("claude")
    if not p:
        return (False, "not found (optional - needed for speaker attribution + notes)")
    return (True, p)


def prereqs() -> list[Prereq]:
    return [
        Prereq("python",  "Python 3.9+",      True,  _check_python,                     "winget install Python.Python.3.11"),
        Prereq("ffmpeg",  "ffmpeg",           True,  _check_ffmpeg,                     "winget install Gyan.FFmpeg"),
        Prereq("whisper", "openai-whisper",   True,  lambda: _check_pip_pkg("openai-whisper"), "pip install openai-whisper"),
        Prereq("docx",    "python-docx",      True,  lambda: _check_pip_pkg("python-docx"),    "pip install python-docx"),
        Prereq("claude",  "Claude CLI",       False, _check_claude,                     "Install Claude Code separately"),
    ]


# ---------------------------------------------------------------------------
# Installers
# ---------------------------------------------------------------------------

def install_winget(pkg_id: str, log) -> bool:
    if not which("winget"):
        log(f"  winget not available; cannot auto-install {pkg_id}")
        return False
    log(f"  winget install {pkg_id} ...")
    r = run(["winget", "install", "--id", pkg_id, "-e",
             "--accept-source-agreements", "--accept-package-agreements"])
    if r.stdout:
        for line in r.stdout.splitlines()[-6:]:
            log(f"    {line}")
    ok = r.returncode == 0
    log(f"  -> {'ok' if ok else f'failed (exit {r.returncode})'}")
    return ok


def install_pip(pkg: str, log) -> bool:
    p = which("python") or which("py")
    if not p:
        log("  python missing; cannot pip install")
        return False
    log(f"  pip install --user {pkg} ...")
    r = run([p, "-m", "pip", "install", "--user", "-U", pkg])
    if r.stdout:
        for line in r.stdout.splitlines()[-3:]:
            log(f"    {line}")
    ok = r.returncode == 0
    log(f"  -> {'ok' if ok else f'failed (exit {r.returncode})'}")
    return ok


# ---------------------------------------------------------------------------
# Deploy + scheduled task
# ---------------------------------------------------------------------------

def deploy_scripts(folder: Path, log) -> Path:
    target = folder / ".claude"
    target.mkdir(parents=True, exist_ok=True)
    log(f"  deploying scripts -> {target}")
    for name in SCRIPTS_TO_DEPLOY:
        src = resource(name)
        if not src.exists():
            raise FileNotFoundError(f"bundled resource missing: {src}")
        dst = target / name
        shutil.copyfile(src, dst)
        log(f"    {name} ({dst.stat().st_size} bytes)")
    return target


def write_config(claude_dir: Path, model: str, language: str,
                 fmt: bool, docx: bool, notes: bool, log) -> Path:
    cfg = {
        "whisperModel": model,
        "language": language,
        "stages": {"format": fmt, "docx": docx, "notes": notes},
    }
    p = claude_dir / "config.json"
    p.write_text(json.dumps(cfg, indent=2), encoding="utf-8")
    log(f"  wrote config -> {p}")
    return p


def register_task(task_name: str, claude_dir: Path, log) -> bool:
    watch = claude_dir / "watch.ps1"
    if not watch.exists():
        log("  watch.ps1 not found after deploy?")
        return False
    ps = f'''
$watch = "{watch}"
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$watch`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName "{task_name}" -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Auto-transcribes new MP4 files dropped into the watched folder via Whisper." -Force | Out-Null
Start-ScheduledTask -TaskName "{task_name}"
"OK"
'''
    log(f"  registering scheduled task '{task_name}' ...")
    r = powershell(ps)
    if r.stdout:
        for line in r.stdout.strip().splitlines()[-5:]:
            log(f"    {line}")
    ok = r.returncode == 0
    log(f"  -> {'ok' if ok else f'failed (exit {r.returncode})'}")
    return ok


def unregister_task(task_name: str, log) -> bool:
    ps = f'Unregister-ScheduledTask -TaskName "{task_name}" -Confirm:$false -ErrorAction SilentlyContinue; "removed"'
    log(f"  removing scheduled task '{task_name}' ...")
    r = powershell(ps)
    ok = r.returncode == 0
    log(f"  -> {'ok' if ok else f'failed (exit {r.returncode})'}")
    return ok


def run_on_existing(claude_dir: Path, folder: Path, log) -> None:
    transcribe = claude_dir / "transcribe.ps1"
    mp4s = sorted(folder.glob("*.mp4"))
    if not mp4s:
        log("  no MP4 files found in folder")
        return
    log(f"  found {len(mp4s)} mp4 file(s); transcribing missing ones ...")
    for mp4 in mp4s:
        transcript = mp4.with_name(f"{mp4.stem}.transcript.md")
        if transcript.exists():
            log(f"  skip (already): {mp4.name}")
            continue
        log(f"  transcribing: {mp4.name} (this may take several minutes)")
        r = powershell(f'& "{transcribe}" -Path "{mp4}"')
        if r.stdout:
            for line in r.stdout.splitlines()[-4:]:
                log(f"    {line}")


# ---------------------------------------------------------------------------
# GUI
# ---------------------------------------------------------------------------

class App:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        root.title(f"{APP_TITLE} v{APP_VERSION}")
        root.geometry("760x720")
        root.minsize(680, 600)

        self.log_queue: queue.Queue[str] = queue.Queue()
        self.busy = False
        self.prereq_status: dict[str, ttk.Label] = {}

        self._build_ui()
        self._poll_log_queue()
        self._refresh_prereqs_async()

    # -- UI construction ----------------------------------------------------

    def _build_ui(self) -> None:
        pad = {"padx": 10, "pady": 4}

        nb = ttk.Notebook(self.root)
        nb.pack(fill="both", expand=True)

        # ---- Setup tab ----
        tab = ttk.Frame(nb)
        nb.add(tab, text="Setup")

        # Folder picker
        folder_frame = ttk.LabelFrame(tab, text="Watch folder")
        folder_frame.pack(fill="x", **pad)
        self.folder_var = tk.StringVar(value=str(Path.home() / "Documents" / "Meetings"))
        e = ttk.Entry(folder_frame, textvariable=self.folder_var)
        e.pack(side="left", fill="x", expand=True, padx=(8, 4), pady=8)
        ttk.Button(folder_frame, text="Browse...", command=self._pick_folder).pack(side="left", padx=(0, 8), pady=8)

        # Settings
        s_frame = ttk.LabelFrame(tab, text="Settings")
        s_frame.pack(fill="x", **pad)

        row = ttk.Frame(s_frame)
        row.pack(fill="x", padx=8, pady=4)
        ttk.Label(row, text="Whisper model:").pack(side="left")
        self.model_var = tk.StringVar(value="turbo")
        ttk.Combobox(row, values=WHISPER_MODELS, textvariable=self.model_var, width=14, state="readonly").pack(side="left", padx=8)
        ttk.Label(row, text="(turbo = fast+good; large-v3 = best+slower)").pack(side="left")

        row = ttk.Frame(s_frame)
        row.pack(fill="x", padx=8, pady=4)
        ttk.Label(row, text="Language:").pack(side="left")
        self.language_var = tk.StringVar(value="en")
        ttk.Entry(row, textvariable=self.language_var, width=8).pack(side="left", padx=8)
        ttk.Label(row, text="(ISO 639-1 code, e.g. 'en', 'es', 'fr')").pack(side="left")

        row = ttk.Frame(s_frame)
        row.pack(fill="x", padx=8, pady=4)
        ttk.Label(row, text="Output stages:").pack(side="left")
        self.fmt_var   = tk.BooleanVar(value=True)
        self.docx_var  = tk.BooleanVar(value=True)
        self.notes_var = tk.BooleanVar(value=True)
        ttk.Checkbutton(row, text="Speaker-attributed transcript (needs Claude CLI)", variable=self.fmt_var).pack(side="left", padx=4)
        row2 = ttk.Frame(s_frame)
        row2.pack(fill="x", padx=8, pady=2)
        ttk.Label(row2, text=" " * 14).pack(side="left")
        ttk.Checkbutton(row2, text="Word doc (.docx)", variable=self.docx_var).pack(side="left", padx=4)
        ttk.Checkbutton(row2, text="Meeting notes (needs Claude CLI)", variable=self.notes_var).pack(side="left", padx=4)

        row = ttk.Frame(s_frame)
        row.pack(fill="x", padx=8, pady=4)
        ttk.Label(row, text="Scheduled task name:").pack(side="left")
        self.task_var = tk.StringVar(value=DEFAULT_TASK_NAME)
        ttk.Entry(row, textvariable=self.task_var, width=28).pack(side="left", padx=8)

        # Prerequisites
        p_frame = ttk.LabelFrame(tab, text="Prerequisites")
        p_frame.pack(fill="x", **pad)
        for pr in prereqs():
            row = ttk.Frame(p_frame)
            row.pack(fill="x", padx=8, pady=2)
            ttk.Label(row, text=pr.label, width=20, anchor="w").pack(side="left")
            status = ttk.Label(row, text="checking...", width=50, anchor="w")
            status.pack(side="left")
            self.prereq_status[pr.key] = status
        ttk.Button(p_frame, text="Re-check", command=self._refresh_prereqs_async).pack(anchor="e", padx=8, pady=6)

        # Action buttons
        btns = ttk.Frame(tab)
        btns.pack(fill="x", **pad)
        self.install_btn = ttk.Button(btns, text="Install / Update", command=self._do_install_async)
        self.install_btn.pack(side="left", padx=4)
        ttk.Button(btns, text="Install missing prerequisites only", command=self._do_install_prereqs_async).pack(side="left", padx=4)
        ttk.Button(btns, text="Run on existing files", command=self._do_run_existing_async).pack(side="left", padx=4)
        ttk.Button(btns, text="Uninstall watcher", command=self._do_uninstall_async).pack(side="left", padx=4)

        # Log
        l_frame = ttk.LabelFrame(tab, text="Log")
        l_frame.pack(fill="both", expand=True, **pad)
        self.log_area = scrolledtext.ScrolledText(l_frame, height=14, wrap="word", state="disabled")
        self.log_area.pack(fill="both", expand=True, padx=6, pady=6)

        # ---- About tab ----
        about = ttk.Frame(nb)
        nb.add(about, text="About")
        msg = (
            f"{APP_TITLE} v{APP_VERSION}\n\n"
            "This installer sets up an automatic meeting-transcription pipeline:\n\n"
            "  - Drop an .mp4 into the chosen folder\n"
            "  - A FileSystemWatcher (run via a scheduled task at logon) detects it\n"
            "  - Whisper transcribes the audio\n"
            "  - Optional: Claude CLI generates a speaker-attributed transcript and meeting notes\n"
            "  - A Word .docx is built from the result\n\n"
            "All output files are written next to the source .mp4:\n"
            "  <name>.transcript.md           raw whisper text\n"
            "  <name>.transcript.formatted.md speaker-attributed bullets\n"
            "  <name>.transcript.docx         styled Word doc\n"
            "  <name>.notes.md                meeting notes (attendees, decisions, action items)\n\n"
            "Scheduled task runs as the current user; no admin required."
        )
        ttk.Label(about, text=msg, justify="left", anchor="nw").pack(fill="both", expand=True, padx=14, pady=14)

    # -- Helpers ------------------------------------------------------------

    def log(self, msg: str) -> None:
        self.log_queue.put(msg)

    def _poll_log_queue(self) -> None:
        try:
            while True:
                msg = self.log_queue.get_nowait()
                self.log_area.configure(state="normal")
                self.log_area.insert("end", msg + "\n")
                self.log_area.see("end")
                self.log_area.configure(state="disabled")
        except queue.Empty:
            pass
        self.root.after(100, self._poll_log_queue)

    def _pick_folder(self) -> None:
        d = filedialog.askdirectory(initialdir=self.folder_var.get() or str(Path.home()))
        if d:
            self.folder_var.set(d)

    def _set_busy(self, busy: bool) -> None:
        self.busy = busy
        state = "disabled" if busy else "normal"
        self.install_btn.configure(state=state)

    def _async(self, fn) -> None:
        if self.busy:
            self.log("(busy - wait for current task to finish)")
            return
        self._set_busy(True)
        def wrapper():
            try:
                fn()
            except Exception as e:
                self.log(f"ERROR: {e}")
            finally:
                self.root.after(0, lambda: self._set_busy(False))
        threading.Thread(target=wrapper, daemon=True).start()

    # -- Action handlers ----------------------------------------------------

    def _refresh_prereqs_async(self) -> None:
        def task():
            self.log("Checking prerequisites...")
            for pr in prereqs():
                ok, detail = pr.check()
                marker = "OK" if ok else ("MISSING" if pr.required else "missing (optional)")
                line = f"  {pr.label}: {marker} - {detail}"
                self.log(line)
                color = "#0a7d0a" if ok else ("#b00020" if pr.required else "#7a5b00")
                lab = self.prereq_status.get(pr.key)
                if lab is not None:
                    self.root.after(0, lambda l=lab, t=f"{marker} - {detail}", c=color: l.configure(text=t, foreground=c))
        self._async(task)

    def _do_install_prereqs_async(self) -> None:
        def task():
            self.log("Installing missing prerequisites (this can take a while; first whisper install ~2 GB)...")
            for pr in prereqs():
                ok, _ = pr.check()
                if ok:
                    self.log(f"  {pr.label}: already installed")
                    continue
                if pr.key == "python":
                    install_winget("Python.Python.3.11", self.log)
                elif pr.key == "ffmpeg":
                    install_winget("Gyan.FFmpeg", self.log)
                elif pr.key == "whisper":
                    install_pip("openai-whisper", self.log)
                elif pr.key == "docx":
                    install_pip("python-docx", self.log)
                elif pr.key == "claude":
                    self.log(f"  {pr.label}: skipping (install Claude Code from https://claude.com/download)")
            self.log("Done. Re-checking prerequisites...")
            for pr in prereqs():
                ok, detail = pr.check()
                marker = "OK" if ok else ("MISSING" if pr.required else "missing (optional)")
                color = "#0a7d0a" if ok else ("#b00020" if pr.required else "#7a5b00")
                lab = self.prereq_status.get(pr.key)
                if lab is not None:
                    self.root.after(0, lambda l=lab, t=f"{marker} - {detail}", c=color: l.configure(text=t, foreground=c))
        self._async(task)

    def _validate_folder(self) -> Path | None:
        f = self.folder_var.get().strip()
        if not f:
            messagebox.showerror(APP_TITLE, "Pick a watch folder first.")
            return None
        p = Path(f)
        if not p.exists():
            if not messagebox.askyesno(APP_TITLE, f"Folder does not exist:\n{p}\n\nCreate it?"):
                return None
            p.mkdir(parents=True, exist_ok=True)
        if not p.is_dir():
            messagebox.showerror(APP_TITLE, f"Not a directory:\n{p}")
            return None
        return p

    def _do_install_async(self) -> None:
        folder = self._validate_folder()
        if folder is None:
            return

        def task():
            self.log(f"=== Installing into {folder} ===")
            # 1. Ensure required prereqs
            missing_required = []
            for pr in prereqs():
                ok, _ = pr.check()
                if not ok and pr.required:
                    missing_required.append(pr)
            if missing_required:
                self.log("Required prerequisites missing - installing them first:")
                for pr in missing_required:
                    if pr.key == "python":
                        install_winget("Python.Python.3.11", self.log)
                    elif pr.key == "ffmpeg":
                        install_winget("Gyan.FFmpeg", self.log)
                    elif pr.key == "whisper":
                        install_pip("openai-whisper", self.log)
                    elif pr.key == "docx":
                        install_pip("python-docx", self.log)

            # 2. Deploy scripts
            claude_dir = deploy_scripts(folder, self.log)

            # 3. Write config
            write_config(
                claude_dir,
                model=self.model_var.get(),
                language=self.language_var.get().strip() or "en",
                fmt=self.fmt_var.get(),
                docx=self.docx_var.get(),
                notes=self.notes_var.get(),
                log=self.log,
            )

            # 4. Register scheduled task
            task_name = self.task_var.get().strip() or DEFAULT_TASK_NAME
            register_task(task_name, claude_dir, self.log)

            self.log("=== Done. Drop an .mp4 into the folder to test. ===")
            self.log(f"Watcher log: {claude_dir / 'watch.log'}")
        self._async(task)

    def _do_run_existing_async(self) -> None:
        folder = self._validate_folder()
        if folder is None:
            return
        def task():
            claude_dir = folder / ".claude"
            if not (claude_dir / "transcribe.ps1").exists():
                self.log("transcribe.ps1 not deployed yet; run 'Install / Update' first.")
                return
            run_on_existing(claude_dir, folder, self.log)
        self._async(task)

    def _do_uninstall_async(self) -> None:
        task_name = self.task_var.get().strip() or DEFAULT_TASK_NAME
        if not messagebox.askyesno(APP_TITLE, f"Remove scheduled task '{task_name}'?\n\nDeployed scripts and any transcripts remain in place."):
            return
        def task():
            unregister_task(task_name, self.log)
        self._async(task)


def main() -> int:
    root = tk.Tk()
    try:
        style = ttk.Style()
        if "vista" in style.theme_names():
            style.theme_use("vista")
    except Exception:
        pass
    App(root)
    root.mainloop()
    return 0


if __name__ == "__main__":
    sys.exit(main())
