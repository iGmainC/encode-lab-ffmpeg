#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:?target is required}"
PREFIX="${2:?install prefix is required}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/versions.env"

SRC_DIR="${ROOT_DIR}/build/src"
ARCHIVE="${SRC_DIR}/x265_${X265_VERSION}.tar.gz"
SOURCE_DIR="${SRC_DIR}/x265_${X265_VERSION}"
BUILD_ROOT="${ROOT_DIR}/build/x265/${TARGET}"
PARALLEL="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu)"
if [[ "${TARGET}" == darwin-* ]]; then
  RUNTIME_RPATH="@loader_path/../lib"
else
  RUNTIME_RPATH='$ORIGIN/../lib'
fi

mkdir -p "${SRC_DIR}"
if [[ ! -f "${ARCHIVE}" ]]; then
  curl -fL --retry 3 "${X265_SOURCE_URL}" -o "${ARCHIVE}.partial"
  mv "${ARCHIVE}.partial" "${ARCHIVE}"
fi

# 下载内容必须匹配固定摘要，避免上游同名归档变化后生成不可复现产物。
if command -v sha256sum >/dev/null 2>&1; then
  echo "${X265_SOURCE_SHA256}  ${ARCHIVE}" | sha256sum -c -
else
  echo "${X265_SOURCE_SHA256}  ${ARCHIVE}" | shasum -a 256 -c -
fi

if [[ ! -d "${SOURCE_DIR}" ]]; then
  tar -xzf "${ARCHIVE}" -C "${SRC_DIR}"
fi

rm -rf "${BUILD_ROOT}" "${PREFIX}"
mkdir -p "${BUILD_ROOT}/8bit"

# 先构建无 CLI 的 10-bit 静态库，再链接进主库；应用转码链路依赖 Main10 与 Dolby Vision RPU。
cmake -S "${SOURCE_DIR}/source" -B "${BUILD_ROOT}/10bit" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DHIGH_BIT_DEPTH=ON \
  -DEXPORT_C_API=OFF \
  -DENABLE_SHARED=OFF \
  -DENABLE_CLI=OFF \
  -DENABLE_HDR10_PLUS=ON
cmake --build "${BUILD_ROOT}/10bit" --parallel "${PARALLEL}"
cp "${BUILD_ROOT}/10bit/libx265.a" "${BUILD_ROOT}/8bit/libx265_main10.a"

cmake -S "${SOURCE_DIR}/source" -B "${BUILD_ROOT}/8bit" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_INSTALL_RPATH="${RUNTIME_RPATH}" \
  -DLINKED_10BIT=ON \
  -DEXTRA_LINK_FLAGS=-L. \
  -DEXTRA_LIB=x265_main10.a \
  -DENABLE_SHARED=ON \
  -DENABLE_CLI=ON
cmake --build "${BUILD_ROOT}/8bit" --parallel "${PARALLEL}"
cmake --install "${BUILD_ROOT}/8bit"

echo "x265 ${X265_VERSION} built for ${TARGET}: ${PREFIX}"
