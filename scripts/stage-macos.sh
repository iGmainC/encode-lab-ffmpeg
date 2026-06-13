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

# 只复制 Homebrew 动态库；系统库继续由 macOS 提供，降低产物体积和签名风险。
is_external_dylib() {
  case "$1" in
    /opt/homebrew/*|/usr/local/*) return 0 ;;
    *) return 1 ;;
  esac
}

# 递归复制依赖库并改写 install name，确保 ffmpeg/ffprobe 能优先加载 artifact 内的库。
copy_and_rewrite_deps() {
  local binary="$1"
  local changed=1
  while [[ "${changed}" -eq 1 ]]; do
    changed=0
    while IFS= read -r item; do
      while IFS= read -r dep; do
        if is_external_dylib "${dep}"; then
          local base
          base="$(basename "${dep}")"
          if [[ ! -f "${DIST_DIR}/lib/${base}" ]]; then
            cp "${dep}" "${DIST_DIR}/lib/${base}"
            chmod u+w "${DIST_DIR}/lib/${base}"
            install_name_tool -id "@rpath/${base}" "${DIST_DIR}/lib/${base}" || true
            changed=1
          fi
          install_name_tool -change "${dep}" "@rpath/${base}" "${item}" || true
        fi
      done < <(otool -L "${item}" | awk 'NR > 1 { print $1 }')
    done < <(find "${DIST_DIR}/bin" "${DIST_DIR}/lib" -type f)
  done
}

# rpath 指向随包 lib 目录，避免依赖用户本机 Homebrew 路径。
install_name_tool -add_rpath "@executable_path/../lib" "${DIST_DIR}/bin/ffmpeg" || true
install_name_tool -add_rpath "@executable_path/../lib" "${DIST_DIR}/bin/ffprobe" || true
copy_and_rewrite_deps "${DIST_DIR}/bin/ffmpeg"
copy_and_rewrite_deps "${DIST_DIR}/bin/ffprobe"
