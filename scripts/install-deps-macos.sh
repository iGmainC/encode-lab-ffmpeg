#!/usr/bin/env bash
set -euo pipefail

# 安装 Homebrew 依赖，确保 zscale、tonemap 和 H.265 路径在 macOS 产物中可用。
brew update
brew install \
  dav1d \
  lame \
  libogg \
  libtool \
  libvpx \
  nasm \
  opus \
  pkg-config \
  svt-av1 \
  x264 \
  x265 \
  xz \
  yasm \
  zimg
