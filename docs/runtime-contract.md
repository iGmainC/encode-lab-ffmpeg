# Runtime Contract

Encode Lab expects the bundled FFmpeg runtime to provide stable behavior across client machines.

## Required commands

- `ffmpeg`
- `ffprobe`

## Required FFmpeg capabilities

- `zscale` filter
- `tonemap` filter
- `libx264` encoder
- `libx265` encoder
- `libaom-av1` encoder
- `libsvtav1` encoder
- `libvpx-vp9` encoder
- `dav1d` decoder

## Preview behavior protected by this runtime

HDR / Dolby Vision preview first maps frames to SDR:

```text
HDR source -> zscale -> tonemap -> zscale BT.709 -> preview PNG
```

If a client uses system FFmpeg without `zscale`, Encode Lab can fall back to normal preview, but the bundled runtime should make the SDR path available by default.

## Artifact layout

```text
bin/
  ffmpeg
  ffprobe
lib/
  platform dynamic libraries when needed
manifest.json
SHA256SUMS
LEGAL.md
```

On Windows, DLLs may live beside `ffmpeg.exe` in `bin/`.
