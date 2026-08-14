# Meetings Transcriber Setup

A small GUI installer that deploys the auto-transcription pipeline into any folder on a Windows machine. Drop an `.mp4` into the watched folder and a transcript, speaker-attributed transcript, Word doc, and meeting notes appear next to it.

## Build the .exe

```powershell
.\build.ps1
```

Output: `dist\MeetingsTranscriberSetup.exe`. Distribute that single file.

## What the installer does

1. Detects (and on request installs) prerequisites: Python, ffmpeg, `openai-whisper`, `python-docx`. The Claude CLI is optional but enables speaker-attributed transcripts and meeting notes.
2. Copies `transcribe.ps1`, `watch.ps1`, `md-to-docx.py` into `<chosen folder>\.claude\`.
3. Writes `<chosen folder>\.claude\config.json` with the chosen settings.
4. Registers a per-user scheduled task (`MeetingTranscriber` by default) that runs the watcher at logon.

No admin rights required. To remove, click "Uninstall watcher" in the GUI (or run `Unregister-ScheduledTask -TaskName MeetingTranscriber -Confirm:$false`).

## Run from source

```powershell
python setup_gui.py
```

## Resources

The PowerShell + Python scripts the installer deploys live in `resources/`. Update them there and rebuild the exe to ship a new version.
