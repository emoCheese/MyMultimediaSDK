# MultimediaSDK

基于 GStreamer + FFmpeg 源码构建的跨平台精简多媒体 SDK，提供 RTSP 拉流、H.264 解码和 MP4 录制能力。

## 功能

- **RTSP 拉流**（TCP/UDP）— GStreamer rtspsrc
- **H.264 解码** — CPU（avdec_h264）、GPU（D3D11VA / VAAPI / NVDEC），运行时自动选择最优后端
- **MP4 无损录制** — Remux 模式，不重新编码，mp4mux + filesink
- **自包含构建** — 不依赖系统安装的 GStreamer 或 FFmpeg，全部从源码编译

## 支持平台

| 平台 | 最低系统要求 | 编译器 |
|------|-------------|--------|
| Linux x64 | Ubuntu 20.04+ | GCC 9.4+ |
| Linux ARM64 | Ubuntu 20.04+ | aarch64-linux-gnu |
| Windows x64 | Windows 10 / Server 2019+ | MSVC 2019+ |

## 环境要求

### Linux

```bash
# Ubuntu 20.04+
sudo apt install build-essential meson ninja-build cmake \
    pkg-config python3 python3-pip git nasm yasm bison flex \
    libglib2.0-dev libmount-dev libselinux1-dev zlib1g-dev

pip3 install 'meson>=1.4'
```

### Windows

- Visual Studio 2019+（含 C++ 桌面开发工作负载）
- Python 3 + `pip install meson ninja`
- nasm（放入 PATH 或使用 vcpkg）

## 从源码构建

### 1. 克隆仓库

```bash
# 首次克隆（包含 submodule）
git clone --recurse-submodules <仓库地址> MultimediaSDK
cd MultimediaSDK

# 如果已是完整浅克隆，使用以下指令加速
git submodule update --init --depth 1
```

GStreamer 和 FFmpeg 使用 git submodule 管理。如果已经克隆但忘记拉取 submodule：

```bash
git submodule update --init --recursive
```

### 2. 应用补丁

构建前需将 `patches/gstreamer/` 下的补丁应用到 GStreamer 源码（修复 docs 在裁剪构建中的兼容性）：

```bash
cd gstreamer
git apply ../patches/gstreamer/*.patch
cd ..
```

> 每次更新 GStreamer submodule 后必须重新应用补丁。

### 3. 构建

```bash
# 自动检测当前平台
python3 build.py

# 指定目标平台
python3 build.py --target linux-x64

# 交叉编译 ARM
python3 build.py --target linux-arm64

# 构建并打包
python3 build.py --target linux-x64 --package

# 清理后重新构建
python3 build.py --target linux-x64 --clean
```

### 4. 产物位置

```
output/sdk/<target>/
├── include/          # 头文件（GStreamer、GLib、FFmpeg）
├── lib/              # 静态库（.a）
├── plugins/          # GStreamer 动态插件（.so/.dll）
└── cmake/
    └── MultimediaSDKConfig.cmake
```

打包后的压缩包在 `output/dist/` 下：

```
MultimediaSDK-1.0.0-linux-x64.tar.gz
MultimediaSDK-1.0.0-linux-x64.sha256
```

---

## 使用 SDK

### 解压 SDK

构建完成后，SDK 产物位于 `output/sdk/<target>/`。若已使用 `--package` 打包，产物在 `output/dist/` 下：

```bash
# Linux
tar xzf output/dist/MultimediaSDK-1.0.0-linux-x64.tar.gz
cd MultimediaSDK-1.0.0-linux-x64

# Windows
# 解压 MultimediaSDK-1.0.0-win-x64.zip
```

### CMake 集成

将 SDK 解压到项目目录，在 `CMakeLists.txt` 中：

```cmake
cmake_minimum_required(VERSION 3.16)
project(MyApp)

# 指定 SDK 路径（解压后的目录）
set(MultimediaSDK_DIR "/path/to/MultimediaSDK-1.0.0-linux-x64/cmake")
find_package(MultimediaSDK REQUIRED)

add_executable(my_app main.c)
target_link_libraries(my_app
    MultimediaSDK::gstreamer
    MultimediaSDK::gstvideo
    MultimediaSDK::gstapp
    MultimediaSDK::gstrtp
)
```

### 编译与运行

#### Linux

```bash
# 编译
mkdir -p build && cd build
cmake /path/to/your-project \
    -DMultimediaSDK_DIR="/path/to/MultimediaSDK-1.0.0-linux-x64/cmake" \
    -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)

# 运行（必须设置环境变量指向 SDK 库和插件路径）
export GST_PLUGIN_PATH="/path/to/MultimediaSDK-1.0.0-linux-x64/plugins"
export LD_LIBRARY_PATH="/path/to/MultimediaSDK-1.0.0-linux-x64/lib:${LD_LIBRARY_PATH}"
./my_app
```

> 如果未设置 `GST_PLUGIN_PATH`，GStreamer 将找不到 `rtspsrc`、`mp4mux` 等插件。
> `LD_LIBRARY_PATH` 需指向 SDK 的 `lib/` 目录，否则运行时链接器找不到 GStreamer 的 `.so` 库。

#### Windows

```powershell
# 编译（Visual Studio Developer Command Prompt）
mkdir build
cd build
cmake \path\to\your-project ^
    -DMultimediaSDK_DIR="C:\path\to\MultimediaSDK-1.0.0-win-x64\cmake" ^
    -DCMAKE_BUILD_TYPE=Release
cmake --build . --config Release

# 运行（必须设置环境变量）
set GST_PLUGIN_PATH=C:\path\to\MultimediaSDK-1.0.0-win-x64\plugins
set PATH=C:\path\to\MultimediaSDK-1.0.0-win-x64\lib;%PATH%
.\Release\my_app.exe
```

> Windows 下 `PATH` 需要包含 SDK 的 `lib/` 目录，GStreamer 运行时通过 `PATH` 搜索 `.dll` 和通过 `GST_PLUGIN_PATH` 搜索插件。

### 代码示例：RTSP 拉流录制为 MP4

```c
#include <gst/gst.h>

int main(int argc, char *argv[]) {
    gst_init(&argc, &argv);

    const char *url = "rtsp://192.168.1.100:554/stream";
    const char *output = "/tmp/output.mp4";

    /* 方式 1：GStreamer 命令行语法（开发/调试推荐） */
    GstElement *pipeline = gst_parse_launch(
        "rtspsrc location=rtsp://192.168.1.100:554/stream latency=0 "
        "protocols=tcp ! "
        "rtph264depay ! h264parse ! avdec_h264 ! "
        "mp4mux ! filesink location=/tmp/output.mp4",
        NULL
    );

    /* 方式 2：逐个元素构建（生产推荐，便于错误处理） */
    /*
    GstElement *pipeline = gst_pipeline_new("rtsp-to-mp4");
    GstElement *src    = gst_element_factory_make("rtspsrc",    "source");
    GstElement *depay  = gst_element_factory_make("rtph264depay","depay");
    GstElement *parse  = gst_element_factory_make("h264parse",  "parser");
    GstElement *dec    = gst_element_factory_make("avdec_h264", "decoder");
    GstElement *mux    = gst_element_factory_make("mp4mux",     "muxer");
    GstElement *sink   = gst_element_factory_make("filesink",   "sink");

    g_object_set(src,  "location",  url,    NULL);
    g_object_set(sink, "location",  output, NULL);

    gst_bin_add_many(GST_BIN(pipeline), src, depay, parse, dec, mux, sink, NULL);
    gst_element_link_many(depay, parse, dec, mux, sink, NULL);
    g_signal_connect(src, "pad-added", G_CALLBACK(on_pad_added), depay);
    */

    gst_element_set_state(pipeline, GST_STATE_PLAYING);

    GMainLoop *loop = g_main_loop_new(NULL, FALSE);
    g_main_loop_run(loop);

    gst_element_set_state(pipeline, GST_STATE_NULL);
    gst_object_unref(pipeline);
    g_main_loop_unref(loop);
    return 0;
}
```

> **GPU 硬解：** 将 `avdec_h264` 替换为对应的 GPU 解码器元素即可：
> - Windows D3D11VA：`d3d11h264dec`
> - Linux VAAPI：`vah264dec`
> - Linux NVDEC：`nvh264dec`
>
> 也可在代码中运行时检测可用性，自动选择最优后端。

### 可用的 CMake 目标

| 目标 | 说明 |
|------|------|
| `MultimediaSDK::gstreamer` | GStreamer 核心 |
| `MultimediaSDK::gstbase` | 基础工具库 |
| `MultimediaSDK::gstvideo` | 视频类型/缓冲区 |
| `MultimediaSDK::gstapp` | AppSrc/AppSink |
| `MultimediaSDK::gstrtp` | RTP 支持 |
| `MultimediaSDK::glib` | GLib |
| `MultimediaSDK::gobject` | GObject |
| `MultimediaSDK::avcodec` | FFmpeg 编解码 |
| `MultimediaSDK::avformat` | FFmpeg 解复用/复用 |
| `MultimediaSDK::avutil` | FFmpeg 工具 |
| `MultimediaSDK::all` | 以上全部 |

---

## 自定义裁剪

编辑 `config/modules.ini`，按需开启或关闭模块：

```ini
# 仅 CPU 解码，关闭所有 GPU 后端
[plugins.bad]
d3d11 = false
va = false
nvcodec = false

# 仅 H.264 解码（去掉 HEVC）
[ffmpeg]
decoders = h264

# 关闭 RTSP，仅保留本地 MP4 解复用
[plugins.good]
rtsp = false
rtp = false
isomp4 = true
```

修改后重新构建：

```bash
python3 build.py --clean
```

## 贡献指南

### 初始化开发环境

```bash
# 全量克隆（含 submodule）
git clone --recurse-submodules git@github.com:<your-org>/MultimediaSDK.git
cd MultimediaSDK

# 应用 GStreamer 补丁
cd gstreamer
git apply ../patches/gstreamer/*.patch
cd ..

# 构建 SDK
python3 build.py
```

### 提交流程

```bash
# 确保工作区干净
git status

# 如果修改了 GStreamer submodule 内文件，先提交到 submodule
# 然后更新主仓库的 submodule 指针
# （通常不直接修改 gstreamer/，而是通过 patches/ 管理）

# 如果工作区涉及 gstreamer/ 的 dirty 状态
cd gstreamer
git checkout .              # 还原 submodule 修改
git checkout <original-sha> # 或恢复为原始提交
cd ..
git add -A
git commit -m "feat: your change description"

# 推送前检查
python3 build.py --clean    # 确保构建通过
cd tests/smoke && bash build.sh  # 确保测试通过
```

### 补丁管理

对 GStreamer 源码的修改请放入 `patches/gstreamer/`，不要直接提交 submodule 内变更：

```bash
# 生成补丁
cd gstreamer
git diff > ../patches/gstreamer/003-my-fix.patch
cd ..
git add patches/gstreamer/003-my-fix.patch
git commit -m "fix: add patch for ..."
```

## 许可证

GStreamer 和 FFmpeg 组件遵循各自的许可证（LGPL / GPL）。使用时请注意许可证合规性。
