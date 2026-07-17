#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SDK_DIR="$PROJECT_ROOT/output/sdk/linux-x64"
BUILD_DIR="$SCRIPT_DIR/build"

if [ ! -d "$SDK_DIR/lib" ]; then
    echo "ERROR: SDK not built. Run 'python3 build.py' first."
    exit 1
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo "==> Configuring with CMake..."
cmake "$SCRIPT_DIR" \
    -DMultimediaSDK_DIR="$SDK_DIR/cmake" \
    -DCMAKE_BUILD_TYPE=Release

echo "==> Building..."
cmake --build . -- -j$(nproc)

echo "==> Running smoke test..."

export GST_PLUGIN_PATH="$SDK_DIR/plugins"
export LD_LIBRARY_PATH="$SDK_DIR/lib:${LD_LIBRARY_PATH:-}"

./smoke_test
