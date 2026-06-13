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

# 这里验证的是 Encode Lab 真实依赖的能力，不只验证二进制能启动。
"${FFMPEG_BIN}" -hide_banner -filters | awk '{ print $2 }' | grep -qx "zscale"
"${FFMPEG_BIN}" -hide_banner -filters | awk '{ print $2 }' | grep -qx "tonemap"
"${FFMPEG_BIN}" -hide_banner -encoders | grep -q "libx265"

echo "Encode Lab FFmpeg runtime verification passed: ${FFMPEG_BIN}"
