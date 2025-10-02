# Simple Video Conversion Script (`convert.sh`)

A lightweight wrapper around `ffmpeg` to quickly convert / transcode a single video file with a chosen target bitrate and customizable codecs.

---

## Features
 
- Accepts both conventional and "dash" positional styles:
  - `./convert.sh input.mp4 1500k`
  - `./convert.sh input.mp4 1500` (auto becomes `1500k`)
  - `./convert.sh -input.mp4 -1500` (tolerates your original dash style)
- Auto‑appends `k` when only digits are provided
- Output naming: `name-<SUFFIX>.ext` (avoids overwrite by adding `-1`, `-2`, ...)
- If you pass a path (e.g. `Media/video.mkv`), the output is written to the same directory: `Media/video-x265.mkv`
- Dry‑run mode (`-n` / `--dry-run`) prints the command without executing
- Environment variable overrides for suffix, codecs, and extra flags
- Cleans up partial output if interrupted (Ctrl+C / SIGINT / SIGTERM)

---

## Current Defaults (based on script state)

| Setting | Default | Notes |
|---------|---------|-------|
| `VC_SUFFIX` | `x265` | Used in output filename: `input-x265.ext` |
| `VC_VCODEC` | `hevc_nvenc` | NVIDIA HEVC encoder. If unavailable on your system (e.g. macOS), override (see below). |
| `VC_ACODEC` | `libfdk_aac` | Change to `aac`, `libopus`, etc., to re-encode. |
| `VC_EXTRA` | (empty) | Additional raw ffmpeg args appended verbatim. |

If your ffmpeg build does not support `hevc_nvenc` (common on macOS without NVIDIA), pick one of:

- `VC_VCODEC=libx265` (CPU, slower but compatible)
- `VC_VCODEC=libx264` (if H.264 is fine)
- `VC_VCODEC=hevc_videotoolbox` (macOS hardware HEVC)

Example:

```bash
VC_VCODEC=hevc_videotoolbox ./convert.sh movie.mov 2500k
```

---

## Installation

1. Ensure `ffmpeg` is installed.

  - macOS (Homebrew): `brew install ffmpeg`
2. Make script executable:
   
```bash
chmod +x convert.sh
```
3. (Optional) Add to PATH:
   
```bash
ln -s "$PWD/convert.sh" /usr/local/bin/convert-video
```
Then call with `convert-video input.mkv 1800k`.

---

## Basic Usage

```bash
./convert.sh input.mkv 1500k         # target 1500 kbps video bitrate
./convert.sh input.mkv 1500          # becomes 1500k
./convert.sh -input.mkv -1500        # legacy tolerated style
./convert.sh -n input.mkv 2M         # dry run (prints command only)
```

Produces (example, same directory as input):
```
input-x265.mkv
```
If that already exists:
```
input-x265-1.mkv
input-x265-2.mkv
```

---

## Help Screen

```bash
./convert.sh -h
```
(Shows embedded examples extracted from script comments.)

---

## Environment Variables

You can override behavior per invocation:
```bash
VC_SUFFIX=SMALL \
VC_VCODEC=libx265 \
VC_ACODEC=aac \
VC_EXTRA='-crf 28 -preset slow' \
./convert.sh input.mkv 1200k
```
Explanation:
- `VC_SUFFIX=SMALL` → output: `input-SMALL.mkv`
- `VC_VCODEC=libx265` → software x265 encoder
- `VC_ACODEC=aac` → re-encode audio to AAC (defaults to copy otherwise)
- `VC_EXTRA='-crf 28 -preset slow'` → appended literally after bitrate arguments

Note: If you provide both `-b:v` via script and CRF options, you may want to neutralize bitrate control by also adding `-b:v 0` (for quality-based mode). Example:

```bash
VC_EXTRA='-crf 23 -preset medium -b:v 0' ./convert.sh input.mkv 1k
```
(The `1k` is a placeholder to satisfy the script argument requirement.)

---

## Output Naming Logic

1. Determine directory of input (or `.` if none supplied)
2. Derive base name (strip path & extension)
3. Append `-<suffix>` (default `-x265`)
4. Add original extension
5. If file exists in that directory, append `-1`, `-2`, etc.

Pseudo examples:

```
Input:  Example.File.mp4
Output: Example.File-x265.mp4

Input:  Media/Example.File.mp4
Output: Media/Example.File-x265.mp4
```

---

## Dry Run Mode

Use when testing options:
```bash
./convert.sh -n input.mkv 2000k
```
Shows the fully assembled `ffmpeg` command but does not run it.

---

## Error Handling

- Missing arguments → exits with an error message
- Input file not found → error
- Warns on unusual bitrate formats (expects e.g. `800k`, `2M`, `1500k`)
- Cleans up partially written output if interrupted (signal trap)

---

## Bitrate Notes

Accepts forms:

- `800k` (kilobits per second)
- `2M`   (megabits per second)
- Plain digits (auto `k`): `1500` → `1500k`

If you prefer constant quality (CRF) over fixed bitrate:
```bash
VC_VCODEC=libx265 VC_EXTRA='-crf 24 -preset medium -b:v 0' ./convert.sh input.mkv 1k
```

---

## GPU / Hardware Encoding Tips

| Platform | Common Option | Notes |
|----------|---------------|-------|
| NVIDIA (Linux/Windows) | `hevc_nvenc` / `h264_nvenc` | Fast; ensure recent driver & ffmpeg compiled with NVENC. |
| macOS (Apple Silicon / Intel) | `hevc_videotoolbox` / `h264_videotoolbox` | Uses VideoToolbox hardware. |
| Generic CPU | `libx264` / `libx265` | Slower; high quality; tune with `-preset`. |

Examples:

```bash
VC_VCODEC=h264_nvenc ./convert.sh input.mkv 3500k
VC_VCODEC=hevc_videotoolbox ./convert.sh input.mov 2800k
VC_VCODEC=libx264 VC_EXTRA='-preset slow -crf 22 -b:v 0' ./convert.sh input.mkv 1k
```

---

## Advanced Examples

Two-pass style (manual, if you want deterministic bitrate with software encoder):
```bash
# Pass 1
ffmpeg -y -i input.mkv -c:v libx265 -b:v 1500k -pass 1 -an -f null /dev/null
# Pass 2
ffmpeg -i input.mkv -c:v libx265 -b:v 1500k -pass 2 -c:a aac output-x265.mkv
```
(You could extend the script to automate this—ask if you'd like it added.)

Batch convert all `.mkv` in a folder (example helper loop):
```bash
for f in *.mkv; do
  ./convert.sh "$f" 1800k
done
```

Only process files not yet converted (suffix `x265`):
```bash
for f in *.mkv; do
  [[ -f ${f%.*}-x265.${f##*.} ]] && continue
  ./convert.sh "$f" 1800k
done
```

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Usage / validation error |
| 130 | Interrupted (cleanup triggered) |

---

## FAQ

**Q: Bitrate seems low / quality bad?**  
Increase kbps or switch to CRF mode (`VC_EXTRA='-crf 20 -b:v 0'`).

**Q: Audio not changing?**  
Default is `copy`. Set `VC_ACODEC=aac` or another codec.

**Q: `Unknown encoder 'hevc_nvenc'`?**  
Use `VC_VCODEC=libx265` or `VC_VCODEC=hevc_videotoolbox` (macOS) depending on hardware.

**Q: Can I force container format?**  
Yes—just change output extension manually (e.g. rename input or modify script). ffmpeg chooses by extension.

---

## Possible Future Enhancements

- Built-in CRF mode flag (`--crf` without needing dummy bitrate)
- Automatic hardware encoder detection / fallback
- Two-pass bitrate mode (`--two-pass`)
- Directory batch mode (`--all *.mkv`)
- Target size (MB) → computed bitrate

Open an issue or request if you'd like any of these added.

---

## License

Personal utility script; treat as public domain / CC0. Use at your own risk.

---

## Quick Reference Cheat Sheet

```bash
# Basic
./convert.sh video.mkv 1800k

# Dry run
./convert.sh -n video.mkv 1800k

# Override codecs (macOS hardware HEVC)
VC_VCODEC=hevc_videotoolbox ./convert.sh video.mov 2500k

# Re-encode audio to AAC
VC_ACODEC=aac ./convert.sh video.mkv 1500k

# CRF quality mode (x265)
VC_VCODEC=libx265 VC_EXTRA='-crf 24 -preset medium -b:v 0' ./convert.sh video.mkv 1k
```

---
Happy encoding! If you want enhancements, just ask.
