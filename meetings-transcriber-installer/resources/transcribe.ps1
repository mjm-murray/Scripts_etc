[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Path,

    [ValidateSet('tiny', 'base', 'small', 'medium', 'large-v3', 'turbo')]
    [string]$Model = 'turbo',

    [string]$Language = 'en',

    [switch]$SkipFormat,
    [switch]$SkipDocx,
    [switch]$SkipNotes
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path)) {
    throw "File not found: $Path"
}

$file       = Get-Item -LiteralPath $Path
$dir        = $file.DirectoryName
$stem       = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
$transcript = Join-Path $dir "$stem.transcript.md"
$formatted  = Join-Path $dir "$stem.transcript.formatted.md"
$docx       = Join-Path $dir "$stem.transcript.docx"
$notes      = Join-Path $dir "$stem.notes.md"
$helperDir  = $PSScriptRoot

# ---- 1. Transcribe (whisper) ----
if (Test-Path -LiteralPath $transcript) {
    Write-Host "Skip whisper (transcript exists): $($file.Name)"
} else {
    Write-Host "Transcribing $($file.Name) with whisper model=$Model ..."
    $tmp = Join-Path $env:TEMP ("whisper_" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        & python -m whisper `
            $file.FullName `
            --model $Model `
            --language $Language `
            --output_format txt `
            --output_dir $tmp `
            --fp16 False
        if ($LASTEXITCODE -ne 0) { throw "whisper exited with code $LASTEXITCODE" }

        $produced = Join-Path $tmp "$stem.txt"
        if (-not (Test-Path -LiteralPath $produced)) {
            throw "whisper did not produce expected file: $produced"
        }
        Move-Item -LiteralPath $produced -Destination $transcript -Force
        Write-Host "Wrote: $transcript"
    }
    finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---- 2. Format transcript with speaker attribution (Claude) ----
$haveClaude = [bool](Get-Command claude -ErrorAction SilentlyContinue)

if ($SkipFormat) {
    Write-Host "Skip format (--SkipFormat)"
} elseif (Test-Path -LiteralPath $formatted) {
    Write-Host "Skip format (exists): $(Split-Path -Leaf $formatted)"
} elseif (-not $haveClaude) {
    Write-Warning "claude CLI not found — skipping speaker-attributed formatting (docx will fall back to plain bullets)"
} else {
    Write-Host "Formatting transcript with speaker attribution via claude ..."
    try {
        $formatPrompt = @"
You are reformatting a raw, unpunctuated meeting transcript provided via stdin. The transcript is from a single audio recording with multiple speakers but no diarization.

Your task:
1. Split the transcript into individual speaker turns based on context cues (people addressing each other by name, topic changes, conversational handoffs like "thanks", "go ahead", question-answer pairs).
2. Identify each speaker by NAME if you can infer it confidently from the context (e.g., one participant says "thanks Frank" - the next speaker is likely Frank; or someone introduces themselves). When unsure, label as "Speaker 1", "Speaker 2", etc., assigned consistently across the whole document. DO NOT guess names you are not confident about.
3. Add minimal punctuation and capitalization so the text reads naturally. DO NOT summarize, paraphrase, or omit any words from the original transcript - every word from the input must appear in the output.
4. Output as a Markdown bulleted list. One bullet per speaker turn. Format each bullet as: `- **Speaker Name:** turn text.`

If a single speaker has a very long uninterrupted stretch, you may split it into multiple consecutive bullets at natural sentence/topic boundaries, all attributed to the same speaker.

Output ONLY the bulleted markdown. No preamble, no headings, no commentary, no code fences.
"@

        $transcriptText = Get-Content -LiteralPath $transcript -Raw
        $generated = $transcriptText | & claude -p --output-format text $formatPrompt
        if ($LASTEXITCODE -ne 0) { throw "claude exited with code $LASTEXITCODE" }
        if ([string]::IsNullOrWhiteSpace($generated)) { throw "claude returned empty output" }

        Set-Content -LiteralPath $formatted -Value $generated -Encoding UTF8
        Write-Host "Wrote: $formatted"
    } catch {
        Write-Warning "speaker-attributed formatting failed: $($_.Exception.Message)"
    }
}

# ---- 3. Convert to .docx ----
if ($SkipDocx) {
    Write-Host "Skip docx (--SkipDocx)"
} elseif (Test-Path -LiteralPath $docx) {
    Write-Host "Skip docx (exists): $(Split-Path -Leaf $docx)"
} else {
    Write-Host "Building docx ..."
    try {
        $title  = $stem -replace '[_-]+', ' '
        $source = if (Test-Path -LiteralPath $formatted) { $formatted } else { $transcript }
        & python (Join-Path $helperDir 'md-to-docx.py') $source $docx --title $title
        if ($LASTEXITCODE -ne 0) { throw "md-to-docx.py exited with code $LASTEXITCODE" }
        Write-Host "Wrote: $docx (from $(Split-Path -Leaf $source))"
    } catch {
        Write-Warning "docx generation failed: $($_.Exception.Message)"
    }
}

# ---- 4. Generate meeting notes via Claude ----
if ($SkipNotes) {
    Write-Host "Skip notes (--SkipNotes)"
} elseif (Test-Path -LiteralPath $notes) {
    Write-Host "Skip notes (exists): $(Split-Path -Leaf $notes)"
} elseif (-not $haveClaude) {
    Write-Warning "claude CLI not found on PATH - skipping notes generation"
} else {
    Write-Host "Generating meeting notes via claude ..."
    try {
        $recordedDate = $file.LastWriteTime.ToString('yyyy-MM-dd')
        $notesPrompt = @"
You are an executive assistant producing meeting notes from a raw, unpunctuated transcript provided via stdin.

Produce a single Markdown document with these sections (omit any section with no content):

# <inferred meeting title>

**Date:** $recordedDate

## Attendees
(Best guesses from names mentioned, with affiliation if mentioned in the transcript.)

## Summary
(3-6 sentences on what was discussed.)

## Key Takeaways
(Bulleted, high-signal insights and conclusions from the discussion. Each bullet is a self-contained statement a reader could grasp without reading the full transcript. Distinct from "Key Decisions": takeaways are what was learned or observed; decisions are specific commitments made.)

## Key Decisions
(Bullet list of specific decisions or commitments made during the meeting.)

## Action Items
(Bullet list, format: "- [ ] <action> - <owner if known> - <due date if known>")

## Risks / Concerns
(Bullet list of risks, blockers, or concerns raised that aren't already captured as action items or open questions.)

## Open Questions
(Anything left unresolved or requiring follow-up.)

Output ONLY the markdown. No preamble, no code fences, no commentary. Use real line breaks between sections.
"@

        # Prefer the speaker-attributed transcript if available - better context for note-taking.
        $notesSource = if (Test-Path -LiteralPath $formatted) { $formatted } else { $transcript }
        $sourceText = Get-Content -LiteralPath $notesSource -Raw
        $generated = $sourceText | & claude -p --output-format text $notesPrompt
        if ($LASTEXITCODE -ne 0) { throw "claude exited with code $LASTEXITCODE" }
        if ([string]::IsNullOrWhiteSpace($generated)) { throw "claude returned empty output" }

        Set-Content -LiteralPath $notes -Value $generated -Encoding UTF8
        Write-Host "Wrote: $notes"
    } catch {
        Write-Warning "notes generation failed: $($_.Exception.Message)"
    }
}
