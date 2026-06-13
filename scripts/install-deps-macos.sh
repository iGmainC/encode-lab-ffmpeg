#!/usr/bin/env bash
set -euo pipefail

# 安装 Homebrew 依赖，确保 zscale、tonemap 和项目暴露的视频编码器在 macOS 产物中可用。
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1

brew install \
  aom \
  dav1d \
  libtool \
  libvpx \
  nasm \
  pkg-config \
  svt-av1 \
  x264 \
  x265 \
  xz \
  yasm \
  zimg
