#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:?target is required}"
DIST_DIR="${2:?dist dir is required}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/versions.env"

if [[ "${TARGET}" == windows-* ]]; then
  FFMPEG_BIN="${DIST_DIR}/bin/ffmpeg.exe"
else
  FFMPEG_BIN="${DIST_DIR}/bin/ffmpeg"
fi

# manifest 记录可审计的构建能力，客户端后续可用它做版本和能力判断。
FFMPEG_VERSION_LINE="$("${FFMPEG_BIN}" -hide_banner -version | head -n 1 | sed 's/"/\\"/g')"
BUILT_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

if command -v shasum >/dev/null 2>&1; then
  CHECKSUM_CMD=(shasum -a 256)
else
  CHECKSUM_CMD=(sha256sum)
fi

cat >"${DIST_DIR}/manifest.json" <<JSON
{
  "name": "encode-lab-ffmpeg-runtime",
  "target": "${TARGET}",
  "ffmpegVersion": "${FFMPEG_VERSION}",
  "ffmpegVersionLine": "${FFMPEG_VERSION_LINE}",
  "builtAt": "${BUILT_AT}",
  "requiredFilters": ["libplacebo", "zscale", "tonemap"],
  "requiredEncoders": ["libx264", "libx265", "libaom-av1", "libsvtav1", "libvpx-vp9"],
  "licenseMode": "gpl"
}
JSON

(
  cd "${DIST_DIR}"
  # checksum 覆盖除 SHA256SUMS 自身外的所有文件，方便发布后校验下载完整性。
  find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 "${CHECKSUM_CMD[@]}" >SHA256SUMS
)
