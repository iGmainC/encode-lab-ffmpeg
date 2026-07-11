#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:?target is required}"
DIST_DIR="${2:?dist dir is required}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/versions.env"

if [[ "${TARGET}" == windows-* ]]; then
  FFMPEG_BIN="${DIST_DIR}/bin/ffmpeg.exe"
  X265_BIN="${DIST_DIR}/bin/x265.exe"
  DOVI_TOOL_BIN="${DIST_DIR}/bin/dovi_tool.exe"
else
  FFMPEG_BIN="${DIST_DIR}/bin/ffmpeg"
  X265_BIN="${DIST_DIR}/bin/x265"
  DOVI_TOOL_BIN="${DIST_DIR}/bin/dovi_tool"
fi

# manifest 记录可审计的构建能力，客户端后续可用它做版本和能力判断。
# `head` 会提前关闭管道，配合 pipefail 可能让仍在输出的 x265 因 SIGPIPE 误判构建失败。
FFMPEG_VERSION_LINE="$("${FFMPEG_BIN}" -hide_banner -version | sed -n '1p' | sed 's/"/\\"/g')"
X265_VERSION_LINE="$("${X265_BIN}" --version 2>&1 | sed -n '1p' | sed 's/"/\\"/g')"
DOVI_TOOL_VERSION_LINE="$("${DOVI_TOOL_BIN}" --version 2>&1 | sed -n '1p' | sed 's/"/\\"/g')"
BUILT_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

if command -v shasum >/dev/null 2>&1; then
  CHECKSUM_CMD=(shasum -a 256)
else
  CHECKSUM_CMD=(sha256sum)
fi

cat >"${DIST_DIR}/manifest.json" <<JSON
{
  "name": "encode-lab-ffmpeg-runtime",
  "runtimeVersion": "${RUNTIME_VERSION}",
  "target": "${TARGET}",
  "ffmpegVersion": "${FFMPEG_VERSION}",
  "ffmpegVersionLine": "${FFMPEG_VERSION_LINE}",
  "x265VersionLine": "${X265_VERSION_LINE}",
  "doviToolVersion": "${DOVI_TOOL_VERSION}",
  "doviToolVersionLine": "${DOVI_TOOL_VERSION_LINE}",
  "builtAt": "${BUILT_AT}",
  "requiredCommands": ["ffmpeg", "ffprobe", "x265", "dovi_tool"],
  "requiredFilters": ["libplacebo", "zscale", "tonemap"],
  "requiredEncoders": ["libx264", "libx265", "libaom-av1", "libsvtav1", "libvpx-vp9"],
  "dolbyVisionProfiles": ["5", "8.1"],
  "licenseMode": "gpl"
}
JSON

(
  cd "${DIST_DIR}"
  # checksum 覆盖除 SHA256SUMS 自身外的所有文件，方便发布后校验下载完整性。
  find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 "${CHECKSUM_CMD[@]}" >SHA256SUMS
)
