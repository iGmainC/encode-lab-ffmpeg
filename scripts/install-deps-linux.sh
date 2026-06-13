#!/usr/bin/env bash
set -euo pipefail

# 安装 FFmpeg 源码编译和动态库重定位所需依赖。
sudo apt-get update
sudo apt-get install -y \
  autoconf \
  automake \
  build-essential \
  ca-certificates \
  curl \
  git \
  libdav1d-dev \
  libmp3lame-dev \
  libnuma-dev \
  libopus-dev \
  libsvtav1-dev \
  libtool \
  libvpx-dev \
  libx264-dev \
  libx265-dev \
  libzimg-dev \
  nasm \
  patchelf \
  pkg-config \
  rsync \
  tar \
  xz-utils \
  yasm
