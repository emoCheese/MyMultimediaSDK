# MultimediaSDK 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 从零创建 MultimediaSDK 仓库，实现 GStreamer + FFmpeg 源码构建、裁剪编译、CMake 导出、CI/CD 和打包流程。

**架构：** 顶层 `build.py` 编排 `build-gstreamer.sh` 和 `build-ffmpeg.sh`，配置文件 `config/modules.ini` 驱动所有裁剪决策。产物合并到 `output/sdk/<target>/` 并生成 CMake 配置。

**技术栈：** Python 3, Bash, Meson, Ninja, CMake, Docker, GitHub Actions

---

### 任务 1：仓库骨架与忽略规则

**文件：**
- 创建：`.gitignore`
- 创建：`config/`（空目录由脚本创建）
- 创建：`scripts/`（空目录）
- 创建：`cmake/`（空目录）
- 创建：`patches/gstreamer/`（空目录）
- 创建：`patches/ffmpeg/`（空目录）
- 创建：`docker/`（空目录）
- 创建：`output/.gitkeep`

- [ ] **步骤 1：创建 .gitignore**

```bash
cat > /home/fox2/tmp/MultimediaSDK/.gitignore << 'IGNOREEOF'
# Build output
output/build/
output/sdk/
output/dist/
output/*.tar.gz
output/*.zip

# Python
__pycache__/
*.pyc
*.pyo
*.egg-info/

# IDE
.idea/
.vscode/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db
IGNOREEOF
```

- [ ] **步骤 2：创建所有空目录和 .gitkeep**

```bash
cd /home/fox2/tmp/MultimediaSDK
mkdir -p config scripts cmake patches/gstreamer patches/ffmpeg docker output
touch output/.gitkeep
```

- [ ] **步骤 3：验证目录结构**

```bash
cd /home/fox2/tmp/MultimediaSDK
ls -la .gitignore config/ scripts/ cmake/ patches/ docker/ output/.gitkeep
```

预期：所有目录存在，`.gitkeep` 在 `output/` 下。

- [ ] **步骤 4：Git init 并提交**

```bash
cd /home/fox2/tmp/MultimediaSDK
git init
git add .gitignore config/ scripts/ cmake/ patches/ docker/ output/.gitkeep
git commit -m "chore: initialize repository skeleton"
```

---

### 任务 2：配置系统 — modules.ini + version.txt

**文件：**
- 创建：`config/modules.ini`
- 创建：`version.txt`

- [ ] **步骤 1：编写 config/modules.ini**

```bash
cat > /home/fox2/tmp/MultimediaSDK/config/modules.ini << 'INIEOF'
# ============================================================
# MultimediaSDK 模块配置
# 修改此文件即可调整裁剪范围，无需改任何脚本
# ============================================================

[core]
gstreamer = true
gst-plugins-base = true

[plugins.good]
rtsp = true
rtp = true
isomp4 = true
soup = true
opus = false
vpx = false
jack = false
oss = false

[plugins.bad]
codecparsers = true
d3d11 = true
va = true
nvcodec = true
mpegts = false
webrtc = false
hls = false
dash = false

[plugins.ugly]
enabled = false

[libav]
enabled = true

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
INIEOF
```

- [ ] **步骤 2：编写 version.txt**

```bash
echo "1.0.0" > /home/fox2/tmp/MultimediaSDK/version.txt
```

- [ ] **步骤 3：验证文件内容**

```bash
cd /home/fox2/tmp/MultimediaSDK
cat config/modules.ini
cat version.txt
```

- [ ] **步骤 4：提交**

```bash
cd /home/fox2/tmp/MultimediaSDK
git add config/modules.ini version.txt
git commit -m "feat: add module config and version file"
```

---

### 任务 3：FFmpeg 构建脚本

**文件：**
- 创建：`scripts/build-ffmpeg.sh`

`build-ffmpeg.sh` 负责读取 `config/modules.ini` 的 `[ffmpeg]` 段，生成 `./configure` flags，编译 FFmpeg 静态库，安装到指定目录。

- [ ] **步骤 1：编写 scripts/build-ffmpeg.sh**

```bash
cat > /home/fox2/tmp/MultimediaSDK/scripts/build-ffmpeg.sh << 'SHEOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FFMPEG_SRC="$PROJECT_ROOT/ffmpeg-7.1.5"

# 参数
INSTALL_DIR="${1:-$PROJECT_ROOT/output/build/ffmpeg-install}"
BUILD_DIR="$PROJECT_ROOT/output/build/ffmpeg-build"

# 读取 config/modules.ini 中 [ffmpeg] 段的 key=value
parse_ini_value() {
    local section="$1"
    local key="$2"
    awk -F= -v section="$section" -v key="$key" '
        /^\[/{in_section=0}
        $0 == "["section"]" {in_section=1; next}
        in_section && $1 == key {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}
    ' "$PROJECT_ROOT/config/modules.ini"
}

DECODERS=$(parse_ini_value ffmpeg decoders)
DEMUXERS=$(parse_ini_value ffmpeg demuxers)
MUXERS=$(parse_ini_value ffmpeg muxers)
PARSERS=$(parse_ini_value ffmpeg parsers)
ENCODERS=$(parse_ini_value ffmpeg encoders)
PROTOCOLS=$(parse_ini_value ffmpeg protocols)

# 生成 --enable/--disable flags
build_flag_list() {
    local prefix="$1"
    local list="$2"
    if [ -z "$list" ]; then
        echo "--disable-${prefix}s"
    else
        local IFS=','
        local flags=""
        for item in $list; do
            item=$(echo "$item" | xargs)
            [ -n "$item" ] && flags="$flags --enable-${prefix}=${item}"
        done
        echo "$flags"
    fi
}

echo "==> Configuring FFmpeg..."
mkdir -p "$BUILD_DIR"
cd "$FFMPEG_SRC"

./configure \
    --prefix="$INSTALL_DIR" \
    --disable-all \
    --enable-avcodec \
    --enable-avformat \
    --enable-avutil \
    $(build_flag_list decoder "$DECODERS") \
    $(build_flag_list demuxer "$DEMUXERS") \
    $(build_flag_list muxer "$MUXERS") \
    $(build_flag_list parser "$PARSERS") \
    $(build_flag_list encoder "$ENCODERS") \
    $(build_flag_list protocol "$PROTOCOLS") \
    --enable-bsf=h264_mp4toannexb \
    --disable-doc \
    --disable-programs \
    --disable-avdevice \
    --disable-postproc \
    --disable-avfilter \
    --disable-swscale \
    --enable-pic \
    --enable-static \
    --disable-shared

echo "==> Building FFmpeg..."
make -j$(nproc)

echo "==> Installing FFmpeg to $INSTALL_DIR..."
make install

echo "==> FFmpeg build complete."
echo "Libraries available at: $INSTALL_DIR/lib/"
ls -la "$INSTALL_DIR/lib/"*.a
SHEOF

chmod +x /home/fox2/tmp/MultimediaSDK/scripts/build-ffmpeg.sh
```

- [ ] **步骤 2：验证脚本语法**

```bash
bash -n /home/fox2/tmp/MultimediaSDK/scripts/build-ffmpeg.sh
```

预期：无语法错误。

- [ ] **步骤 3：验证 parse_ini_value 解析逻辑**

```bash
cd /home/fox2/tmp/MultimediaSDK
# 模拟解析
awk -F= -v section="ffmpeg" -v key="decoders" '
  /^\[/{in_section=0}
  $0 == "["section"]" {in_section=1; next}
  in_section && $1 == key {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}
' config/modules.ini
```

预期输出：`h264,hevc`

- [ ] **步骤 4：提交**

```bash
cd /home/fox2/tmp/MultimediaSDK
git add scripts/build-ffmpeg.sh
git commit -m "feat: add FFmpeg build script with config-driven flags"
```

---

### 任务 4：GStreamer 构建脚本

**文件：**
- 创建：`scripts/build-gstreamer.sh`

`build-gstreamer.sh` 读取 `config/modules.ini` 生成 Meson options，编译 GStreamer monorepo 子集。

- [ ] **步骤 1：编写 scripts/build-gstreamer.sh**

```bash
cat > /home/fox2/tmp/MultimediaSDK/scripts/build-gstreamer.sh << 'SHEOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
GST_SRC="$PROJECT_ROOT/gstreamer"

INSTALL_DIR="${1:-$PROJECT_ROOT/output/build/gst-install}"
BUILD_DIR="$PROJECT_ROOT/output/build/gst-build"
PKG_CONFIG_PATH="${2:-$PROJECT_ROOT/output/build/ffmpeg-install/lib/pkgconfig}"
FFMPEG_INSTALL="${3:-$PROJECT_ROOT/output/build/ffmpeg-install}"

# 解析 ini boolean
parse_ini_bool() {
    local section="$1"
    local key="$2"
    local val
    val=$(awk -F= -v section="$section" -v key="$key" '
        /^\[/{in_section=0}
        $0 == "["section"]" {in_section=1; next}
        in_section && $1 == key {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}
    ' "$PROJECT_ROOT/config/modules.ini")
    if [ "${val,,}" = "true" ] || [ "${val,,}" = "1" ]; then
        echo "true"
    else
        echo "false"
    fi
}

# --- 收集启用的子项目 ---
ENABLED_PROJECTS="gstreamer gst-plugins-base"

if [ "$(parse_ini_bool plugins.good rtsp)" = "true" ] || \
   [ "$(parse_ini_bool plugins.good rtp)" = "true" ] || \
   [ "$(parse_ini_bool plugins.good isomp4)" = "true" ] || \
   [ "$(parse_ini_bool plugins.good soup)" = "true" ]; then
    ENABLED_PROJECTS="$ENABLED_PROJECTS gst-plugins-good"
fi

if [ "$(parse_ini_bool plugins.bad codecparsers)" = "true" ] || \
   [ "$(parse_ini_bool plugins.bad d3d11)" = "true" ] || \
   [ "$(parse_ini_bool plugins.bad va)" = "true" ] || \
   [ "$(parse_ini_bool plugins.bad nvcodec)" = "true" ]; then
    ENABLED_PROJECTS="$ENABLED_PROJECTS gst-plugins-bad"
fi

if [ "$(parse_ini_bool libav enabled)" = "true" ]; then
    ENABLED_PROJECTS="$ENABLED_PROJECTS gst-libav"
fi

echo "==> Enabled subprojects: $ENABLED_PROJECTS"

# --- 构建 Meson options ---
MESON_OPTIONS=(
    "-Dauto_features=disabled"
    "-Dbuild-static=disabled"
    "-Ddefault_library=static"
    "-Dgst-full-libraries=$(echo $ENABLED_PROJECTS | tr ' ' ',')"
)

# good plugins
if [ "$(parse_ini_bool plugins.good soup)" = "false" ]; then
    MESON_OPTIONS+=("-Dsoup=disabled")
fi
if [ "$(parse_ini_bool plugins.good vpx)" = "false" ]; then
    MESON_OPTIONS+=("-Dvpx=disabled")
fi
if [ "$(parse_ini_bool plugins.good opus)" = "false" ]; then
    MESON_OPTIONS+=("-Dopus=disabled")
fi

# bad plugins
[ "$(parse_ini_bool plugins.bad d3d11)" = "true" ] && MESON_OPTIONS+=("-Dd3d11=enabled")
[ "$(parse_ini_bool plugins.bad va)" = "true" ] && MESON_OPTIONS+=("-Dva=enabled")
[ "$(parse_ini_bool plugins.bad nvcodec)" = "true" ] && MESON_OPTIONS+=("-Dnvcodec=enabled")
[ "$(parse_ini_bool plugins.bad webrtc)" = "false" ] && MESON_OPTIONS+=("-Dwebrtc=disabled")
[ "$(parse_ini_bool plugins.bad hls)" = "false" ] && MESON_OPTIONS+=("-Dhls=disabled")
[ "$(parse_ini_bool plugins.bad dash)" = "false" ] && MESON_OPTIONS+=("-Ddash=disabled")

# ugly
if [ "$(parse_ini_bool plugins.ugly enabled)" = "false" ]; then
    MESON_OPTIONS+=("-Dugly=disabled")
fi

# other subprojects
for proj in gst-rtsp-server gst-editing-services gst-python gst-devtools gst-examples; do
    if [ "$(parse_ini_bool other "$proj")" = "false" ]; then
        MESON_OPTIONS+=("-D$proj=disabled")
    fi
done

# gst-libav: point to custom FFmpeg build
if [ "$(parse_ini_bool libav enabled)" = "true" ]; then
    MESON_OPTIONS+=(
        "-Dlibav=enabled"
        "-Dlibav-ffmpeg-prefix=$FFMPEG_INSTALL"
    )
fi

echo "==> Meson options: ${MESON_OPTIONS[*]}"

# --- Build ---
export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:$FFMPEG_INSTALL/lib/pkgconfig"

mkdir -p "$BUILD_DIR"

cd "$GST_SRC"
meson setup "$BUILD_DIR" ${MESON_OPTIONS[@]}
meson compile -C "$BUILD_DIR"
DESTDIR="$INSTALL_DIR" meson install -C "$BUILD_DIR"

echo "==> GStreamer build complete."
echo "Installed to: $INSTALL_DIR"
SHEOF

chmod +x /home/fox2/tmp/MultimediaSDK/scripts/build-gstreamer.sh
```

- [ ] **步骤 2：验证脚本语法**

```bash
bash -n /home/fox2/tmp/MultimediaSDK/scripts/build-gstreamer.sh
```

- [ ] **步骤 3：验证 parse_ini_bool 逻辑**

```bash
cd /home/fox2/tmp/MultimediaSDK
# 测试 true
awk -F= -v section="libav" -v key="enabled" '
  /^\[/{in_section=0}
  $0 == "["section"]" {in_section=1; next}
  in_section && $1 == key {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}
' config/modules.ini && echo " -> should be: true"

# 测试 false
awk -F= -v section="plugins.ugly" -v key="enabled" '
  /^\[/{in_section=0}
  $0 == "["section"]" {in_section=1; next}
  in_section && $1 == key {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}
' config/modules.ini && echo " -> should be: false"
```

- [ ] **步骤 4：提交**

```bash
cd /home/fox2/tmp/MultimediaSDK
git add scripts/build-gstreamer.sh
git commit -m "feat: add GStreamer build script with config-driven meson options"
```

---

### 任务 5：顶层构建编排 — build.py

**文件：**
- 创建：`build.py`

- [ ] **步骤 1：编写 build.py**

```python
cat > /home/fox2/tmp/MultimediaSDK/build.py << 'PYEOF'
#!/usr/bin/env python3
"""MultimediaSDK build orchestrator."""

import argparse
import os
import platform
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent
SCRIPTS_DIR = PROJECT_ROOT / "scripts"
OUTPUT_DIR = PROJECT_ROOT / "output"


def run(cmd, **kwargs):
    print(f"\n==> Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=str(PROJECT_ROOT), **kwargs)
    if result.returncode != 0:
        print(f"ERROR: command failed with code {result.returncode}")
        sys.exit(result.returncode)


def detect_target(args):
    if args.target:
        return args.target
    system = platform.system().lower()
    machine = platform.machine().lower()
    if system == "linux":
        if machine in ("aarch64", "arm64"):
            return "linux-arm64"
        return "linux-x64"
    elif system == "windows":
        return "win-x64"
    else:
        print(f"ERROR: unsupported platform: {system}/{machine}")
        sys.exit(1)


def validate_target(target):
    valid = {"linux-x64", "linux-arm64", "win-x64"}
    if target not in valid:
        print(f"ERROR: invalid target '{target}'. Must be one of: {valid}")
        sys.exit(1)


def build(args):
    target = detect_target(args)
    validate_target(target)

    build_dir = OUTPUT_DIR / "build" / target
    sdk_dir = OUTPUT_DIR / "sdk" / target
    ffmpeg_install = build_dir / "ffmpeg-install"
    gst_install = build_dir / "gst-install"
    dist_dir = OUTPUT_DIR / "dist"

    if args.clean:
        import shutil
        for d in [build_dir, sdk_dir, dist_dir]:
            if d.exists():
                shutil.rmtree(d)
                print(f"Cleaned: {d}")

    build_dir.mkdir(parents=True, exist_ok=True)
    sdk_dir.mkdir(parents=True, exist_ok=True)

    # Step 1: Build FFmpeg
    print("\n========================================")
    print("STEP 1/4: Building FFmpeg")
    print("========================================")
    run(["bash", str(SCRIPTS_DIR / "build-ffmpeg.sh"),
         str(ffmpeg_install)])

    # Step 2: Build GStreamer
    print("\n========================================")
    print("STEP 2/4: Building GStreamer")
    print("========================================")
    run(["bash", str(SCRIPTS_DIR / "build-gstreamer.sh"),
         str(gst_install),
         str(ffmpeg_install / "lib" / "pkgconfig"),
         str(ffmpeg_install)])

    # Step 3: Merge into SDK layout
    print("\n========================================")
    print("STEP 3/4: Merging SDK artifacts")
    print("========================================")

    # Copy headers
    run(["cp", "-r", str(gst_install / "include"), str(sdk_dir)])

    # Copy libraries
    (sdk_dir / "lib").mkdir(exist_ok=True)
    run(["bash", "-c",
         f"cp -r {gst_install}/lib/*.a {sdk_dir}/lib/ 2>/dev/null || true"])
    run(["bash", "-c",
         f"cp -r {ffmpeg_install}/lib/*.a {sdk_dir}/lib/ 2>/dev/null || true"])

    # Copy plugins (dynamic)
    (sdk_dir / "plugins").mkdir(exist_ok=True)
    run(["bash", "-c",
         f"cp -r {gst_install}/lib/gstreamer-1.0/* {sdk_dir}/plugins/ 2>/dev/null || true"])

    # Generate CMake config
    print("  Generating CMake config...")
    cmake_template = PROJECT_ROOT / "cmake" / "MultimediaSDKConfig.cmake.in"
    cmake_output = sdk_dir / "cmake" / "MultimediaSDKConfig.cmake"
    (sdk_dir / "cmake").mkdir(exist_ok=True)

    if cmake_template.exists():
        content = cmake_template.read_text()
        content = content.replace("@CMAKE_INSTALL_PREFIX@", str(sdk_dir))
        content = content.replace("@VERSION@", (PROJECT_ROOT / "version.txt").read_text().strip())
        cmake_output.write_text(content)
    else:
        print("WARNING: cmake template not found, skipping CMake config generation")

    # Step 4: Package (optional)
    if args.package:
        print("\n========================================")
        print("STEP 4/4: Packaging")
        print("========================================")
        pkg_script = SCRIPTS_DIR / "package.sh"
        if pkg_script.exists():
            run(["bash", str(pkg_script), str(target)])
        else:
            print("WARNING: package.sh not found, skipping packaging")

    print("\n========================================")
    print(f"BUILD COMPLETE")
    print(f"SDK location: {sdk_dir}")
    print(f"  include/  -> headers")
    print(f"  lib/      -> static libraries")
    print(f"  plugins/  -> dynamic plugins")
    print(f"  cmake/     -> CMake config")
    print("========================================")
    return 0


def main():
    parser = argparse.ArgumentParser(description="MultimediaSDK build orchestrator")
    parser.add_argument("--target", choices=["linux-x64", "linux-arm64", "win-x64"],
                        help="Build target (auto-detect if omitted)")
    parser.add_argument("--clean", action="store_true", help="Clean build directories before build")
    parser.add_argument("--package", action="store_true", help="Package SDK after build")
    parser.add_argument("--verbose", action="store_true", help="Verbose output")

    args = parser.parse_args()
    build(args)


if __name__ == "__main__":
    main()
PYEOF

chmod +x /home/fox2/tmp/MultimediaSDK/build.py
```

- [ ] **步骤 2：验证 Python 语法**

```bash
python3 -c "import py_compile; py_compile.compile('/home/fox2/tmp/MultimediaSDK/build.py', doraise=True)"
```

- [ ] **步骤 3：验证 --help 可用**

```bash
python3 /home/fox2/tmp/MultimediaSDK/build.py --help
```

- [ ] **步骤 4：提交**

```bash
cd /home/fox2/tmp/MultimediaSDK
git add build.py
git commit -m "feat: add top-level build orchestrator"
```

---

### 任务 6：CMake 导出系统

**文件：**
- 创建：`cmake/MultimediaSDKConfig.cmake.in`
- 创建：`CMakeLists.txt`

- [ ] **步骤 1：编写 CMake 模板 cmake/MultimediaSDKConfig.cmake.in**

```bash
cat > /home/fox2/tmp/MultimediaSDK/cmake/MultimediaSDKConfig.cmake.in << 'CMAEOF'
# MultimediaSDK CMake Config
# Generated by build.py
# Usage: find_package(MultimediaSDK REQUIRED)

set(MultimediaSDK_VERSION "@VERSION@")
set(MultimediaSDK_ROOT_DIR "@CMAKE_INSTALL_PREFIX@")
set(MultimediaSDK_INCLUDE_DIRS "${MultimediaSDK_ROOT_DIR}/include")
set(MultimediaSDK_LIB_DIR "${MultimediaSDK_ROOT_DIR}/lib")
set(MultimediaSDK_PLUGIN_DIR "${MultimediaSDK_ROOT_DIR}/plugins")

# GStreamer core
add_library(MultimediaSDK::gstreamer STATIC IMPORTED)
set_target_properties(MultimediaSDK::gstreamer PROPERTIES
    IMPORTED_LOCATION "${MultimediaSDK_LIB_DIR}/libgstreamer-1.0.a"
    INTERFACE_INCLUDE_DIRECTORIES "${MultimediaSDK_INCLUDE_DIRS}/gstreamer-1.0"
    INTERFACE_LINK_LIBRARIES "MultimediaSDK::glib;MultimediaSDK::gobject"
)

add_library(MultimediaSDK::gstbase STATIC IMPORTED)
set_target_properties(MultimediaSDK::gstbase PROPERTIES
    IMPORTED_LOCATION "${MultimediaSDK_LIB_DIR}/libgstbase-1.0.a"
    INTERFACE_INCLUDE_DIRECTORIES "${MultimediaSDK_INCLUDE_DIRS}/gstreamer-1.0"
    INTERFACE_LINK_LIBRARIES "MultimediaSDK::gstreamer"
)

add_library(MultimediaSDK::gstvideo STATIC IMPORTED)
set_target_properties(MultimediaSDK::gstvideo PROPERTIES
    IMPORTED_LOCATION "${MultimediaSDK_LIB_DIR}/libgstvideo-1.0.a"
    INTERFACE_INCLUDE_DIRECTORIES "${MultimediaSDK_INCLUDE_DIRS}/gstreamer-1.0"
    INTERFACE_LINK_LIBRARIES "MultimediaSDK::gstbase"
)

add_library(MultimediaSDK::gstapp STATIC IMPORTED)
set_target_properties(MultimediaSDK::gstapp PROPERTIES
    IMPORTED_LOCATION "${MultimediaSDK_LIB_DIR}/libgstapp-1.0.a"
    INTERFACE_INCLUDE_DIRECTORIES "${MultimediaSDK_INCLUDE_DIRS}/gstreamer-1.0"
    INTERFACE_LINK_LIBRARIES "MultimediaSDK::gstbase"
)

add_library(MultimediaSDK::gstrtp STATIC IMPORTED)
set_target_properties(MultimediaSDK::gstrtp PROPERTIES
    IMPORTED_LOCATION "${MultimediaSDK_LIB_DIR}/libgstrtp-1.0.a"
    INTERFACE_INCLUDE_DIRECTORIES "${MultimediaSDK_INCLUDE_DIRS}/gstreamer-1.0"
    INTERFACE_LINK_LIBRARIES "MultimediaSDK::gstbase"
)

# GLib
add_library(MultimediaSDK::glib STATIC IMPORTED)
set_target_properties(MultimediaSDK::glib PROPERTIES
    IMPORTED_LOCATION "${MultimediaSDK_LIB_DIR}/libglib-2.0.a"
    INTERFACE_INCLUDE_DIRECTORIES "${MultimediaSDK_INCLUDE_DIRS}/glib-2.0"
)

add_library(MultimediaSDK::gobject STATIC IMPORTED)
set_target_properties(MultimediaSDK::gobject PROPERTIES
    IMPORTED_LOCATION "${MultimediaSDK_LIB_DIR}/libgobject-2.0.a"
    INTERFACE_INCLUDE_DIRECTORIES "${MultimediaSDK_INCLUDE_DIRS}/glib-2.0"
    INTERFACE_LINK_LIBRARIES "MultimediaSDK::glib"
)

# FFmpeg
add_library(MultimediaSDK::avcodec STATIC IMPORTED)
set_target_properties(MultimediaSDK::avcodec PROPERTIES
    IMPORTED_LOCATION "${MultimediaSDK_LIB_DIR}/libavcodec.a"
    INTERFACE_INCLUDE_DIRECTORIES "${MultimediaSDK_INCLUDE_DIRS}"
)

add_library(MultimediaSDK::avformat STATIC IMPORTED)
set_target_properties(MultimediaSDK::avformat PROPERTIES
    IMPORTED_LOCATION "${MultimediaSDK_LIB_DIR}/libavformat.a"
    INTERFACE_INCLUDE_DIRECTORIES "${MultimediaSDK_INCLUDE_DIRS}"
    INTERFACE_LINK_LIBRARIES "MultimediaSDK::avcodec"
)

add_library(MultimediaSDK::avutil STATIC IMPORTED)
set_target_properties(MultimediaSDK::avutil PROPERTIES
    IMPORTED_LOCATION "${MultimediaSDK_LIB_DIR}/libavutil.a"
    INTERFACE_INCLUDE_DIRECTORIES "${MultimediaSDK_INCLUDE_DIRS}"
)

# Convenience meta-target
add_library(MultimediaSDK::all INTERFACE IMPORTED)
set_target_properties(MultimediaSDK::all PROPERTIES
    INTERFACE_LINK_LIBRARIES "MultimediaSDK::gstreamer;MultimediaSDK::gstvideo;MultimediaSDK::gstapp;MultimediaSDK::gstrtp;MultimediaSDK::avformat;MultimediaSDK::avcodec;MultimediaSDK::avutil"
)

set(MultimediaSDK_FOUND TRUE)
CMAEOF
```

- [ ] **步骤 2：编写 CMakeLists.txt（安装项目）**

```bash
cat > /home/fox2/tmp/MultimediaSDK/CMakeLists.txt << 'CMAEOF'
cmake_minimum_required(VERSION 3.16)
project(MultimediaSDK VERSION 1.0.0 LANGUAGES C)

# This CMakeLists.txt is used for the SDK installation target.
# Actual builds are done via build.py + Meson/configure scripts.

set(CMAKE_INSTALL_PREFIX "${CMAKE_CURRENT_SOURCE_DIR}/output/sdk/linux-x64"
    CACHE PATH "SDK install prefix")

install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/output/sdk/linux-x64/"
        DESTINATION "."
        USE_SOURCE_PERMISSIONS
        OPTIONAL)
CMAEOF
```

- [ ] **步骤 3：提交**

```bash
cd /home/fox2/tmp/MultimediaSDK
git add cmake/MultimediaSDKConfig.cmake.in CMakeLists.txt
git commit -m "feat: add CMake export system"
```

---

### 任务 7：打包脚本

**文件：**
- 创建：`scripts/package.sh`

- [ ] **步骤 1：编写 scripts/package.sh**

```bash
cat > /home/fox2/tmp/MultimediaSDK/scripts/package.sh << 'SHEOF'
#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-linux-x64}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VERSION=$(cat "$PROJECT_ROOT/version.txt")
SDK_DIR="$PROJECT_ROOT/output/sdk/$TARGET"
DIST_DIR="$PROJECT_ROOT/output/dist"
PACKAGE_NAME="MultimediaSDK-${VERSION}-${TARGET}"

if [ ! -d "$SDK_DIR" ]; then
    echo "ERROR: SDK directory not found: $SDK_DIR"
    echo "Run build.py first."
    exit 1
fi

mkdir -p "$DIST_DIR"

echo "==> Packaging $PACKAGE_NAME..."

cd "$SDK_DIR"

case "$TARGET" in
    win*)
        zip -r "$DIST_DIR/${PACKAGE_NAME}.zip" *
        echo "==> Package: $DIST_DIR/${PACKAGE_NAME}.zip"
        ;;
    *)
        tar czf "$DIST_DIR/${PACKAGE_NAME}.tar.gz" *
        echo "==> Package: $DIST_DIR/${PACKAGE_NAME}.tar.gz"
        ;;
esac

# Generate checksum
sha256sum "$DIST_DIR/${PACKAGE_NAME}."* > "$DIST_DIR/${PACKAGE_NAME}.sha256"
echo "==> Checksum: $DIST_DIR/${PACKAGE_NAME}.sha256"

echo "==> Package complete."
SHEOF

chmod +x /home/fox2/tmp/MultimediaSDK/scripts/package.sh
```

- [ ] **步骤 2：验证脚本语法**

```bash
bash -n /home/fox2/tmp/MultimediaSDK/scripts/package.sh
```

- [ ] **步骤 3：提交**

```bash
cd /home/fox2/tmp/MultimediaSDK
git add scripts/package.sh
git commit -m "feat: add SDK packaging script"
```

---

### 任务 8：Docker 构建镜像

**文件：**
- 创建：`docker/linux-x64.Dockerfile`
- 创建：`docker/linux-arm64.Dockerfile`

- [ ] **步骤 1：编写 docker/linux-x64.Dockerfile**

```bash
cat > /home/fox2/tmp/MultimediaSDK/docker/linux-x64.Dockerfile << 'DOCKEOF'
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential \
    meson \
    ninja-build \
    cmake \
    pkg-config \
    python3 \
    python3-pip \
    git \
    curl \
    ca-certificates \
    nasm \
    yasm \
    bison \
    flex \
    libglib2.0-dev \
    libmount-dev \
    libselinux1-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --upgrade pip && pip3 install meson>=1.4

WORKDIR /workspace
DOCKEOF
```

- [ ] **步骤 2：编写 docker/linux-arm64.Dockerfile**

```bash
cat > /home/fox2/tmp/MultimediaSDK/docker/linux-arm64.Dockerfile << 'DOCKEOF'
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

RUN dpkg --add-architecture arm64 && \
    apt-get update && apt-get install -y \
    build-essential \
    meson \
    ninja-build \
    cmake \
    pkg-config \
    python3 \
    python3-pip \
    git \
    curl \
    ca-certificates \
    nasm \
    yasm \
    bison \
    flex \
    crossbuild-essential-arm64 \
    libglib2.0-dev:arm64 \
    libmount-dev:arm64 \
    libselinux1-dev:arm64 \
    zlib1g-dev:arm64 \
    gcc-aarch64-linux-gnu \
    g++-aarch64-linux-gnu \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --upgrade pip && pip3 install meson>=1.4

WORKDIR /workspace
DOCKEOF
```

- [ ] **步骤 3：提交**

```bash
cd /home/fox2/tmp/MultimediaSDK
git add docker/linux-x64.Dockerfile docker/linux-arm64.Dockerfile
git commit -m "feat: add Docker build images (ubuntu:20.04 base)"
```

---

### 任务 9：CI 流水线

**文件：**
- 创建：`.github/workflows/ci.yml`

- [ ] **步骤 1：编写 .github/workflows/ci.yml**

```bash
mkdir -p /home/fox2/tmp/MultimediaSDK/.github/workflows
cat > /home/fox2/tmp/MultimediaSDK/.github/workflows/ci.yml << 'YAMLEOF'
name: MultimediaSDK CI

on:
  push:
    branches: [main]
    tags: ['v*']
  pull_request:
    branches: [main]
  workflow_dispatch:

jobs:
  build-linux-x64:
    name: Build Linux x64
    runs-on: ubuntu-22.04
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Build Docker image
        run: docker build -t multimedia-sdk:linux-x64 -f docker/linux-x64.Dockerfile .

      - name: Build SDK
        run: |
          docker run --rm \
            -v $PWD:/workspace \
            -w /workspace \
            multimedia-sdk:linux-x64 \
            python3 build.py --target linux-x64 --clean

      - name: Package
        run: |
          docker run --rm \
            -v $PWD:/workspace \
            -w /workspace \
            multimedia-sdk:linux-x64 \
            bash scripts/package.sh linux-x64

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: MultimediaSDK-linux-x64
          path: output/dist/*.tar.gz

  build-linux-arm64:
    name: Build Linux ARM64
    runs-on: ubuntu-22.04
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Install QEMU
        run: |
          docker run --rm --privileged multiarch/qemu-user-static --reset -p yes

      - name: Build Docker image
        run: docker build -t multimedia-sdk:linux-arm64 -f docker/linux-arm64.Dockerfile .

      - name: Build SDK
        run: |
          docker run --rm \
            -v $PWD:/workspace \
            -w /workspace \
            multimedia-sdk:linux-arm64 \
            python3 build.py --target linux-arm64 --clean

      - name: Package
        run: |
          docker run --rm \
            -v $PWD:/workspace \
            -w /workspace \
            multimedia-sdk:linux-arm64 \
            bash scripts/package.sh linux-arm64

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: MultimediaSDK-linux-arm64
          path: output/dist/*.tar.gz

  build-win-x64:
    name: Build Windows x64
    runs-on: windows-2022
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Setup MSVC
        uses: ilammy/msvc-dev-cmd@v1

      - name: Setup Meson
        run: pip install meson>=1.4 ninja

      - name: Build and Package
         run: python build.py --target win-x64 --clean --package

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: MultimediaSDK-win-x64
          path: output/dist/*.zip

  release:
    name: Create Release
    needs: [build-linux-x64, build-linux-arm64, build-win-x64]
    if: startsWith(github.ref, 'refs/tags/v')
    runs-on: ubuntu-latest
    steps:
      - name: Download all artifacts
        uses: actions/download-artifact@v4

      - name: Create Release
        uses: softprops/action-gh-release@v2
        with:
          files: |
            MultimediaSDK-linux-x64/*.tar.gz
            MultimediaSDK-linux-arm64/*.tar.gz
            MultimediaSDK-win-x64/*.zip
          generate_release_notes: true
YAMLEOF
```

- [ ] **步骤 2：验证 YAML 语法**

```bash
python3 -c "import yaml; yaml.safe_load(open('/home/fox2/tmp/MultimediaSDK/.github/workflows/ci.yml'))" 2>/dev/null || echo "python3-yaml not installed (non-critical)"
bash -c 'command -v yamllint && yamllint /home/fox2/tmp/MultimediaSDK/.github/workflows/ci.yml || echo "yamllint not installed (non-critical)"'
```

- [ ] **步骤 3：提交**

```bash
cd /home/fox2/tmp/MultimediaSDK
git add .github/
git commit -m "feat: add CI pipeline (linux-x64, linux-arm64, win-x64)"
```

---

### 任务 10：README 和 CHANGELOG

**文件：**
- 创建：`README.md`
- 创建：`CHANGELOG.md`

- [ ] **步骤 1：编写 README.md**

```bash
cat > /home/fox2/tmp/MultimediaSDK/README.md << 'MDEOF'
# MultimediaSDK

Cross-platform multimedia SDK providing RTSP streaming, H.264 decoding, and MP4 recording based on GStreamer + FFmpeg.

## Features

- RTSP pull (TCP/UDP) via GStreamer rtspsrc
- H.264 decode (CPU: avdec_h264, GPU: D3D11VA / VAAPI / NVDEC)
- MP4 lossless recording (remux, no re-encoding)
- Hardware decode auto-detection at runtime
- Self-contained build from source (no system GStreamer/FFmpeg required)

## Supported Platforms

| Platform | Minimum OS | Compiler |
|----------|-----------|----------|
| Linux x64 | Ubuntu 20.04+ | GCC 9.4+ |
| Linux ARM64 | Ubuntu 20.04+ | aarch64-linux-gnu |
| Windows x64 | Windows 10 / Server 2019+ | MSVC 2019+ |

## Quick Start

### Build from source

```bash
git clone --recurse-submodules https://github.com/example/MultimediaSDK.git
cd MultimediaSDK

# Build (auto-detect platform)
python3 build.py

# Or specify target explicitly
python3 build.py --target linux-x64 --package
```

### Using the SDK

```cmake
find_package(MultimediaSDK REQUIRED)

add_executable(my_app main.c)
target_link_libraries(my_app
    MultimediaSDK::gstreamer
    MultimediaSDK::gstvideo
    MultimediaSDK::gstapp
)
```

```c
#include <gst/gst.h>

int main(int argc, char *argv[]) {
    gst_init(&argc, &argv);
    GstElement *pipeline = gst_parse_launch(
        "rtspsrc location=rtsp://... ! rtph264depay ! h264parse ! "
        "avdec_h264 ! mp4mux ! filesink location=output.mp4",
        NULL
    );
    gst_element_set_state(pipeline, GST_STATE_PLAYING);
    // ...
}
```

## SDK Layout

```
MultimediaSDK-1.0.0-linux-x64/
├── include/    # GStreamer, GLib, FFmpeg headers
├── lib/        # Static libraries (.a)
├── plugins/    # GStreamer dynamic plugins (.so/.dll)
└── cmake/      # CMake config (find_package)
```

## Customization

Edit `config/modules.ini` to enable/disable modules:

```ini
[plugins.bad]
d3d11 = false      # Disable D3D11VA
va = false         # Disable VAAPI
nvcodec = false     # Disable NVDEC

[ffmpeg]
decoders = h264     # CPU-only H.264 decode
```

Then rebuild: `python3 build.py --clean`

## License

GStreamer and FFmpeg components are under their respective licenses (LGPL/GPL). See LICENSE file.
MDEOF
```

- [ ] **步骤 2：编写 CHANGELOG.md**

```bash
cat > /home/fox2/tmp/MultimediaSDK/CHANGELOG.md << 'MDEOF'
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
MDEOF
```

- [ ] **步骤 3：提交**

```bash
cd /home/fox2/tmp/MultimediaSDK
git add README.md CHANGELOG.md
git commit -m "docs: add README and CHANGELOG"
```

---

### 任务 11：端到端验证

> **注意：** 此任务需在 GStreamer 和 FFmpeg submodule 可用时执行。

- [ ] **步骤 1：验证项目完整性 — 所有文件存在**

```bash
cd /home/fox2/tmp/MultimediaSDK
echo "=== Checking project structure ==="
ls -la build.py version.txt CMakeLists.txt
ls -la config/modules.ini
ls -la scripts/build-ffmpeg.sh scripts/build-gstreamer.sh scripts/package.sh
ls -la cmake/MultimediaSDKConfig.cmake.in
ls -la docker/linux-x64.Dockerfile docker/linux-arm64.Dockerfile
ls -la .github/workflows/ci.yml
ls -la README.md CHANGELOG.md .gitignore

echo ""
echo "=== All files present ==="
```

- [ ] **步骤 2：验证所有脚本语法**

```bash
cd /home/fox2/tmp/MultimediaSDK
bash -n scripts/build-ffmpeg.sh && echo "build-ffmpeg.sh OK"
bash -n scripts/build-gstreamer.sh && echo "build-gstreamer.sh OK"
bash -n scripts/package.sh && echo "package.sh OK"
python3 -c "import py_compile; py_compile.compile('build.py', doraise=True)" && echo "build.py OK"
```

- [ ] **步骤 3：验证 build.py --target 参数**

```bash
cd /home/fox2/tmp/MultimediaSDK
python3 build.py --help

# 验证 target 验证逻辑
python3 build.py --target invalid-target 2>&1 || echo "(expected error)"
```

- [ ] **步骤 4：Git log 记录**

```bash
cd /home/fox2/tmp/MultimediaSDK
git log --oneline
```

- [ ] **步骤 5：提交（如有剩余变更）**

```bash
cd /home/fox2/tmp/MultimediaSDK
git status
# 如果有未提交的变更再 commit
```
