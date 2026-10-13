#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PRODUCT_NAME="PeekForCodex"
APP_NAME="Peek for Codex.app"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"
VERSION="${VERSION:-0.2.1}"
BUILD_NUMBER="${BUILD_NUMBER:-9}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-me.jacopobassan.peekforcodex}"
APP_OUTPUT_DIR="${APP_OUTPUT_DIR:-$ROOT_DIR/dist}"
APP_DIR="$APP_OUTPUT_DIR/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_TEMPLATE="$ROOT_DIR/Support/Info.plist"
INFO_PLIST="$CONTENTS_DIR/Info.plist"
SOURCE_ICON="$ROOT_DIR/Resources/PeekForCodex.icns"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
typeset -a BUILD_ARGS SIGNING_ARGS
BUILD_ARGS=(-c "$BUILD_CONFIGURATION")
if [[ -n "${SCRATCH_PATH:-}" ]]; then
    BUILD_ARGS+=(--scratch-path "$SCRATCH_PATH")
fi
if [[ -n "${ARCHES:-}" ]]; then
    for architecture in ${=ARCHES}; do
        case "$architecture" in
            arm64|x86_64) BUILD_ARGS+=(--arch "$architecture") ;;
            *) echo "Unsupported architecture: $architecture" >&2; exit 1 ;;
        esac
    done
fi

mkdir -p "$APP_OUTPUT_DIR"

cd "$ROOT_DIR"

env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
    SWIFTPM_CUSTOM_CACHE_PATH=/tmp/swiftpm-cache \
    swift build "${BUILD_ARGS[@]}"

BIN_PATH="$(env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
    SWIFTPM_CUSTOM_CACHE_PATH=/tmp/swiftpm-cache \
    swift build "${BUILD_ARGS[@]}" --show-bin-path)"
EXECUTABLE_PATH="$BIN_PATH/$PRODUCT_NAME"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
    echo "Expected executable not found at $EXECUTABLE_PATH" >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE_PATH" "$MACOS_DIR/$PRODUCT_NAME"
chmod +x "$MACOS_DIR/$PRODUCT_NAME"
cp "$SOURCE_ICON" "$RESOURCES_DIR/PeekForCodex.icns"
cp "$ROOT_DIR/Resources/Assets.car" "$RESOURCES_DIR/Assets.car"
cp "$ROOT_DIR/LICENSE" "$RESOURCES_DIR/LICENSE.txt"
cp "$ROOT_DIR/Resources/ThirdPartyNotices.txt" "$RESOURCES_DIR/ThirdPartyNotices.txt"
SPARKLE_SDK="${SCRATCH_PATH:-$ROOT_DIR/.build}/artifacts/sparkle/Sparkle"
SPARKLE_FRAMEWORK="$SPARKLE_SDK/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[[ -d "$SPARKLE_FRAMEWORK" ]] || { echo "Sparkle framework was not resolved by SwiftPM." >&2; exit 1; }
mkdir -p "$CONTENTS_DIR/Frameworks"
ditto "$SPARKLE_FRAMEWORK" "$CONTENTS_DIR/Frameworks/Sparkle.framework"
cp "$SPARKLE_SDK/LICENSE" "$RESOURCES_DIR/Sparkle-LICENSE.txt"

sed \
    -e "s|__BUNDLE_IDENTIFIER__|$BUNDLE_IDENTIFIER|g" \
    -e "s|__VERSION__|$VERSION|g" \
    -e "s|__BUILD_NUMBER__|$BUILD_NUMBER|g" \
    "$INFO_TEMPLATE" > "$INFO_PLIST"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    SIGNING_ARGS=(--timestamp=none)
else
    SIGNING_ARGS=(--options runtime --timestamp)
fi
FRAMEWORK="$CONTENTS_DIR/Frameworks/Sparkle.framework/Versions/B"
# Sign each nested executable before its containing framework and app.
for component in \
    "$FRAMEWORK/Autoupdate" \
    "$FRAMEWORK/Updater.app" \
    "$FRAMEWORK/XPCServices/Installer.xpc" \
    "$FRAMEWORK/XPCServices/Downloader.xpc" \
    "$CONTENTS_DIR/Frameworks/Sparkle.framework" \
    "$APP_DIR"; do
    codesign --force --sign "$SIGNING_IDENTITY" "${SIGNING_ARGS[@]}" "$component"
done
codesign --verify --deep --strict "$APP_DIR"

echo "Built $APP_DIR"
