# MultimediaSDK — Agent 操作指南

## 项目概述

MultimediaSDK 是一个跨平台精简多媒体 SDK，基于 GStreamer + FFmpeg 源码构建。提供 RTSP 拉流、H.264 解码、MP4 无损录制（Remux）能力，支持 GPU 硬解（D3D11VA / VAAPI / NVDEC）。

**核心原则：自包含、最小裁剪、跨平台统一。**

## 克隆与初始化

### 首次克隆

```bash
git clone --recurse-submodules <仓库地址> MultimediaSDK
cd MultimediaSDK
```

GStreamer 和 FFmpeg 作为 git submodule 管理，使用 `--recurse-submodules` 一次性拉取。

### 更新 submodule

```bash
git submodule update --init --recursive
```

如果只需要最新代码（不需要完整历史），可用浅克隆加速：

```bash
git submodule update --init --depth 1
```

### 构建前必须应用补丁

`patches/gstreamer/` 包含对 GStreamer 上游源码的必要修改。每次克隆或更新 submodule 后必须重新应用：

```bash
cd gstreamer
git checkout .                          # 还原已应用的补丁（如果有）
git apply ../patches/gstreamer/*.patch
cd ..
```

> 未应用补丁直接构建会失败。如果 `gstreamer/` 目录没有对应源码被修改的记录，补丁应用时会自动跳过。

### 推送前检查清单

1. 工作区干净：`git status` → 无未提交文件
2. gstreamer submodule 干净：`cd gstreamer && git status` → `nothing to commit, clean`
3. 构建验证：`python3 build.py --clean`
4. 冒烟测试：`cd tests/smoke && bash build.sh`
5. 补丁文件与当前 submodule 版本匹配：`cd gstreamer && git apply --check ../patches/gstreamer/*.patch`

## 技术栈

| 项 | 选型 |
|---|------|
| 多媒体框架 | GStreamer 1.29（monorepo，git submodule） |
| 编解码 | FFmpeg 7.1.5（git submodule） |
| 构建系统 | Meson（GStreamer）+ configure/make（FFmpeg） |
| 构建入口 | `build.py`（Python 3） |
| SDK 导出 | CMake `find_package(MultimediaSDK)` |
| 平台 | Linux x64, Linux ARM64, Windows x64 |
| 最低系统 | Ubuntu 20.04 / Windows 10 |

## 目录结构

```
MultimediaSDK/
├── build.py                      # 构建入口（唯一用户接口）
├── config/
│   └── modules.ini               # 模块裁剪配置（修改此文件即可调整裁剪）
├── scripts/
│   ├── build-ffmpeg.sh           # FFmpeg 编译（configure + make）
│   ├── build-gstreamer.sh        # GStreamer 编译（meson setup + ninja）
│   └── package.sh                # 打包为 tar.gz / zip
├── cmake/
│   └── MultimediaSDKConfig.cmake.in  # find_package 模板
├── patches/
│   └── gstreamer/                # 对 GStreamer 上游源码的补丁
├── docker/
│   ├── linux-x64.Dockerfile      # CI 构建镜像（ubuntu:20.04）
│   └── linux-arm64.Dockerfile    # ARM64 交叉编译镜像
├── .github/workflows/ci.yml      # GitHub Actions CI
├── tests/smoke/                  # CMake 冒烟测试
│   ├── CMakeLists.txt
│   ├── main.c
│   └── build.sh                  # 一键构建 + 验证脚本
├── gstreamer/                    # git submodule → GStreamer monorepo
├── ffmpeg-7.1.5/                 # git submodule → FFmpeg 源码
├── output/                       # .gitignore
│   ├── build/                    # 中间编译产物
│   └── sdk/<target>/             # 最终 SDK 安装
│       ├── include/
│       ├── lib/
│       ├── plugins/
│       └── cmake/
├── docs/                         # 设计文档和实现计划
├── version.txt                   # 语义化版本号
├── CHANGELOG.md
└── README.md
```

## 构建流程

### 用户入口

```bash
python3 build.py                        # 自动检测平台
python3 build.py --target linux-x64     # 指定平台
python3 build.py --target linux-x64 --clean --package  # 清理 + 打包
```

### 内部流程（build.py 内部）

```
1. 读取 config/modules.ini
   ↓
2. build-ffmpeg.sh → FFmpeg 静态库（libavcodec.a, libavformat.a, libavutil.a, libavfilter.a）
   ↓
3. build-gstreamer.sh → GStreamer 核心 .so + 插件 .so
   ↓
4. 合并产物到 output/sdk/<target>/
   ├── include/    ← GStreamer 安装头 + 系统 GLib/GObject 头
   ├── lib/        ← FFmpeg .a + GStreamer 核心 .so + GLib arch config
   ├── plugins/    ← GStreamer 插件 .so（仅 gstreamer-1.0/ 目录下的）
   └── cmake/      ← 生成的 MultimediaSDKConfig.cmake
   ↓
5. (可选) package.sh → tar.gz / zip
```

### 关键设计决策

- **`auto_features=disabled`**：顶层选项，使所有 auto 特性自动禁用，无需逐项 disable
- **仅显式启用所需特性**：使用 `-Dgst-plugins-good:rtsp=enabled` 语法启用
- **共享库策略**：GStreamer 核心和插件使用 `.so`（插件必须动态加载），FFmpeg 使用 `.a` 静态库
- **SDK 自包含**：构建时复制系统 GLib 头文件到 SDK include/，复制 `glibconfig.h` 到 lib/

## 模块裁剪配置

`config/modules.ini` 是唯一配置点，修改后重新构建即可生效。

```ini
[core]
gstreamer = true          # GStreamer 核心（不可移除）
gst-plugins-base = true   # 基础插件（不可移除）

[plugins.good]
rtsp = true               # rtspsrc, RTSP 拉流
rtp = true                # rtph264depay, RTP 解包
rtpmanager = true         # RTP 会话管理
udp = true                # UDP 传输
isomp4 = true             # mp4mux/qtdemux
soup = true               # HTTP/HTTPS

[plugins.bad]
codecparsers = true       # h264parse（映射到 videoparsers）
d3d11 = true              # D3D11VA（Windows GPU 硬解）
va = true                 # VAAPI（Linux GPU 硬解）
nvcodec = true            # NVDEC（NVIDIA GPU 硬解）

[libav]
enabled = true             # gst-libav（avdec_h264 FFmpeg 桥接）

[ffmpeg]
decoders = h264,hevc      # 解码器列表
demuxers = rtsp,mpegts,mp4
muxers = mp4
parsers = h264,hevc
protocols = file,pipe,tcp,udp,rtp,rtsp
```

### 添加新模块

1. 编辑 `config/modules.ini`，设置对应特性为 `true`
2. 在 `scripts/build-gstreamer.sh` 中添加对应的 `enable_if_needed` 调用
3. 重新构建：`python3 build.py --clean`

### 移除 GPU 硬解

```ini
[plugins.bad]
d3d11 = false
va = false
nvcodec = false
```

## 对 GStreamer 源码的补丁

`patches/gstreamer/` 目录下记录了对上游源码的修改。每次更新 GStreamer submodule 后需重新应用。

| 补丁 | 文件 | 原因 |
|------|------|------|
| docs guard | `subprojects/gst-plugins-good/meson.build` | 当 `check` 禁用时，gstreamer subproject 的 docs 不定义 `plugins_cache_generator`，但 good/bad/base/libav 无条件调用 `subdir('docs')` 并访问该变量。修复：加 `if get_option('doc').allowed()` 守卫 |
| docs guard | `subprojects/gst-plugins-bad/meson.build` | 同上 |
| docs guard | `subprojects/gst-plugins-base/meson.build` | 同上 |
| docs guard | `subprojects/gst-libav/meson.build` | 同上 |

### 更新 submodule 后重新应用补丁

```bash
cd gstreamer
git checkout .                    # 还原所有修改
git checkout <new-commit>         # 切换到新版本
# 手动应用 docs guard（用 Edit 工具修改上述 4 个文件）
# 提交并推送 MultimediaSDK 仓库
```

## 已知问题与注意事项

### 1. awk ini 解析

`scripts/build-gstreamer.sh` 和 `scripts/build-ffmpeg.sh` 使用 awk 解析 `modules.ini`。关键细节：

- awk 分隔符 `-F=` 会导致 `$1` 含尾部空格（`enabled ` ≠ `enabled`）
- **必须同时 trim `$1` 和 `$2`**：`gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)`

### 2. Meson 子项目选项语法

GStreamer monorepo 中，**子项目选项不能直接作为顶层选项传递**。正确语法：

```
错误: -Dsoup=enabled
正确: -Dgst-plugins-good:soup=enabled

错误: -Dd3d11=enabled
正确: -Dgst-plugins-bad:d3d11=enabled

错误: -Dgst-rtsp-server=disabled
正确: -Drtsp_server=disabled（顶层选项名不同）
```

子项目名与选项名的映射关系在各子项目的 `meson.options` 中定义。

### 3. codecparsers → videoparsers

`config/modules.ini` 中使用 `codecparsers`（有意义的名称），但在 Meson 选项中对应的名称是 `videoparsers`。脚本中做了映射：

```bash
if [ "$(parse_ini_bool plugins.bad codecparsers)" = "true" ]; then
    MESON_OPTIONS+=("-Dgst-plugins-bad:videoparsers=enabled")
fi
```

### 4. 平台特定的 GLib 路径

`build.py` 中复制 GLib 配置的路径是 Linux x86_64 硬编码的：
```python
f"cp -r /usr/lib/x86_64-linux-gnu/glib-2.0 {sdk_dir}/lib/"
```

在 ARM64 或 Windows 上需要相应调整。未来应改为从 `pkg-config` 自动检测。

### 5. gst-plugin-scanner 警告

运行 SDK 程序时可能看到类似警告：
```
Failed to load plugin ...: undefined symbol: ...
```

这是因为 `gst-plugin-scanner` 是独立子进程，在解析插件元数据时使用受限环境。只要主程序能正常创建 GStreamer 元素（确认方法：运行 `tests/smoke/build.sh`），这些警告不影响功能。

### 6. Python 版本

当前环境使用 Python 3.8（EOL），Meson 1.12+ 将要求 Python 3.10。构建前确保 Python ≥ 3.8。

## 测试

```bash
# 冒烟测试：验证 SDK 可用性
cd tests/smoke && bash build.sh
```

测试内容：
- CMake `find_package(MultimediaSDK)` 是否正常
- 7 个关键 GStreamer 元素是否可用（rtspsrc, rtph264depay, h264parse, avdec_h264, mp4mux, filesink, fakesink）
- Pipeline 创建是否成功

此测试应在每次 SDK 构建完成后运行。

## CI/CD

`.github/workflows/ci.yml`

| 平台 | 触发 | 构建方式 |
|------|------|---------|
| linux-x64 | push main / tag v* | Docker (ubuntu:20.04) |
| linux-arm64 | push main / tag v* | Docker (ubuntu:20.04 + aarch64 交叉) |
| win-x64 | push main / tag v* | Windows runner + MSVC |

`tag v*` 触发生成 GitHub Release 附带各平台产物。

## 常见操作

### 添加新的 FFmpeg 解码器

编辑 `config/modules.ini`：
```ini
[ffmpeg]
decoders = h264,hevc,av1     # 追加 av1
```
重新构建：`python3 build.py --clean`

### 更新 GStreamer 版本

```bash
cd gstreamer
git fetch
git checkout <new-tag-or-commit>
cd ..
# 重新应用 patches/gstreamer/ 下的补丁
git add gstreamer
git commit -m "chore: update GStreamer to <version>"
```

> 更新后检查补丁是否仍适用：`cd gstreamer && git apply --check ../patches/gstreamer/*.patch`

### 更新 FFmpeg 版本

替换 `ffmpeg-7.1.5/` 目录内容，或修改 `scripts/build-ffmpeg.sh` 中的源码路径。

### 打包 SDK

```bash
python3 build.py --package
# 产物：output/dist/MultimediaSDK-1.0.0-linux-x64.tar.gz
```

业务工程使用方法见 `README.md`。
