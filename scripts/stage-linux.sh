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

# 收集非基础系统库，避免用户机器缺少 libzimg/libx265 等依赖时运行失败。
copy_deps() {
  local binary="$1"
  local ldd_output
  if ! ldd_output="$(ldd "${binary}" 2>&1)"; then
    echo "failed to inspect runtime dependencies: ${binary}" >&2
    echo "${ldd_output}" >&2
    return 1
  fi

  while read -r dep; do
    [[ -f "${dep}" ]] || continue
    case "$(basename "${dep}")" in
      # 所有 glibc 组件都跟随最低支持系统，禁止混入新版 libmvec/librt 等破坏 ABI 基线。
      ld-linux-*.so.*|libc.so.*|libpthread.so.*|libm.so.*|libmvec.so.*|libdl.so.*|librt.so.*|libresolv.so.*|libutil.so.*|libanl.so.*)
        continue
        ;;
    esac
    # Ubuntu 22.04 的 coreutils 尚不支持 cp --update=none；-n 保持同名依赖不覆盖语义。
    cp -n "${dep}" "${DIST_DIR}/lib/"
  done < <(awk '/=> \// { print $3 }' <<<"${ldd_output}")
}

while IFS= read -r item; do
  copy_deps "${item}"
done < <(find "${DIST_DIR}/bin" -type f | sort)

# rpath 指向 artifact 内的 lib 目录，让客户端不依赖系统库搜索路径。
while IFS= read -r item; do
  if ! patchelf --set-rpath '$ORIGIN/../lib' "${item}"; then
    echo "failed to set bundled library rpath: ${item}" >&2
    exit 1
  fi
done < <(find "${DIST_DIR}/bin" -type f | sort)

# 重定位后再次检查，避免 artifact 到客户端后才暴露缺失动态库。
while IFS= read -r item; do
  if ! ldd_output="$(LD_LIBRARY_PATH="${DIST_DIR}/lib" ldd "${item}" 2>&1)"; then
    echo "failed to validate staged runtime dependencies: ${item}" >&2
    echo "${ldd_output}" >&2
    exit 1
  fi
  if [[ "${ldd_output}" == *"not found"* ]]; then
    echo "staged runtime has unresolved dependencies: ${item}" >&2
    echo "${ldd_output}" >&2
    exit 1
  fi
done < <(find "${DIST_DIR}/bin" -type f | sort)
