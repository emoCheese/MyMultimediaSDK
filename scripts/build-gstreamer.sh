#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
GST_SRC="$PROJECT_ROOT/gstreamer"

INSTALL_DIR="${1:-$PROJECT_ROOT/output/build/gst-install}"
BUILD_DIR="$PROJECT_ROOT/output/build/gst-build"
FFMPEG_PC_PATH="${2:-$PROJECT_ROOT/output/build/ffmpeg-install/lib/pkgconfig}"
FFMPEG_INSTALL="${3:-$PROJECT_ROOT/output/build/ffmpeg-install}"

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

echo "==> Reading module configuration..."

MESON_OPTIONS=(
    "-Ddefault_library=static"
    "-Dgood=enabled"
    "-Dbad=enabled"
    "-Dugly=disabled"
    "-Drs=disabled"
    "-Dsharp=disabled"
    "-Dpython=disabled"
    "-Drtsp_server=disabled"
    "-Dges=disabled"
    "-Ddevtools=disabled"
    "-Dgst-examples=disabled"
    "-Ddoc=disabled"
    "-Dgtk_doc=disabled"
    "-Dtests=disabled"
    "-Dexamples=disabled"
    "-Dintrospection=disabled"
    "-Dnls=disabled"
    "-Dtools=disabled"
)

# --- gst-plugins-good subproject options ---
enable_good_feature() {
    local key="$1"
    if [ "$(parse_ini_bool plugins.good "$key")" = "true" ]; then
        MESON_OPTIONS+=("-Dgst-plugins-good:${key}=enabled")
    else
        MESON_OPTIONS+=("-Dgst-plugins-good:${key}=disabled")
    fi
}

enable_good_feature "rtsp"
enable_good_feature "rtp"
enable_good_feature "rtpmanager"
enable_good_feature "udp"
enable_good_feature "isomp4"
enable_good_feature "soup"
enable_good_feature "vpx"
enable_good_feature "opus"
enable_good_feature "jack"
enable_good_feature "oss"
enable_good_feature "oss4"
enable_good_feature "pulse"
enable_good_feature "cairo"
enable_good_feature "flac"
enable_good_feature "jpeg"
enable_good_feature "png"
enable_good_feature "speex"
enable_good_feature "taglib"
enable_good_feature "wavpack"
enable_good_feature "lame"
enable_good_feature "mpg123"
enable_good_feature "dv"
enable_good_feature "dv1394"
enable_good_feature "shout2"
enable_good_feature "twolame"
enable_good_feature "bz2"
enable_good_feature "amrnb"
enable_good_feature "amrwbdec"
enable_good_feature "directsound"
enable_good_feature "osxaudio"
enable_good_feature "osxvideo"
enable_good_feature "waveform"
enable_good_feature "gtk3"
enable_good_feature "gdk-pixbuf"
enable_good_feature "adaptivedemux2"
enable_good_feature "ximagesrc"
enable_good_feature "v4l2"
enable_good_feature "rpicamsrc"
enable_good_feature "qt5"
enable_good_feature "qt6"

# --- gst-plugins-bad subproject options ---
enable_bad_feature() {
    local key="$1"
    if [ "$(parse_ini_bool plugins.bad "$key")" = "true" ]; then
        MESON_OPTIONS+=("-Dgst-plugins-bad:${key}=enabled")
    else
        MESON_OPTIONS+=("-Dgst-plugins-bad:${key}=disabled")
    fi
}

# codecparsers maps to videoparsers in the meson option
if [ "$(parse_ini_bool plugins.bad codecparsers)" = "true" ]; then
    MESON_OPTIONS+=("-Dgst-plugins-bad:videoparsers=enabled")
else
    MESON_OPTIONS+=("-Dgst-plugins-bad:videoparsers=disabled")
fi

enable_bad_feature "d3d11"
enable_bad_feature "va"
enable_bad_feature "nvcodec"

# Explicitly disable heavy/optional bad features
for feat in webrtc hls dash mpegtsdemux mpegtsmux smoothstreaming aom srt rtmp rtmp2 \
            opencv openh264 msdk qsv vulkan gl magicleap x265 fdkaac faac faad dts \
            mpeg2enc mplex resindvd soundtouch sndfile lc3 ldac openaptx \
            svtav1 svthevcenc svtjpegxs vmaf tflite onnx mediafoundation \
            wasapi wasapi2 winscreencap wic win32ipc winks directshow \
            applemedia androidmedia bluez ladspa lv2; do
    MESON_OPTIONS+=("-Dgst-plugins-bad:${feat}=disabled")
done

# --- gst-plugins-base subproject options ---
for feat in gl gl-graphene gl-jpeg gl-png iso-codes drm; do
    MESON_OPTIONS+=("-Dgst-plugins-base:${feat}=disabled")
done

# --- libav ---
if [ "$(parse_ini_bool libav enabled)" = "true" ]; then
    MESON_OPTIONS+=("-Dlibav=enabled")
    export PKG_CONFIG_PATH="$FFMPEG_PC_PATH:$FFMPEG_INSTALL/lib/pkgconfig:$PKG_CONFIG_PATH"
else
    MESON_OPTIONS+=("-Dlibav=disabled")
fi

echo "==> Meson options (${#MESON_OPTIONS[@]} total):"
printf '  %s\n' "${MESON_OPTIONS[@]}"

mkdir -p "$BUILD_DIR"

cd "$GST_SRC"
meson setup "$BUILD_DIR" "${MESON_OPTIONS[@]}"
meson compile -C "$BUILD_DIR"
DESTDIR="$INSTALL_DIR" meson install -C "$BUILD_DIR"

echo "==> GStreamer build complete."
echo "Installed to: $INSTALL_DIR"
