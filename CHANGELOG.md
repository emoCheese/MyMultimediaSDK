# Changelog

## [1.1.0] - 2026-07-17

### Added
- 启用 `decodebin3`（自动选择硬件/软件解码）
- 启用 `videoconvert`/`videoscale`（色彩空间转换与缩放）
- 启用 `appsrc`/`appsink`（程序化数据接口）
- 启用 `tcp` 传输、`audioconvert`、`audioresample`

### Fixed
- CMake 配置路径改为相对路径，SDK 可任意位置移动
- AWK ini 解析 `$1` 尾部空格问题
- GStreamer 子项目选项语法修正（`-Dgst-plugins-good:rtsp=enabled`）
- 构建合并逻辑区分核心库与插件目录
- GLib 头文件自动复制到 SDK include

## [1.0.0] - 2026-07-16

### Added
- Initial release
- RTSP pull (TCP/UDP) via GStreamer rtspsrc
- H.264 decode: CPU (avdec_h264), GPU (D3D11VA/VAAPI/NVDEC)
- MP4 lossless recording (remux via mp4mux)
- Config-driven module trimming (`config/modules.ini`)
- CMake export (`find_package(MultimediaSDK)`)
- Docker-based CI for Linux x64 and ARM64 cross-compilation
- Windows native MSVC build support
- Ubuntu 20.04+ runtime compatibility
