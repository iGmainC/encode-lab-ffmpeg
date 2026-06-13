#!/usr/bin/env bash
set -euo pipefail

FFMPEG_BIN="${1:?ffmpeg binary path is required}"
BIN_DIR="$(cd "$(dirname "${FFMPEG_BIN}")" && pwd)"

if [[ "$(basename "${FFMPEG_BIN}")" == *.exe ]]; then
  FFPROBE_BIN="${BIN_DIR}/ffprobe.exe"
else
  FFPROBE_BIN="${BIN_DIR}/ffprobe"
fi

"${FFMPEG_BIN}" -hide_banner -version >/dev/null
"${FFPROBE_BIN}" -hide_banner -version >/dev/null

FILTERS="$("${FFMPEG_BIN}" -hide_banner -filters)"
ENCODERS="$("${FFMPEG_BIN}" -hide_banner -encoders)"

require_filter() {
  local name="${1:?filter name is required}"
  # 避免 `grep -q` 提前关闭管道导致 ffmpeg 在 pipefail 下返回 141。
  if ! awk -v name="${name}" '$2 == name { found = 1 } END { exit found ? 0 : 1 }' <<<"${FILTERS}"; then
    echo "missing required FFmpeg filter: ${name}" >&2
    exit 1
  fi
}

require_encoder() {
  local name="${1:?encoder name is required}"
  # ffmpeg -encoders 的第二列是 encoder 名称，例如 `libx265`。
  if ! awk -v name="${name}" '$2 == name { found = 1 } END { exit found ? 0 : 1 }' <<<"${ENCODERS}"; then
    echo "missing required FFmpeg encoder: ${name}" >&2
    exit 1
  fi
}

# 这里验证的是 Encode Lab 真实依赖的能力，不只验证二进制能启动。
require_filter "zscale"
require_filter "tonemap"
require_encoder "libx264"
require_encoder "libx265"
require_encoder "libaom-av1"
require_encoder "libsvtav1"
require_encoder "libvpx-vp9"

echo "Encode Lab FFmpeg runtime verification passed: ${FFMPEG_BIN}"
