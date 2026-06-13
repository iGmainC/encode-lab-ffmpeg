#!/usr/bin/env bash
set -euo pipefail

# 安装 FFmpeg 源码编译和动态库重定位所需依赖。
sudo apt-get update
sudo apt-get install -y \
  autoconf \
  automake \
  build-essential \
  ca-certificates \
  cmake \
  curl \
  git \
  glslang-dev \
  glslang-tools \
  libaom-dev \
  libdav1d-dev \
  liblcms2-dev \
  libnuma-dev \
  libshaderc-dev \
  libsvtav1enc-dev \
  libtool \
  libvulkan-dev \
  libvpx-dev \
  libx264-dev \
  libx265-dev \
  libxxhash-dev \
  libzimg-dev \
  meson \
  nasm \
  ninja-build \
  patchelf \
  pkg-config \
  python3-mako \
  rsync \
  spirv-tools \
  tar \
  xz-utils \
  yasm
