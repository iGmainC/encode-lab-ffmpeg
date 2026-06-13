# Encode Lab FFmpeg Runtime

Encode Lab 的专用 FFmpeg runtime 构建仓库。目标是固定 FFmpeg 版本、编译参数和能力验证，避免用户客户端依赖各自系统 FFmpeg 时出现 `libplacebo`、`zscale`、`tonemap`、`libx265`、`libsvtav1` 等能力不一致。

## 产物目标

GitHub Actions 会生成以下 artifact：

- `encode-lab-ffmpeg-darwin-arm64`
- `encode-lab-ffmpeg-linux-x64`

每个 artifact 至少包含：

```text
bin/ffmpeg
bin/ffprobe
etc/vulkan/icd.d/MoltenVK_icd.json（macOS）
manifest.json
SHA256SUMS
LEGAL.md
```

Windows 与 Intel macOS 构建脚本暂时保留，但默认 workflow 先不生成对应 artifact。

## 必备能力

构建产物必须通过 `scripts/verify-runtime.sh`：

- `ffmpeg` 可执行
- `ffprobe` 可执行
- `libplacebo` filter 存在，并支持 `apply_dolbyvision`
- `zscale` filter 存在
- `tonemap` filter 存在
- `libx264` encoder 存在
- `libx265` encoder 存在
- `libaom-av1` encoder 存在
- `libsvtav1` encoder 存在
- `libvpx-vp9` encoder 存在

`libplacebo` 用于 Dolby Vision 预览时读取 RPU 并映射到 BT.709 SDR；`zscale` 来自 `libzimg`，作为 HDR10 / HLG 预览 SDR 映射 fallback。

macOS artifact 会随包携带 MoltenVK ICD 和 `libMoltenVK.dylib`，客户端需要把 `VK_ICD_FILENAMES` 指向 artifact 内的 `etc/vulkan/icd.d/MoltenVK_icd.json`，避免依赖用户本机是否安装 Vulkan 驱动。

## 手动触发构建

```bash
gh workflow run build-runtime.yml -f ffmpeg_version=8.1.1
```

## 许可边界

本仓库会启用 `--enable-gpl` 和 `libx264` / `libx265`，因此生成的 FFmpeg 二进制按 GPL 相关条款分发。不要启用 `--enable-nonfree`。

详细说明见 [LEGAL.md](./LEGAL.md)。
