# Changelog

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
