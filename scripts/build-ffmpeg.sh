#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FFMPEG_SRC="$PROJECT_ROOT/ffmpeg-7.1.5"

INSTALL_DIR="${1:-$PROJECT_ROOT/output/build/ffmpeg-install}"
BUILD_DIR="$PROJECT_ROOT/output/build/ffmpeg-build"

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
