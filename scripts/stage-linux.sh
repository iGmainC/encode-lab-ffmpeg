#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:?target is required}"
INSTALL_DIR="${2:?install dir is required}"
DIST_DIR="${3:?dist dir is required}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}/bin" "${DIST_DIR}/lib"
cp "${INSTALL_DIR}/bin/ffmpeg" "${INSTALL_DIR}/bin/ffprobe" "${DIST_DIR}/bin/"
cp "${ROOT_DIR}/LEGAL.md" "${DIST_DIR}/"

# 收集非基础系统库，避免用户机器缺少 libzimg/libx265 等依赖时运行失败。
copy_deps() {
  local binary="$1"
  ldd "${binary}" | awk '/=> \// { print $3 }' | while read -r dep; do
    [[ -f "${dep}" ]] || continue
    case "${dep}" in
      # 基础 glibc 相关库跟随目标系统，避免打包动态链接器造成兼容风险。
      /lib64/ld-linux-*|/lib/x86_64-linux-gnu/libc.so.*|/lib/x86_64-linux-gnu/libpthread.so.*|/lib/x86_64-linux-gnu/libm.so.*|/lib/x86_64-linux-gnu/libdl.so.*)
        continue
        ;;
    esac
    cp -n "${dep}" "${DIST_DIR}/lib/" || true
  done
}

copy_deps "${DIST_DIR}/bin/ffmpeg"
copy_deps "${DIST_DIR}/bin/ffprobe"

# rpath 指向 artifact 内的 lib 目录，让客户端不依赖系统库搜索路径。
patchelf --set-rpath '$ORIGIN/../lib' "${DIST_DIR}/bin/ffmpeg" || true
patchelf --set-rpath '$ORIGIN/../lib' "${DIST_DIR}/bin/ffprobe" || true
