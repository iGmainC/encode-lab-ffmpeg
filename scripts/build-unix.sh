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
DOVI_TOOL_ARCHIVE="${SRC_DIR}/dovi_tool-${DOVI_TOOL_VERSION}.tar.gz"
DOVI_TOOL_SRC="${SRC_DIR}/dovi_tool-${DOVI_TOOL_VERSION}"
X265_PREFIX="${ROOT_DIR}/build/x265/${TARGET}/install"

mkdir -p "${SRC_DIR}" "${BUILD_DIR}" "${INSTALL_DIR}" "${DIST_DIR}"

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}

download_verified_archive() {
  local url="${1:?source URL is required}"
  local output="${2:?archive path is required}"
  local expected="${3:?archive SHA-256 is required}"
  local partial="${output}.partial"

  if [[ -f "${output}" && "$(sha256_file "${output}")" == "${expected}" ]]; then
    return
  fi

  rm -f "${output}" "${partial}"
  curl -fL --retry 3 "${url}" -o "${partial}"
  if [[ "$(sha256_file "${partial}")" != "${expected}" ]]; then
    echo "source archive SHA-256 mismatch: ${url}" >&2
    rm -f "${partial}"
    exit 1
  fi
  mv "${partial}" "${output}"
}

checkout_pinned_commit() {
  local url="${1:?git URL is required}"
  local commit="${2:?git commit is required}"
  local destination="${3:?git destination is required}"

  rm -rf "${destination}"
  git init -q "${destination}"
  git -C "${destination}" remote add origin "${url}"
  git -C "${destination}" fetch -q --depth 1 origin "${commit}"
  git -C "${destination}" checkout -q --detach FETCH_HEAD
}

# 下载固定版本源码并校验摘要，避免上游同名资产或中断下载污染构建。
download_verified_archive "${FFMPEG_SOURCE_URL}" "${ARCHIVE}" "${FFMPEG_SOURCE_SHA256}"

# 每个目标使用独立构建目录，避免不同平台或重跑时污染 configure 结果。
if [[ ! -d "${SRC_DIR}/ffmpeg-${FFMPEG_VERSION}" ]]; then
  tar -xf "${ARCHIVE}" -C "${SRC_DIR}"
fi

rsync -a --delete "${SRC_DIR}/ffmpeg-${FFMPEG_VERSION}/" "${BUILD_DIR}/"

if [[ "${TARGET}" == darwin-* ]]; then
  BREW_PREFIX="$(brew --prefix)"
  # GitHub macOS runner 的非交互 shell 不总是带 Homebrew pkg-config 路径。
  export PATH="${BREW_PREFIX}/bin:${PATH}"
  export PKG_CONFIG_PATH="${BREW_PREFIX}/lib/pkgconfig:${BREW_PREFIX}/share/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
  export MACOSX_DEPLOYMENT_TARGET="${MACOS_MINIMUM_VERSION}"
fi

# FFmpeg 与随包 CLI 必须使用同一份固定 x265 源码，避免系统包的 P5 色彩标记能力漂移。
"${ROOT_DIR}/scripts/build-x265-unix.sh" "${TARGET}" "${X265_PREFIX}"
export PATH="${X265_PREFIX}/bin:${PATH}"
export PKG_CONFIG_PATH="${X265_PREFIX}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
if [[ "${TARGET}" == linux-* ]]; then
  export LD_LIBRARY_PATH="${X265_PREFIX}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
fi

if [[ "${TARGET}" == linux-* ]]; then
  VULKAN_HEADERS_SRC="${SRC_DIR}/Vulkan-Headers-${VULKAN_HEADERS_VERSION}"
  VULKAN_HEADERS_PREFIX="${ROOT_DIR}/build/vulkan-headers/${VULKAN_HEADERS_VERSION}"
  LIBPLACEBO_SRC="${SRC_DIR}/libplacebo-${LIBPLACEBO_VERSION}"
  LIBPLACEBO_PREFIX="${ROOT_DIR}/build/libplacebo/${LIBPLACEBO_VERSION}"

  if [[ ! -f "${VULKAN_HEADERS_PREFIX}/include/vulkan/vulkan.h" ]]; then
    rm -rf "${VULKAN_HEADERS_SRC}" "${VULKAN_HEADERS_PREFIX}"
    checkout_pinned_commit "${VULKAN_HEADERS_SOURCE_URL}" "${VULKAN_HEADERS_COMMIT}" "${VULKAN_HEADERS_SRC}"
    cmake -S "${VULKAN_HEADERS_SRC}" -B "${VULKAN_HEADERS_SRC}/build" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="${VULKAN_HEADERS_PREFIX}"
    cmake --install "${VULKAN_HEADERS_SRC}/build"
  fi

  # FFmpeg 8.1.1 需要 Vulkan header >= 1.3.277；构建时优先使用固定 commit。
  export PKG_CONFIG_PATH="${VULKAN_HEADERS_PREFIX}/share/pkgconfig:${VULKAN_HEADERS_PREFIX}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"

  if [[ ! -f "${LIBPLACEBO_PREFIX}/lib/pkgconfig/libplacebo.pc" ]]; then
    rm -rf "${LIBPLACEBO_SRC}" "${LIBPLACEBO_PREFIX}"
    checkout_pinned_commit "${LIBPLACEBO_SOURCE_URL}" "${LIBPLACEBO_COMMIT}" "${LIBPLACEBO_SRC}"
    mkdir -p "${LIBPLACEBO_SRC}/3rdparty/Vulkan-Headers/registry"
    ln -s "${VULKAN_HEADERS_PREFIX}/include" "${LIBPLACEBO_SRC}/3rdparty/Vulkan-Headers/include"
    ln -s "${VULKAN_HEADERS_PREFIX}/share/vulkan/registry/vk.xml" "${LIBPLACEBO_SRC}/3rdparty/Vulkan-Headers/registry/vk.xml"
    meson setup "${LIBPLACEBO_SRC}/build" "${LIBPLACEBO_SRC}" \
      --prefix="${LIBPLACEBO_PREFIX}" \
      --libdir=lib \
      --buildtype=release \
      --default-library=shared \
      -Dvulkan=enabled \
      -Dshaderc=disabled \
      -Dglslang=enabled \
      -Dlcms=enabled \
      -Ddovi=enabled \
      -Dlibdovi=disabled \
      -Dopengl=disabled \
      -Dd3d11=disabled \
      -Ddemos=false \
      -Dtests=false \
      -Dbench=false \
      -Dfuzz=false \
      -Dunwind=disabled \
      -Dxxhash=enabled
    meson compile -C "${LIBPLACEBO_SRC}/build"
    meson install -C "${LIBPLACEBO_SRC}/build"
  fi

  # 系统 libplacebo 版本与 FFmpeg 8.1.1 不兼容，必须让 configure 优先使用固定版本。
  export PKG_CONFIG_PATH="${LIBPLACEBO_PREFIX}/lib/pkgconfig:${LIBPLACEBO_PREFIX}/share/pkgconfig:${PKG_CONFIG_PATH}"
  export LD_LIBRARY_PATH="${LIBPLACEBO_PREFIX}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
fi

# 这些开关定义 Encode Lab 客户端依赖的 runtime 能力边界。
CONFIGURE_FLAGS=(
  "--prefix=${INSTALL_DIR}"
  "--disable-debug"
  "--disable-doc"
  "--disable-ffplay"
  "--enable-gpl"
  "--enable-version3"
  "--enable-pic"
  "--enable-libaom"
  "--enable-libdav1d"
  "--enable-libsvtav1"
  "--enable-libvpx"
  "--enable-libx264"
  "--enable-libx265"
  "--enable-libplacebo"
  "--enable-libzimg"
  "--enable-vulkan"
)

if [[ "${TARGET}" == linux-* ]]; then
  CONFIGURE_FLAGS+=(
    "--extra-cflags=-I${VULKAN_HEADERS_PREFIX}/include -I${LIBPLACEBO_PREFIX}/include"
    "--extra-ldflags=-L${LIBPLACEBO_PREFIX}/lib -Wl,-rpath,${LIBPLACEBO_PREFIX}/lib"
  )
fi

if [[ "${TARGET}" == darwin-* ]]; then
  # macOS 客户端仍可使用系统硬件编解码能力，但核心滤镜能力由本仓库固定。
  CONFIGURE_FLAGS+=("--enable-audiotoolbox" "--enable-videotoolbox")
fi

pushd "${BUILD_DIR}" >/dev/null
./configure "${CONFIGURE_FLAGS[@]}"
make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu)"
make install
popd >/dev/null

# dovi_tool 负责提取、转换和检查 RPU；使用 internal-font 避免引入 fontconfig runtime 依赖。
download_verified_archive "${DOVI_TOOL_SOURCE_URL}" "${DOVI_TOOL_ARCHIVE}" "${DOVI_TOOL_SOURCE_SHA256}"
if [[ ! -d "${DOVI_TOOL_SRC}" ]]; then
  tar -xzf "${DOVI_TOOL_ARCHIVE}" -C "${SRC_DIR}"
fi
pushd "${DOVI_TOOL_SRC}" >/dev/null
# 源码 tar 不带 .git；阻止 vergen 错把外层 runtime 仓库提交当成 dovi_tool 版本。
GIT_CEILING_DIRECTORIES="${ROOT_DIR}" \
  cargo build --release --locked --no-default-features --features internal-font
popd >/dev/null
cp "${DOVI_TOOL_SRC}/target/release/dovi_tool" "${INSTALL_DIR}/bin/dovi_tool"

# x265 CLI 的 --dolby-vision-rpu 为 CLI-only，必须和 FFmpeg 一起进入客户端 runtime。
cp "${X265_PREFIX}/bin/x265" "${INSTALL_DIR}/bin/x265"

case "${TARGET}" in
  # 分平台整理可执行文件和依赖库，保证 artifact 可独立分发。
  linux-*) "${ROOT_DIR}/scripts/stage-linux.sh" "${TARGET}" "${INSTALL_DIR}" "${DIST_DIR}" ;;
  darwin-*) "${ROOT_DIR}/scripts/stage-macos.sh" "${TARGET}" "${INSTALL_DIR}" "${DIST_DIR}" ;;
  *) echo "unsupported target: ${TARGET}" >&2; exit 1 ;;
esac

echo "runtime staged: ${DIST_DIR}"
"${ROOT_DIR}/scripts/write-manifest.sh" "${TARGET}" "${DIST_DIR}"
echo "runtime manifest written: ${DIST_DIR}/manifest.json"
"${ROOT_DIR}/scripts/verify-runtime.sh" "${DIST_DIR}"
