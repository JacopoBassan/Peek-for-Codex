#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PRODUCT_NAME="CodexUsageBar"
APP_NAME="Peek for Codex.app"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-me.jacopobassan.peekforcodex}"
APP_DIR="$ROOT_DIR/dist/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_TEMPLATE="$ROOT_DIR/Support/Info.plist"
INFO_PLIST="$CONTENTS_DIR/Info.plist"
SOURCE_ICON="$ROOT_DIR/Resources/CodexUsageBar.icns"

mkdir -p "$ROOT_DIR/dist"

cd "$ROOT_DIR"

env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
    SWIFTPM_CUSTOM_CACHE_PATH=/tmp/swiftpm-cache \
    swift build -c "$BUILD_CONFIGURATION"

EXECUTABLE_PATH="$(find "$ROOT_DIR/.build" -path "*/${BUILD_CONFIGURATION}/${PRODUCT_NAME}" -type f 2>/dev/null | head -n 1)"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
    echo "Expected executable not found at $EXECUTABLE_PATH" >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE_PATH" "$MACOS_DIR/$PRODUCT_NAME"
chmod +x "$MACOS_DIR/$PRODUCT_NAME"
cp "$SOURCE_ICON" "$RESOURCES_DIR/CodexUsageBar.icns"

sed \
    -e "s|__BUNDLE_IDENTIFIER__|$BUNDLE_IDENTIFIER|g" \
    -e "s|__VERSION__|$VERSION|g" \
    -e "s|__BUILD_NUMBER__|$BUILD_NUMBER|g" \
    "$INFO_TEMPLATE" > "$INFO_PLIST"

codesign --force --deep --sign - "$APP_DIR"

echo "Built $APP_DIR"
