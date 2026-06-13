# Encode Lab FFmpeg Runtime

Encode Lab 的专用 FFmpeg runtime 构建仓库。目标是固定 FFmpeg 版本、编译参数和能力验证，避免用户客户端依赖各自系统 FFmpeg 时出现 `zscale`、`tonemap`、`libx265` 等能力不一致。

## 产物目标

GitHub Actions 会生成以下 artifact：

- `encode-lab-ffmpeg-darwin-arm64`
- `encode-lab-ffmpeg-darwin-x64`
- `encode-lab-ffmpeg-linux-x64`
- `encode-lab-ffmpeg-windows-x64`

每个 artifact 至少包含：

```text
bin/ffmpeg
bin/ffprobe
manifest.json
SHA256SUMS
LEGAL.md
```

Windows artifact 中的可执行文件为 `.exe`。

## 必备能力

构建产物必须通过 `scripts/verify-runtime.sh`：

- `ffmpeg` 可执行
- `ffprobe` 可执行
- `zscale` filter 存在
- `tonemap` filter 存在
- `libx265` encoder 存在

`zscale` 来自 `libzimg`，用于 Encode Lab 的 HDR / Dolby Vision 预览 SDR 映射链路。

## 手动触发构建

```bash
gh workflow run build-runtime.yml -f ffmpeg_version=8.1.1
```

## 许可边界

本仓库会启用 `--enable-gpl` 和 `libx264` / `libx265`，因此生成的 FFmpeg 二进制按 GPL 相关条款分发。不要启用 `--enable-nonfree`。

详细说明见 [LEGAL.md](./LEGAL.md)。

