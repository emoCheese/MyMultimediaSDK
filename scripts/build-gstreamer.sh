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

MESON_OPTIONS=(
    "-Dauto_features=disabled"
    "-Ddefault_library=static"
    "-Dgst-full-libraries=$(echo $ENABLED_PROJECTS | tr ' ' ',')"
)

if [ "$(parse_ini_bool plugins.good soup)" = "false" ]; then
    MESON_OPTIONS+=("-Dsoup=disabled")
fi
if [ "$(parse_ini_bool plugins.good vpx)" = "false" ]; then
    MESON_OPTIONS+=("-Dvpx=disabled")
fi
if [ "$(parse_ini_bool plugins.good opus)" = "false" ]; then
    MESON_OPTIONS+=("-Dopus=disabled")
fi

[ "$(parse_ini_bool plugins.bad d3d11)" = "true" ] && MESON_OPTIONS+=("-Dd3d11=enabled")
[ "$(parse_ini_bool plugins.bad va)" = "true" ] && MESON_OPTIONS+=("-Dva=enabled")
[ "$(parse_ini_bool plugins.bad nvcodec)" = "true" ] && MESON_OPTIONS+=("-Dnvcodec=enabled")
[ "$(parse_ini_bool plugins.bad webrtc)" = "false" ] && MESON_OPTIONS+=("-Dwebrtc=disabled")
[ "$(parse_ini_bool plugins.bad hls)" = "false" ] && MESON_OPTIONS+=("-Dhls=disabled")
[ "$(parse_ini_bool plugins.bad dash)" = "false" ] && MESON_OPTIONS+=("-Ddash=disabled")

if [ "$(parse_ini_bool plugins.ugly enabled)" = "false" ]; then
    MESON_OPTIONS+=("-Dugly=disabled")
fi

for proj in gst-rtsp-server gst-editing-services gst-python gst-devtools gst-examples; do
    if [ "$(parse_ini_bool other "$proj")" = "false" ]; then
        MESON_OPTIONS+=("-D$proj=disabled")
    fi
done

if [ "$(parse_ini_bool libav enabled)" = "true" ]; then
    MESON_OPTIONS+=(
        "-Dlibav=enabled"
        "-Dlibav-ffmpeg-prefix=$FFMPEG_INSTALL"
    )
fi

echo "==> Meson options: ${MESON_OPTIONS[*]}"

export PKG_CONFIG_PATH="$FFMPEG_PC_PATH:$FFMPEG_INSTALL/lib/pkgconfig"

mkdir -p "$BUILD_DIR"

cd "$GST_SRC"
meson setup "$BUILD_DIR" ${MESON_OPTIONS[@]}
meson compile -C "$BUILD_DIR"
DESTDIR="$INSTALL_DIR" meson install -C "$BUILD_DIR"

echo "==> GStreamer build complete."
echo "Installed to: $INSTALL_DIR"
