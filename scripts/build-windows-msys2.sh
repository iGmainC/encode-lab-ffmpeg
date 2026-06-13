#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-windows-x64}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/versions.env"

SRC_DIR="${ROOT_DIR}/build/src"
BUILD_DIR="${ROOT_DIR}/build/${TARGET}"
INSTALL_DIR="${ROOT_DIR}/build/install/${TARGET}"
DIST_DIR="${ROOT_DIR}/dist/${TARGET}"
ARCHIVE="${SRC_DIR}/ffmpeg-${FFMPEG_VERSION}.tar.xz"

mkdir -p "${SRC_DIR}" "${BUILD_DIR}" "${INSTALL_DIR}" "${DIST_DIR}"

# Windows 也从同一份源码构建，保持滤镜和编码器能力与 Unix 产物一致。
if [[ ! -f "${ARCHIVE}" ]]; then
  curl -L "${FFMPEG_SOURCE_URL}" -o "${ARCHIVE}"
fi

# 独立构建目录可以避免 MSYS2 重跑时复用旧的 configure 缓存。
if [[ ! -d "${SRC_DIR}/ffmpeg-${FFMPEG_VERSION}" ]]; then
  tar -xf "${ARCHIVE}" -C "${SRC_DIR}"
fi

rsync -a --delete "${SRC_DIR}/ffmpeg-${FFMPEG_VERSION}/" "${BUILD_DIR}/"

pushd "${BUILD_DIR}" >/dev/null
# MinGW 产物启用与 macOS/Linux 相同的 GPL 编解码器和 zimg 滤镜能力。
./configure \
  "--prefix=${INSTALL_DIR}" \
  --target-os=mingw32 \
  --arch=x86_64 \
  --disable-debug \
  --disable-doc \
  --disable-ffplay \
  --enable-gpl \
  --enable-version3 \
  --enable-libaom \
  --enable-libdav1d \
  --enable-libsvtav1 \
  --enable-libvpx \
  --enable-libx264 \
  --enable-libx265 \
  --enable-libzimg
make -j"$(nproc)"
make install
popd >/dev/null

# Windows 需要把运行时 DLL 放在 exe 旁边，方便 Electron 客户端直接调用。
"${ROOT_DIR}/scripts/stage-windows.sh" "${TARGET}" "${INSTALL_DIR}" "${DIST_DIR}"
"${ROOT_DIR}/scripts/write-manifest.sh" "${TARGET}" "${DIST_DIR}"
"${ROOT_DIR}/scripts/verify-runtime.sh" "${DIST_DIR}/bin/ffmpeg.exe"
