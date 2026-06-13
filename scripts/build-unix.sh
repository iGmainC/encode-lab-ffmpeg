#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:?target is required}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/versions.env"

SRC_DIR="${ROOT_DIR}/build/src"
BUILD_DIR="${ROOT_DIR}/build/${TARGET}"
INSTALL_DIR="${ROOT_DIR}/build/install/${TARGET}"
DIST_DIR="${ROOT_DIR}/dist/${TARGET}"
ARCHIVE="${SRC_DIR}/ffmpeg-${FFMPEG_VERSION}.tar.xz"

mkdir -p "${SRC_DIR}" "${BUILD_DIR}" "${INSTALL_DIR}" "${DIST_DIR}"

# 下载固定版本源码，避免 GitHub runner 使用系统 FFmpeg 造成能力漂移。
if [[ ! -f "${ARCHIVE}" ]]; then
  curl -L "${FFMPEG_SOURCE_URL}" -o "${ARCHIVE}"
fi

# 每个目标使用独立构建目录，避免不同平台或重跑时污染 configure 结果。
if [[ ! -d "${SRC_DIR}/ffmpeg-${FFMPEG_VERSION}" ]]; then
  tar -xf "${ARCHIVE}" -C "${SRC_DIR}"
fi

rsync -a --delete "${SRC_DIR}/ffmpeg-${FFMPEG_VERSION}/" "${BUILD_DIR}/"

# 这些开关定义 Encode Lab 客户端依赖的 runtime 能力边界。
CONFIGURE_FLAGS=(
  "--prefix=${INSTALL_DIR}"
  "--disable-debug"
  "--disable-doc"
  "--disable-ffplay"
  "--enable-gpl"
  "--enable-version3"
  "--enable-pic"
  "--enable-libdav1d"
  "--enable-libmp3lame"
  "--enable-libopus"
  "--enable-libsvtav1"
  "--enable-libvpx"
  "--enable-libx264"
  "--enable-libx265"
  "--enable-libzimg"
)

if [[ "${TARGET}" == darwin-* ]]; then
  # macOS 客户端仍可使用系统硬件编解码能力，但核心滤镜能力由本仓库固定。
  CONFIGURE_FLAGS+=("--enable-audiotoolbox" "--enable-videotoolbox")
fi

pushd "${BUILD_DIR}" >/dev/null
./configure "${CONFIGURE_FLAGS[@]}"
make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu)"
make install
popd >/dev/null

case "${TARGET}" in
  # 分平台整理可执行文件和依赖库，保证 artifact 可独立分发。
  linux-*) "${ROOT_DIR}/scripts/stage-linux.sh" "${TARGET}" "${INSTALL_DIR}" "${DIST_DIR}" ;;
  darwin-*) "${ROOT_DIR}/scripts/stage-macos.sh" "${TARGET}" "${INSTALL_DIR}" "${DIST_DIR}" ;;
  *) echo "unsupported target: ${TARGET}" >&2; exit 1 ;;
esac

"${ROOT_DIR}/scripts/write-manifest.sh" "${TARGET}" "${DIST_DIR}"
"${ROOT_DIR}/scripts/verify-runtime.sh" "${DIST_DIR}/bin/ffmpeg"
