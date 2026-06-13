# Legal Notes

This repository builds FFmpeg binaries for Encode Lab.

The build enables GPL components such as `libx264` and `libx265`. As a result, generated FFmpeg binaries are distributed under GPL terms as described by the FFmpeg project and the linked libraries.

Rules for this repository:

- Do not use `--enable-nonfree`.
- Keep source versions and configure flags in versioned scripts.
- Keep generated artifact manifests and checksums.
- Keep this repository or release source references available whenever binaries are distributed.

This file is not legal advice. It records the engineering constraints used by Encode Lab.

