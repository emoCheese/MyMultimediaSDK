# MultimediaSDK 设计规格

**日期**: 2026-07-16
**版本**: 1.0.0
**状态**: 设计中

---

## 1. 概述

MultimediaSDK 是一个跨平台的精简多媒体 SDK，基于 GStreamer + FFmpeg 源码构建，提供 RTSP 拉流、H.264 解码和 MP4 录制能力。

**核心目标**：
- 自包含离线构建，不依赖系统安装的 GStreamer/FFmpeg
- 最大程度裁剪，仅保留所需模块，最小化体积
- 统一 Windows / Linux / ARM Linux 的编译环境
- 输出标准 CMake SDK，业务工程 `find_package()` 即可使用

---

## 2. 需求范围

### 必需能力

| 功能 | 实现方式 |
|------|---------|
| RTSP 拉流 (TCP/UDP) | GStreamer rtspsrc |
| H.264 解码 | avdec_h264 / d3d11h264dec / vah264dec / nvh264dec |
| MP4 无损录制 (Remux，不重编码) | GStreamer mp4mux + filesink |
| GPU: D3D11VA (Windows) | d3d11h264dec |
| GPU: VAAPI (Linux) | vah264dec |
| GPU: NVDEC (Linux) | nvh264dec |

### 不支持

- 音频编解码
- 视频编码/转码
- RTSP 服务端
- WebRTC、HLS、DASH
- Python/C# 绑定

---

## 3. 架构

```
┌───────────────────────────────────────────────┐
│                 业务工程                        │
│  find_package(MultimediaSDK)                   │
│  #include <gst/gst.h>                          │
│  gst_element_factory_make("rtspsrc", ...)     │
└──────────────┬────────────────────────────────┘
               │
┌──────────────▼────────────────────────────────┐
│              SDK (include/ + lib/ + plugins/)   │
│                                                 │
│  ┌──────────┐ ┌──────────┐ ┌───────────────┐  │
│  │ GStreamer │ │ gst-libav │ │   FFmpeg      │  │
│  │  core     │ │ (bridge)  │ │ (codec+fmt)   │  │
│  │ + plugins │ │           │ │               │  │
│  └──────────┘ └──────────┘ └───────────────┘  │
│                                                 │
└─────────────────────────────────────────────────┘
```

---

## 4. 目录结构

```
MultimediaSDK/
├── CMakeLists.txt
├── build.py                          # 顶层构建入口
├── version.txt                       # 1.0.0
├── CHANGELOG.md
├── config/
│   └── modules.ini                   # 模块裁剪配置（唯一配置点）
├── cmake/
│   └── MultimediaSDKConfig.cmake.in  # find_package 模板
├── scripts/
│   ├── build-gstreamer.sh            # Meson 编译 GStreamer 子集
│   ├── build-ffmpeg.sh               # configure+make 编译 FFmpeg
│   └── package.sh                    # 打包为 tarball/zip
├── patches/
│   ├── gstreamer/
│   └── ffmpeg/
├── docker/
│   ├── linux-x64.Dockerfile
│   └── linux-arm64.Dockerfile
├── .github/workflows/
│   └── ci.yml
├── gstreamer/                        # git submodule → GStreamer monorepo
├── ffmpeg-7.1.5/                     # git submodule → FFmpeg 源码
├── output/                           # .gitignore
│   ├── build/
│   └── sdk/
└── README.md
```

---

## 5. GStreamer 模块裁剪

### 编译的子项目

| 子项目 | 包含的关键元素 |
|--------|-------------|
| gstreamer | Pipeline 核心 |
| gst-plugins-base | 基础类型、video、app、allocators |
| gst-plugins-good | rtspsrc、rtpmanager、isomp4、soup |
| gst-plugins-bad | h264parse、d3d11、va、nvcodec |
| gst-libav | avdec_h264 桥接 |

### 不编译的子项目

gst-plugins-ugly, gst-plugins-rs, gst-editing-services, gst-python,
gst-rtsp-server, gstreamer-sharp, gst-devtools, gst-docs, gst-examples

### 依赖图（从源码构建）

```
gstreamer
├── glib (subproject)
├── orc (subproject)
└── gst-plugins-base
    ├── libdrm (subproject, Linux)
    ├── libva (subproject, Linux)
    ├── DirectX-Headers (subproject, Windows)
    └── gst-plugins-good
        ├── json-glib (subproject)
        ├── libsoup (subproject)
        └── gst-plugins-bad
            └── gst-libav
                └── FFmpeg (pre-built static libs)
```

---

## 6. 配置驱动的裁剪系统

所有裁剪决策集中在 `config/modules.ini`，修改裁剪只需编辑此文件，不需改任何脚本。

### `config/modules.ini`

```ini
# ============================================================
# MultimediaSDK 模块配置
# 修改此文件即可调整裁剪范围，无需改任何脚本
# ============================================================

[core]
gstreamer = true
gst-plugins-base = true

[plugins.good]
rtsp = true           # rtspsrc, rtspclientsink, UDP source/sink
rtp = true            # rtpmanager, rtpptdemux
isomp4 = true         # qtdemux, mp4mux (QT/MP4 container)
soup = true           # HTTPS 拉流
opus = false
vpx = false
jack = false
oss = false

[plugins.bad]
codecparsers = true   # h264parse, h265parse
d3d11 = true          # d3d11h264dec (Windows D3D11VA)
va = true             # vah264dec (Linux VAAPI)
nvcodec = true        # nvh264dec (Linux NVDEC)
mpegts = false
webrtc = false
hls = false
dash = false

[plugins.ugly]
enabled = false

[libav]
enabled = true        # gst-libav (avdec_h264 等)

[other]
gst-rtsp-server = false
gst-editing-services = false
gst-python = false
gst-devtools = false
gst-examples = false

[ffmpeg]
decoders = h264,hevc
demuxers = rtsp,mpegts,mp4
muxers = mp4
parsers = h264,hevc
encoders =
protocols = file,pipe,tcp,udp,rtp,rtsp
```

### 脚本工作流

```
config/modules.ini  →  build-gstreamer.sh  →  生成 meson options
                                           →  meson setup
config/modules.ini  →  build-ffmpeg.sh     →  生成 configure flags
                                           →  ./configure + make
```

---

## 7. 构建系统

### 入口

```bash
python build.py --target linux-x64 [--mode release] [--clean] [--package] [--verbose]
python build.py --target linux-arm64
python build.py --target win-x64
```

### 流程

1. 读取 `config/modules.ini`
2. 生成 Meson 选项和 FFmpeg configure flags
3. `scripts/build-ffmpeg.sh` → FFmpeg 静态库 → `output/build/<target>/ffmpeg-install/`
4. `scripts/build-gstreamer.sh` → GStreamer 核心 + 插件 → `output/build/<target>/gst-install/`
5. 合并产物到 `output/sdk/<target>/`
6. 生成 `cmake/MultimediaSDKConfig.cmake`
7. (可选) `scripts/package.sh` → tarball/zip

### 链接策略

- GStreamer 核心库 (.a) → 静态链接
- GStreamer 插件 (.so/.dll) → 动态加载（GStreamer 架构要求）
- FFmpeg (.a) → 静态链接

### 产物布局

```
output/sdk/<target>/
├── include/          # GStreamer + GLib + FFmpeg 公共头文件
├── lib/              # .a 静态库
├── plugins/          # .so / .dll 动态插件
└── cmake/            # MultimediaSDKConfig.cmake
```

---

## 8. FFmpeg 裁剪

### 构建配置

```bash
./configure \
    --prefix=$INSTALL_DIR \
    --disable-all \
    --enable-avcodec \
    --enable-avformat \
    --enable-avutil \
    --enable-protocol=file,pipe,tcp,udp,rtp,rtsp \
    --enable-demuxer=rtsp,mpegts,mov,mp4 \
    --enable-muxer=mp4 \
    --enable-decoder=h264,hevc \
    --enable-parser=h264,hevc \
    --enable-bsf=h264_mp4toannexb \
    --disable-encoders \
    --disable-filters \
    --disable-doc \
    --disable-programs \
    --disable-avdevice \
    --disable-postproc \
    --disable-avfilter \
    --disable-swscale \
    --enable-pic \
    --enable-static \
    --disable-shared
```

### 产物

- `libavcodec.a` — H.264/H.265 解码器
- `libavformat.a` — RTSP/MP4/MPEG-TS 解复用
- `libavutil.a` — 通用工具函数

---

## 9. CMake 导出

### 模板 `cmake/MultimediaSDKConfig.cmake.in`

```cmake
set(MultimediaSDK_INCLUDE_DIRS "@CMAKE_INSTALL_PREFIX@/include")
set(MultimediaSDK_LIB_DIR "@CMAKE_INSTALL_PREFIX@/lib")
set(MultimediaSDK_PLUGIN_DIR "@CMAKE_INSTALL_PREFIX@/plugins")

# GStreamer core
add_library(MultimediaSDK::gstreamer STATIC IMPORTED)
set_target_properties(MultimediaSDK::gstreamer PROPERTIES
    IMPORTED_LOCATION "${MultimediaSDK_LIB_DIR}/libgstreamer-1.0.a"
    INTERFACE_INCLUDE_DIRECTORIES "${MultimediaSDK_INCLUDE_DIRS}/gstreamer-1.0"
)

# ... 其他库类似声明
```

### 业务代码使用

```cmake
find_package(MultimediaSDK REQUIRED)

add_executable(my_app main.c)
target_link_libraries(my_app
    MultimediaSDK::gstreamer
    MultimediaSDK::gstvideo
    MultimediaSDK::gstapp
)
```

---

## 10. CI/CD

### 流水线矩阵

| 平台 | 运行器 | 构建方式 | 运行时兼容 |
|------|--------|---------|-----------|
| linux-x64 (20.04) | ubuntu-22.04 | docker/linux-x64.Dockerfile (FROM ubuntu:20.04) | Ubuntu 20.04+ |
| linux-arm64 | ubuntu-22.04 | docker/linux-arm64.Dockerfile (FROM ubuntu:20.04) | Ubuntu 20.04+ arm64 |
| win-x64 | windows-2022 | 原生 MSVC | Windows 10/Server 2019+ |

### 触发规则

| 事件 | 行为 |
|------|------|
| `push main` | 构建 x64 三个平台 |
| `tag v*` | 构建全部平台 + GitHub Release 附带产物 |
| `pull_request` | 仅编译检查（不打包） |

### Docker 基础镜像

```dockerfile
# docker/linux-x64.Dockerfile
FROM ubuntu:20.04
RUN apt-get update && apt-get install -y \
    build-essential meson ninja-build cmake \
    pkg-config python3 python3-pip git \
    nasm yasm \
    libglib2.0-dev libmount-dev libselinux-dev
RUN pip3 install meson>=1.4
```

---

## 11. 版本管理

- 策略：SemVer (`MAJOR.MINOR.PATCH`)
- 文件：`version.txt` + `CHANGELOG.md`
- 发布：`git tag v1.0.0 && git push --tags` → CI 触发 Release
- 分支：`main`（稳定）、`develop`（开发）、`feature/*`

---

## 12. 兼容性

| 维度 | 最低要求 |
|------|---------|
| Ubuntu | 20.04 |
| GCC | 9.4.0 |
| GLibC | 2.31 |
| Meson | 1.4 |
| CMake (消费 SDK) | 3.16 |
| Windows | 10 / Server 2019+ |
| MSVC | Visual Studio 2019+ |
| ARM Linux | GLibC 2.31+, aarch64 |

---

## 13. 风险与注意事项

1. **GStreamer 版本锁定** — submodule 锁定 commit hash，避免上游 break
2. **FFmpeg API 兼容** — 锁死 7.1.5，大版本升级须全量测试
3. **交叉编译 ARM** — QEMU + aarch64 工具链，首次配置较慢
4. **D3D11VA 绑定** — 依赖 DirectX-Headers subproject，仅 MSVC 可编译
5. **许可证合规** — FFmpeg 组件各自有许可证（LGPL/GPL），需检查组合合规性
