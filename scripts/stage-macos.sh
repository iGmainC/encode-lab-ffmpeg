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

# 打包 MoltenVK ICD，确保 libplacebo 在没有系统 Vulkan 驱动的 macOS 客户端也能初始化。
stage_moltenvk_icd() {
  local moltenvk_prefix
  moltenvk_prefix="$(brew --prefix molten-vk)"

  mkdir -p "${DIST_DIR}/etc/vulkan/icd.d"
  cp "${moltenvk_prefix}/lib/libMoltenVK.dylib" "${DIST_DIR}/lib/"
  cp "${moltenvk_prefix}/etc/vulkan/icd.d/MoltenVK_icd.json" "${DIST_DIR}/etc/vulkan/icd.d/"

  # Homebrew manifest 内的路径指向 cellar；产物内必须改成相对 artifact 根目录的 lib。
  perl -0pi -e 's#"library_path"\s*:\s*"[^"]+"#"library_path": "../../../lib/libMoltenVK.dylib"#' \
    "${DIST_DIR}/etc/vulkan/icd.d/MoltenVK_icd.json"
}

# 对已改写 install name/rpath 的 Mach-O 文件重新做 ad-hoc 签名，避免 macOS dyld 运行时直接杀掉进程。
sign_runtime_files() {
  local item

  # 先签依赖库，再签最终入口二进制，确保入口文件看到的是稳定的依赖签名状态。
  while IFS= read -r item; do
    codesign --force --sign - "${item}"
  done < <(find "${DIST_DIR}/lib" -type f | sort)

  codesign --force --sign - "${DIST_DIR}/bin/ffmpeg"
  codesign --force --sign - "${DIST_DIR}/bin/ffprobe"
}

# rpath 指向随包 lib 目录，避免依赖用户本机 Homebrew 路径。
install_name_tool -add_rpath "@executable_path/../lib" "${DIST_DIR}/bin/ffmpeg" || true
install_name_tool -add_rpath "@executable_path/../lib" "${DIST_DIR}/bin/ffprobe" || true
stage_moltenvk_icd
copy_and_rewrite_deps "${DIST_DIR}/bin/ffmpeg"
copy_and_rewrite_deps "${DIST_DIR}/bin/ffprobe"
sign_runtime_files
