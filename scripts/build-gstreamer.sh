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
        in_section {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)}
        in_section && $1 == key {print $2; exit}
    ' "$PROJECT_ROOT/config/modules.ini")
    [ "${val,,}" = "true" ] || [ "${val,,}" = "1" ] && echo "true" || echo "false"
}

echo "==> Reading module configuration..."

MESON_OPTIONS=(
    "-Dauto_features=disabled"
    "-Ddoc=disabled"
    "-Dgst-plugins-base:doc=disabled"
    "-Dgst-plugins-good:doc=disabled"
    "-Dgst-plugins-bad:doc=disabled"
    "-Dgst-libav:doc=disabled"
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
    "-Dtests=disabled"
    "-Dexamples=disabled"
    "-Dintrospection=disabled"
    "-Dnls=disabled"
    "-Dtools=disabled"
    "-Dtls=disabled"
    "-Dlibnice=disabled"
    "-Dgtk=disabled"
    "-Dwebrtc=disabled"
)

# --- gst-plugins-good: only enable what we need ---
enable_if_needed() {
    local subproj="$1"
    local key="$2"
    if [ "$(parse_ini_bool "$3" "$4")" = "true" ]; then
        MESON_OPTIONS+=("-D${subproj}:${key}=enabled")
    fi
}

enable_if_needed "gst-plugins-good" "rtsp"       "plugins.good" "rtsp"
enable_if_needed "gst-plugins-good" "rtp"        "plugins.good" "rtp"
enable_if_needed "gst-plugins-good" "rtpmanager" "plugins.good" "rtp"
enable_if_needed "gst-plugins-good" "udp"        "plugins.good" "rtsp"
enable_if_needed "gst-plugins-good" "isomp4"     "plugins.good" "isomp4"
enable_if_needed "gst-plugins-good" "soup"       "plugins.good" "soup"

# --- gst-plugins-bad ---
enable_if_needed "gst-plugins-bad" "videoparsers" "plugins.bad" "codecparsers"
enable_if_needed "gst-plugins-bad" "d3d11"        "plugins.bad" "d3d11"
enable_if_needed "gst-plugins-bad" "va"           "plugins.bad" "va"
enable_if_needed "gst-plugins-bad" "nvcodec"      "plugins.bad" "nvcodec"

# --- gst-plugins-base: always-enable essential utilities ---
MESON_OPTIONS+=(
    "-Dgst-plugins-base:playback=enabled"
    "-Dgst-plugins-base:videoconvertscale=enabled"
    "-Dgst-plugins-base:app=enabled"
    "-Dgst-plugins-base:tcp=enabled"
    "-Dgst-plugins-base:audioconvert=enabled"
    "-Dgst-plugins-base:audioresample=enabled"
)

# --- libav ---
if [ "$(parse_ini_bool libav enabled)" = "true" ]; then
    MESON_OPTIONS+=("-Dlibav=enabled")
    export PKG_CONFIG_PATH="$FFMPEG_PC_PATH:$FFMPEG_INSTALL/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
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
