#!/usr/bin/env bash
set -euo pipefail

RUNTIME_DIR="$(cd "${1:?runtime directory is required}" && pwd)"
BIN_DIR="${RUNTIME_DIR}/bin"
FFMPEG_BIN="${BIN_DIR}/ffmpeg"
FFPROBE_BIN="${BIN_DIR}/ffprobe"
X265_BIN="${BIN_DIR}/x265"
DOVI_TOOL_BIN="${BIN_DIR}/dovi_tool"
VULKAN_ICD="${RUNTIME_DIR}/etc/vulkan/icd.d/MoltenVK_icd.json"

if [[ -f "${BIN_DIR}/ffmpeg.exe" ]]; then
  FFMPEG_BIN="${BIN_DIR}/ffmpeg.exe"
  FFPROBE_BIN="${BIN_DIR}/ffprobe.exe"
  X265_BIN="${BIN_DIR}/x265.exe"
  DOVI_TOOL_BIN="${BIN_DIR}/dovi_tool.exe"
fi

if [[ -f "${VULKAN_ICD}" ]]; then
  # macOS artifact 随包 MoltenVK；验证时也固定使用随包 ICD，避免误读 runner 系统环境。
  export VK_ICD_FILENAMES="${VULKAN_ICD}"
fi

if [[ "$(uname -s)" == "Linux" ]]; then
  # 客户端也会为 bundled runtime 设置该路径；验证必须使用同一加载模型。
  export LD_LIBRARY_PATH="${RUNTIME_DIR}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
fi

"${FFMPEG_BIN}" -hide_banner -version >/dev/null
"${FFPROBE_BIN}" -hide_banner -version >/dev/null
"${X265_BIN}" --version >/dev/null 2>&1
"${DOVI_TOOL_BIN}" --version >/dev/null

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

# x265 的 RPU 参数是正式转码链路的硬依赖，不能只验证 FFmpeg libx265 wrapper。
X265_HELP="$("${X265_BIN}" --fullhelp 2>&1 || true)"
if [[ "${X265_HELP}" != *"--dolby-vision-profile"* || "${X265_HELP}" != *"--dolby-vision-rpu"* ]]; then
  echo "x265 CLI is missing Dolby Vision RPU options" >&2
  exit 1
fi

DOVI_TOOL_HELP="$("${DOVI_TOOL_BIN}" --help 2>&1)"
for command in extract-rpu inject-rpu demux export info generate; do
  if [[ "${DOVI_TOOL_HELP}" != *"${command}"* ]]; then
    echo "dovi_tool is missing required command: ${command}" >&2
    exit 1
  fi
done

# 真实跑一条最小 RPU 编码链路，覆盖工具存在但版本或参数不兼容的情况。
SMOKE_DIR="$(mktemp -d)"
trap 'rm -rf "${SMOKE_DIR}"' EXIT
cat >"${SMOKE_DIR}/rpu.json" <<'JSON'
{
  "cm_version": "V40",
  "length": 10,
  "level6": {
    "max_display_mastering_luminance": 1000,
    "min_display_mastering_luminance": 1,
    "max_content_light_level": 1000,
    "max_frame_average_light_level": 400
  }
}
JSON

cat >"${SMOKE_DIR}/rpu-p5.json" <<'JSON'
{
  "cm_version": "V40",
  "profile": "5",
  "length": 10,
  "level6": {
    "max_display_mastering_luminance": 1000,
    "min_display_mastering_luminance": 1,
    "max_content_light_level": 1000,
    "max_frame_average_light_level": 400
  }
}
JSON

"${DOVI_TOOL_BIN}" generate -j "${SMOKE_DIR}/rpu.json" -o "${SMOKE_DIR}/RPU.bin" >/dev/null
"${DOVI_TOOL_BIN}" generate -j "${SMOKE_DIR}/rpu-p5.json" -o "${SMOKE_DIR}/RPU-p5.bin" >/dev/null
"${FFMPEG_BIN}" -hide_banner -v error -y \
  -f lavfi -i "testsrc2=s=64x64:r=24" \
  -frames:v 10 -pix_fmt yuv420p10le -strict -1 -f yuv4mpegpipe \
  "${SMOKE_DIR}/input.y4m"
"${X265_BIN}" --y4m --input "${SMOKE_DIR}/input.y4m" \
  --output "${SMOKE_DIR}/encoded.hevc" \
  --frames 10 --profile main10 --preset ultrafast --crf 28 \
  --vbv-maxrate 10000 --vbv-bufsize 10000 --hrd \
  --dolby-vision-profile 8.1 --dolby-vision-rpu "${SMOKE_DIR}/RPU.bin" \
  --colorprim bt2020 --transfer smpte2084 --colormatrix bt2020nc --range limited \
  --master-display "G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1)" \
  --max-cll "1000,400" >/dev/null 2>&1
"${X265_BIN}" --y4m --input "${SMOKE_DIR}/input.y4m" \
  --output "${SMOKE_DIR}/encoded-p5.hevc" \
  --frames 10 --profile main10 --preset ultrafast --crf 28 \
  --vbv-maxrate 10000 --vbv-bufsize 10000 --hrd \
  --dolby-vision-profile 5 --dolby-vision-rpu "${SMOKE_DIR}/RPU-p5.bin" \
  --colorprim bt2020 --transfer smpte2084 --colormatrix ipt-pq-c2 --range full >/dev/null 2>&1
"${DOVI_TOOL_BIN}" extract-rpu -i "${SMOKE_DIR}/encoded.hevc" -o "${SMOKE_DIR}/roundtrip-rpu.bin" >/dev/null
"${DOVI_TOOL_BIN}" info -i "${SMOKE_DIR}/roundtrip-rpu.bin" -f 9 >/dev/null

if [[ ! -s "${SMOKE_DIR}/encoded.hevc" || ! -s "${SMOKE_DIR}/roundtrip-rpu.bin" ]]; then
  echo "Dolby Vision RPU smoke test did not produce valid artifacts" >&2
  exit 1
fi

# 应用正式路径通过 FFmpeg libx265 wrapper 透传逐帧 RPU，必须同时覆盖 P8.1 和 P5。
"${FFMPEG_BIN}" -hide_banner -v error -y -fflags +genpts -r 24 \
  -i "${SMOKE_DIR}/encoded.hevc" -an -c:v libx265 -profile:v main10 \
  -preset ultrafast -crf 28 -pix_fmt yuv420p10le -dolbyvision 1 \
  -x265-params "dolby-vision-profile=8.1:vbv-maxrate=10000:vbv-bufsize=10000:hrd=1:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:range=limited:hdr10=1" \
  -f matroska "${SMOKE_DIR}/wrapper-p81.mkv"
"${FFMPEG_BIN}" -hide_banner -v error -y -fflags +genpts -r 24 \
  -i "${SMOKE_DIR}/encoded-p5.hevc" -an -c:v libx265 -profile:v main10 \
  -preset ultrafast -crf 28 -pix_fmt yuv420p10le -dolbyvision 1 \
  -x265-params "dolby-vision-profile=5:vbv-maxrate=10000:vbv-bufsize=10000:hrd=1:colorprim=bt2020:transfer=smpte2084:colormatrix=ipt-pq-c2:range=full" \
  -f matroska "${SMOKE_DIR}/wrapper-p5.mkv"

for profile in p81 p5; do
  "${FFMPEG_BIN}" -hide_banner -v error -y \
    -i "${SMOKE_DIR}/wrapper-${profile}.mkv" -map 0:v:0 -c:v copy \
    -bsf:v hevc_mp4toannexb -f hevc "${SMOKE_DIR}/wrapper-${profile}.hevc"
  "${DOVI_TOOL_BIN}" extract-rpu \
    -i "${SMOKE_DIR}/wrapper-${profile}.hevc" \
    -o "${SMOKE_DIR}/wrapper-${profile}-rpu.bin" >/dev/null
done

"${DOVI_TOOL_BIN}" export -i "${SMOKE_DIR}/RPU.bin" \
  --data "all=${SMOKE_DIR}/source-p81.json" >/dev/null
"${DOVI_TOOL_BIN}" export -i "${SMOKE_DIR}/wrapper-p81-rpu.bin" \
  --data "all=${SMOKE_DIR}/output-p81.json" >/dev/null
"${DOVI_TOOL_BIN}" export -i "${SMOKE_DIR}/RPU-p5.bin" \
  --data "all=${SMOKE_DIR}/source-p5.json" >/dev/null
"${DOVI_TOOL_BIN}" export -i "${SMOKE_DIR}/wrapper-p5-rpu.bin" \
  --data "all=${SMOKE_DIR}/output-p5.json" >/dev/null

python3 - "${SMOKE_DIR}" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])

def canonicalize(value, parent_key=None):
    if isinstance(value, dict):
        return {
            key: canonicalize(child, key)
            for key, child in value.items()
            if key != "rpu_data_crc32"
        }
    if isinstance(value, list):
        items = [canonicalize(child) for child in value]
        if parent_key == "ext_metadata_blocks":
            items.sort(key=lambda item: next(iter(item), ""))
        return items
    return value

for profile in ("p81", "p5"):
    source = json.loads((root / f"source-{profile}.json").read_text())
    output = json.loads((root / f"output-{profile}.json").read_text())
    if canonicalize(source) != canonicalize(output):
        raise SystemExit(f"FFmpeg wrapper changed {profile} RPU semantics")
PY

P81_PROBE="$(${FFPROBE_BIN} -v error -select_streams v:0 -show_entries stream_side_data -of json "${SMOKE_DIR}/wrapper-p81.mkv")"
P5_PROBE="$(${FFPROBE_BIN} -v error -select_streams v:0 -show_entries stream_side_data -of json "${SMOKE_DIR}/wrapper-p5.mkv")"
if [[ "${P81_PROBE}" != *'"dv_profile": 8'* || "${P81_PROBE}" != *'"dv_bl_signal_compatibility_id": 1'* ]]; then
  echo "FFmpeg wrapper did not produce Dolby Vision Profile 8.1" >&2
  exit 1
fi
if [[ "${P5_PROBE}" != *'"dv_profile": 5'* || "${P5_PROBE}" != *'"dv_bl_signal_compatibility_id": 0'* ]]; then
  echo "FFmpeg wrapper did not produce Dolby Vision Profile 5" >&2
  exit 1
fi

if [[ -f "${VULKAN_ICD}" ]]; then
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

echo "Encode Lab FFmpeg runtime verification passed: ${RUNTIME_DIR}"
