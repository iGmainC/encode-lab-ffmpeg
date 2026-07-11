# Encode Lab FFmpeg Runtime

Encode Lab 的专用 FFmpeg runtime 构建仓库。目标是固定 FFmpeg、x265、dovi_tool 的版本、编译参数和能力验证，避免用户客户端依赖各自系统组件时出现 `libplacebo`、`zscale`、`tonemap`、Profile 5 色彩标记、RPU 参数等能力不一致。

## 产物目标

GitHub Actions 会生成以下 artifact：

- `encode-lab-ffmpeg-darwin-arm64`
- `encode-lab-ffmpeg-linux-x64`

每个 artifact 至少包含：

```text
bin/ffmpeg
bin/ffprobe
bin/x265
bin/dovi_tool
etc/vulkan/icd.d/MoltenVK_icd.json（macOS）
manifest.json
SHA256SUMS
LEGAL.md
```

Windows 与 Intel macOS 构建脚本暂时保留，但默认 workflow 先不生成对应 artifact。

当前发布基线为 macOS 15（Apple Silicon）和 glibc 2.35（Linux x64，对应 Ubuntu 22.04 运行基线）。每个 manifest 会记录 runtime 仓库提交、核心源码摘要、关键构建依赖来源，以及对应平台的最低系统版本。

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
- x265 CLI 支持 `--dolby-vision-profile` 与 `--dolby-vision-rpu`
- x265 由固定的 4.2 源码构建，并同时提供 8-bit / 10-bit 编码能力
- `dovi_tool` 支持 RPU 提取、注入、信息读取和 Profile 7 拆层
- 10 帧 Profile 8.1 与 Profile 5 RPU 编码、FFmpeg 重编码和语义比对 smoke test 通过

`libplacebo` 用于 Dolby Vision 预览时读取 RPU 并映射到 BT.709 SDR；`zscale` 来自 `libzimg`，作为 HDR10 / HLG 预览 SDR 映射 fallback。

macOS artifact 会随包携带 MoltenVK ICD 和 `libMoltenVK.dylib`，客户端需要把 `VK_ICD_FILENAMES` 指向 artifact 内的 `etc/vulkan/icd.d/MoltenVK_icd.json`，避免依赖用户本机是否安装 Vulkan 驱动。

## 手动触发构建

```bash
gh workflow run build-runtime.yml -f runtime_version=8.1.1-rpu.2 -f ffmpeg_version=8.1.1 -f create_release=true
```

Release 版本和 tag 是不可变的；同名版本已存在时 workflow 会直接失败，修复构建后必须递增 `rpu.N`。Release 同时发布 archive 级 `SHA256SUMS`，客户端构建脚本仍固定内置所使用版本的摘要，下载后校验通过才会替换本地 runtime。

## 许可边界

本仓库会启用 `--enable-gpl` 和 `libx264` / `libx265`，因此生成的 FFmpeg 二进制按 GPL 相关条款分发。不要启用 `--enable-nonfree`。

详细说明见 [LEGAL.md](./LEGAL.md)。
