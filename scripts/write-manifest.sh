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

if [[ "${TARGET}" == linux-* ]]; then
  # 与客户端启动环境一致，manifest 探测必须从 bundled lib 目录解析动态库。
  export LD_LIBRARY_PATH="${DIST_DIR}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
fi

capture_version_line() {
  local label="${1:?version label is required}"
  shift
  local output
  if ! output="$("$@" 2>&1)"; then
    echo "failed to query ${label} version" >&2
    echo "${output}" >&2
    return 1
  fi

  output="${output%%$'\n'*}"
  printf '%s' "${output//\"/\\\"}"
}

# manifest 记录可审计的构建能力，客户端后续可用它做版本和能力判断。
# 先完整捕获输出再取首行，避免 pipefail/SIGPIPE，并在动态库缺失时保留原始错误。
FFMPEG_VERSION_LINE="$(capture_version_line ffmpeg "${FFMPEG_BIN}" -hide_banner -version)"
X265_VERSION_LINE="$(capture_version_line x265 "${X265_BIN}" --version)"
DOVI_TOOL_VERSION_LINE="$(capture_version_line dovi_tool "${DOVI_TOOL_BIN}" --version)"
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
