# Runtime Contract

Encode Lab expects the bundled FFmpeg runtime to provide stable behavior across client machines.

## Required commands

- `ffmpeg`
- `ffprobe`
- `x265`
- `dovi_tool`

## Required FFmpeg capabilities

- `libplacebo` filter with `apply_dolbyvision`
- `zscale` filter
- `tonemap` filter
- `libx264` encoder
- `libx265` encoder
- `libaom-av1` encoder
- `libsvtav1` encoder
- `libvpx-vp9` encoder
- `dav1d` decoder
- x265 CLI with Dolby Vision profile 5 / 8.1 and external RPU input
- dovi_tool RPU extraction, conversion, demux, injection and inspection

## Dolby Vision transcode contract

Formal Dolby Vision transcode does not rely on FFmpeg's `-dolbyvision 1` switch alone:

```text
dovi_tool extracts or converts RPU
FFmpeg decodes the base layer to 10-bit Y4M
x265 CLI encodes frames with --dolby-vision-profile and --dolby-vision-rpu
FFmpeg remuxes the encoded video with source audio, subtitles and chapters
ffprobe and dovi_tool validate the final output
```

The first supported product path keeps source resolution and frame rate and does not allow trimming or frame insertion while RPU preservation is enabled.

## Preview behavior protected by this runtime

HDR / Dolby Vision preview first maps frames to SDR:

```text
Dolby Vision source -> libplacebo apply_dolbyvision -> BT.709 SDR -> preview PNG
HDR10 / HLG source -> libplacebo or zscale -> tonemap -> BT.709 SDR -> preview PNG
```

If a client uses system FFmpeg without the required SDR mapping filters, Encode Lab can fall back to normal preview, but the bundled runtime should make the SDR path available by default.

## Artifact layout

```text
bin/
  ffmpeg
  ffprobe
  x265
  dovi_tool
lib/
  platform dynamic libraries when needed
etc/vulkan/icd.d/
  MoltenVK_icd.json on macOS
manifest.json
SHA256SUMS
LEGAL.md
```

On Windows, DLLs may live beside `ffmpeg.exe` in `bin/`.

On macOS, bundled callers should set `VK_ICD_FILENAMES` to the packaged MoltenVK ICD manifest so `libplacebo` can create a Vulkan device through Metal without relying on host-level Vulkan setup.
