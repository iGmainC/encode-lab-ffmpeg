#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:?target is required}"
INSTALL_DIR="${2:?install dir is required}"
DIST_DIR="${3:?dist dir is required}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}/bin" "${DIST_DIR}/lib"
cp \
  "${INSTALL_DIR}/bin/ffmpeg" \
  "${INSTALL_DIR}/bin/ffprobe" \
  "${INSTALL_DIR}/bin/x265" \
  "${INSTALL_DIR}/bin/dovi_tool" \
  "${DIST_DIR}/bin/"
cp "${ROOT_DIR}/LEGAL.md" "${DIST_DIR}/"

# 复制 Homebrew 与仓库内固定构建的动态库；系统库继续由 macOS 提供。
is_external_dylib() {
  case "$1" in
    /opt/homebrew/*|/usr/local/*|"${ROOT_DIR}"/build/*) return 0 ;;
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
            install_name_tool -id "@rpath/${base}" "${DIST_DIR}/lib/${base}"
            changed=1
          fi
          install_name_tool -change "${dep}" "@rpath/${base}" "${item}"
        fi
      done < <(otool -L "${item}" | awk 'NR > 1 { print $1 }')
    done < <(find "${DIST_DIR}/bin" "${DIST_DIR}/lib" -type f)
  done
}

list_rpaths() {
  otool -l "$1" | awk '$1 == "cmd" && $2 == "LC_RPATH" { getline; getline; print $2 }'
}

is_external_rpath() {
  case "$1" in
    /opt/homebrew/*|/usr/local/*|"${ROOT_DIR}"/build/*) return 0 ;;
    *) return 1 ;;
  esac
}

# 删除构建机绝对 rpath，并确保入口只从 artifact 的 lib 目录解析依赖。
normalize_runtime_rpaths() {
  local item
  local rpath
  while IFS= read -r item; do
    while IFS= read -r rpath; do
      if is_external_rpath "${rpath}"; then
        install_name_tool -delete_rpath "${rpath}" "${item}"
      fi
    done < <(list_rpaths "${item}")

    if [[ "${item}" == "${DIST_DIR}/bin/"* ]] && \
      ! list_rpaths "${item}" | awk '$0 == "@executable_path/../lib" { found = 1 } END { exit found ? 0 : 1 }'; then
      install_name_tool -add_rpath "@executable_path/../lib" "${item}"
    fi
  done < <(find "${DIST_DIR}/bin" "${DIST_DIR}/lib" -type f | sort)
}

# CI 构建树仍存在时也不能掩盖漏包；任何外部依赖或 rpath 都直接失败。
validate_runtime_references() {
  local item
  local reference
  while IFS= read -r item; do
    while IFS= read -r reference; do
      if is_external_dylib "${reference}"; then
        echo "staged Mach-O retains external dependency: ${item} -> ${reference}" >&2
        exit 1
      fi
    done < <(otool -L "${item}" | awk 'NR > 1 { print $1 }')

    while IFS= read -r reference; do
      if is_external_rpath "${reference}"; then
        echo "staged Mach-O retains external rpath: ${item} -> ${reference}" >&2
        exit 1
      fi
    done < <(list_rpaths "${item}")
  done < <(find "${DIST_DIR}/bin" "${DIST_DIR}/lib" -type f | sort)
}

# 固定源码构建的 x265 使用 @rpath install name，无法通过绝对路径依赖扫描自动发现。
stage_pinned_x265() {
  local x265_lib_dir="${ROOT_DIR}/build/x265/${TARGET}/install/lib"
  local dependency
  local base

  dependency="$(otool -L "${INSTALL_DIR}/bin/x265" | awk '/@rpath\/libx265.*\.dylib/ { print $1; exit }')"
  if [[ -z "${dependency}" ]]; then
    echo "failed to resolve pinned x265 dylib name" >&2
    exit 1
  fi

  base="${dependency#@rpath/}"
  if [[ ! -f "${x265_lib_dir}/${base}" ]]; then
    echo "missing pinned x265 dylib: ${x265_lib_dir}/${base}" >&2
    exit 1
  fi

  cp "${x265_lib_dir}/${base}" "${DIST_DIR}/lib/${base}"
  chmod u+w "${DIST_DIR}/lib/${base}"
  install_name_tool -id "@rpath/${base}" "${DIST_DIR}/lib/${base}"
}

# 打包 MoltenVK ICD，确保 libplacebo 在没有系统 Vulkan 驱动的 macOS 客户端也能初始化。
stage_moltenvk_icd() {
  local moltenvk_prefix
  moltenvk_prefix="$(brew --prefix molten-vk)"

  mkdir -p "${DIST_DIR}/etc/vulkan/icd.d"
  cp "${moltenvk_prefix}/lib/libMoltenVK.dylib" "${DIST_DIR}/lib/"
  chmod u+w "${DIST_DIR}/lib/libMoltenVK.dylib"
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

  while IFS= read -r item; do
    codesign --force --sign - "${item}"
  done < <(find "${DIST_DIR}/bin" -type f | sort)
}

stage_moltenvk_icd
stage_pinned_x265
copy_and_rewrite_deps "${DIST_DIR}/bin/ffmpeg"
normalize_runtime_rpaths
validate_runtime_references
sign_runtime_files
