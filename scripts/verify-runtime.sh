#!/usr/bin/env bash
set -euo pipefail

FFMPEG_BIN="${1:?ffmpeg binary path is required}"
BIN_DIR="$(cd "$(dirname "${FFMPEG_BIN}")" && pwd)"
RUNTIME_DIR="$(cd "${BIN_DIR}/.." && pwd)"
VULKAN_ICD="${RUNTIME_DIR}/etc/vulkan/icd.d/MoltenVK_icd.json"

if [[ "$(basename "${FFMPEG_BIN}")" == *.exe ]]; then
  FFPROBE_BIN="${BIN_DIR}/ffprobe.exe"
else
  FFPROBE_BIN="${BIN_DIR}/ffprobe"
fi

if [[ -f "${VULKAN_ICD}" ]]; then
  # macOS artifact 随包 MoltenVK；验证时也固定使用随包 ICD，避免误读 runner 系统环境。
  export VK_ICD_FILENAMES="${VULKAN_ICD}"
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
require_filter "libplacebo"
require_filter "zscale"
require_filter "tonemap"
require_encoder "libx264"
require_encoder "libx265"
require_encoder "libaom-av1"
require_encoder "libsvtav1"
require_encoder "libvpx-vp9"

# Dolby Vision 预览 SDR 映射依赖 libplacebo 读取 RPU，不能只验证 filter 名称存在。
LIBPLACEBO_HELP="$("${FFMPEG_BIN}" -hide_banner -h filter=libplacebo)"
if [[ "${LIBPLACEBO_HELP}" != *"apply_dolbyvision"* ]]; then
  echo "libplacebo filter is missing apply_dolbyvision support" >&2
  exit 1
fi

if [[ -f "${VULKAN_ICD}" ]]; then
  SMOKE_DIR="$(mktemp -d)"
  trap 'rm -rf "${SMOKE_DIR}"' EXIT

  # 真实跑一次 libplacebo，覆盖 macOS 只存在 filter 但缺少可用 Vulkan ICD 的情况。
  "${FFMPEG_BIN}" -hide_banner -v error -y \
    -f lavfi -i "testsrc2=s=64x64:d=0.1" \
    -vf "format=yuv420p,libplacebo=colorspace=bt709:color_primaries=bt709:color_trc=bt709:range=tv,format=rgb24" \
    -frames:v 1 \
    -update 1 \
    "${SMOKE_DIR}/libplacebo.png" >/dev/null

  if [[ ! -s "${SMOKE_DIR}/libplacebo.png" ]]; then
    echo "libplacebo smoke test did not produce a preview frame" >&2
    exit 1
  fi
fi

echo "Encode Lab FFmpeg runtime verification passed: ${FFMPEG_BIN}"
