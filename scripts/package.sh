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

sha256sum "$DIST_DIR/${PACKAGE_NAME}."* > "$DIST_DIR/${PACKAGE_NAME}.sha256"
echo "==> Checksum: $DIST_DIR/${PACKAGE_NAME}.sha256"

echo "==> Package complete."
