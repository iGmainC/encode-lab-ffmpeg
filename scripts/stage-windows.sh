#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:?target is required}"
INSTALL_DIR="${2:?install dir is required}"
DIST_DIR="${3:?dist dir is required}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}/bin"
cp "${INSTALL_DIR}/bin/ffmpeg.exe" "${INSTALL_DIR}/bin/ffprobe.exe" "${DIST_DIR}/bin/"
cp "${ROOT_DIR}/LEGAL.md" "${DIST_DIR}/"

# 复制 MSYS2/UCRT 运行时 DLL，保证 Windows 客户端不依赖用户预装 MSYS2。
copy_dlls() {
  local binary="$1"
  ldd "${binary}" | awk '/mingw64|ucrt64/ { print $3 }' | while read -r dep; do
    [[ -f "${dep}" ]] || continue
    cp -n "${dep}" "${DIST_DIR}/bin/" || true
  done
}

copy_dlls "${DIST_DIR}/bin/ffmpeg.exe"
copy_dlls "${DIST_DIR}/bin/ffprobe.exe"
