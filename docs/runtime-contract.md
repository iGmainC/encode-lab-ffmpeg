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

Formal Dolby Vision transcode uses the bundled FFmpeg `libx265` wrapper to preserve decoded RPU side data, and independently verifies the result with `dovi_tool`:

```text
ffprobe validates a supported single-layer Profile 5 or Profile 8.1 source
ffprobe scans packet PTS values to prove constant frame timing and count frames
FFmpeg decodes and re-encodes the base layer through 10-bit libx265 with -dolbyvision 1
FFmpeg copies source audio, subtitles, attachments, metadata and chapters into MKV
dovi_tool extracts source/output RPU and exports per-frame semantic data
ffprobe and dovi_tool validate profile, compatibility, frame count and RPU equality
Encode Lab publishes the verified partial file with no-clobber semantics
```

The x265 CLI remains part of the runtime because the build smoke test uses its explicit `--dolby-vision-profile` and `--dolby-vision-rpu` path to prove that the pinned x265 library has the required feature set. It is not the application's primary transcode process.

The first supported product path keeps source resolution and frame rate and does not allow trimming, resizing, frame insertion, VFR input or 2-pass encoding while RPU preservation is enabled. Profile 7 enhancement layers are outside this single-layer contract.

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

## Provenance and platform baseline

Every release manifest records the runtime repository commit, core source archive SHA-256 values, target-specific build dependency sources and the target's minimum system version. Current release artifacts target macOS 15 on Apple Silicon and glibc 2.35 on Linux x64. Runtime release tags are immutable; a rebuild must use a new `rpu.N` version.
