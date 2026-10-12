#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.2.0}"
RELEASE_TAG="${RELEASE_TAG:-v$VERSION}"
MODE=release
case "${1:-}" in
    --preview) MODE=preview ;;
    --help|-h)
        echo "Usage: ./scripts/package-dmg.sh [--preview]"
        echo "Release requires SIGNING_IDENTITY and NOTARY_KEYCHAIN_PROFILE."
        echo "--preview creates an ad-hoc-signed installer for local verification only."
        exit 0 ;;
    "") ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
esac
[[ $# -le 1 ]] || { echo "Too many arguments." >&2; exit 1; }

if [[ "$MODE" == release ]]; then
    [[ "${SIGNING_IDENTITY:-}" == "Developer ID Application: "* ]] || {
        echo "Set SIGNING_IDENTITY to a Developer ID Application certificate's full name." >&2
        exit 1
    }
    [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]] || {
        echo "Set NOTARY_KEYCHAIN_PROFILE to your saved notarytool profile." >&2
        exit 1
    }
else
    export SIGNING_IDENTITY=-
fi

OUTPUT_DIR="$ROOT_DIR/dist/$MODE"
mkdir -p "$OUTPUT_DIR"
WORK_DIR="$(mktemp -d /tmp/peek-for-codex-dmg.XXXXXX)"
WORK_DIR="$(cd "$WORK_DIR" && pwd -P)"
APP_DIR="$WORK_DIR/build/Peek for Codex.app"
# Cleanup is restricted to this script's exact, newly created /tmp workspace.
MOUNT_DIR="$WORK_DIR/mounted"
cleanup() {
    if mount | /usr/bin/grep -Fq " on $MOUNT_DIR ("; then
        hdiutil detach "$MOUNT_DIR" >/dev/null || return 1
    fi
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

ARCHES="arm64 x86_64" SCRATCH_PATH="$ROOT_DIR/.build/distribution" \
    APP_OUTPUT_DIR="$WORK_DIR/build" BUILD_CONFIGURATION=release "$ROOT_DIR/scripts/build.sh"
for architecture in arm64 x86_64; do
    lipo "$APP_DIR/Contents/MacOS/PeekForCodex" -verify_arch "$architecture"
done

if [[ "$MODE" == release ]]; then
    codesign --display --verbose=4 "$APP_DIR" 2> "$WORK_DIR/signature.txt"
    /usr/bin/grep -q '^Authority=Developer ID Application:' "$WORK_DIR/signature.txt" || {
        echo "The app does not have a Developer ID Application signature." >&2; exit 1
    }
fi

mkdir "$WORK_DIR/contents"
ditto "$APP_DIR" "$WORK_DIR/contents/Peek for Codex.app"
ln -s /Applications "$WORK_DIR/contents/Applications"
mkdir "$WORK_DIR/contents/.background"
xcrun swift "$ROOT_DIR/Support/DiskImageBackground.swift" "$WORK_DIR/contents/.background/background.tiff"

ARTIFACT_NAME=Peek-for-Codex.dmg
if [[ "$MODE" == preview ]]; then
    ARTIFACT_NAME=Peek-for-Codex-preview.dmg
fi
hdiutil create -srcfolder "$WORK_DIR/contents" -volname "Peek for Codex" \
    -format UDRW -fs HFS+ "$WORK_DIR/layout.dmg"
mkdir "$MOUNT_DIR"
hdiutil attach "$WORK_DIR/layout.dmg" -nobrowse -mountpoint "$MOUNT_DIR"
osascript "$ROOT_DIR/Support/DiskImageLayout.applescript" "$MOUNT_DIR"
# Closing the Finder window commits its per-volume layout before conversion.
[[ -s "$MOUNT_DIR/.DS_Store" ]] || { echo "Finder did not save the installer layout." >&2; exit 1; }
cp "$ROOT_DIR/Resources/PeekForCodex.icns" "$MOUNT_DIR/.VolumeIcon.icns"
xcrun SetFile -a C "$MOUNT_DIR"
hdiutil detach "$MOUNT_DIR"
hdiutil convert "$WORK_DIR/layout.dmg" -format UDZO -o "$WORK_DIR/$ARTIFACT_NAME"

if [[ "$MODE" == release ]]; then
    codesign --sign "$SIGNING_IDENTITY" --timestamp "$WORK_DIR/$ARTIFACT_NAME"
    xcrun notarytool submit "$WORK_DIR/$ARTIFACT_NAME" \
        --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait --output-format plist \
        > "$WORK_DIR/notarization-result.plist"
    NOTARY_STATUS="$(/usr/libexec/PlistBuddy -c 'Print :status' "$WORK_DIR/notarization-result.plist")"
    [[ "$NOTARY_STATUS" == Accepted ]] || {
        echo "Notarization was not accepted; no release installer was created." >&2; exit 1
    }
    xcrun stapler staple "$WORK_DIR/$ARTIFACT_NAME"
    xcrun stapler validate "$WORK_DIR/$ARTIFACT_NAME"
    spctl --assess --type open --context context:primary-signature "$WORK_DIR/$ARTIFACT_NAME"
fi

hdiutil verify "$WORK_DIR/$ARTIFACT_NAME"
(cd "$WORK_DIR" && shasum -a 256 "$ARTIFACT_NAME" > "$ARTIFACT_NAME.sha256")
if [[ "$MODE" == release ]]; then
    mkdir "$WORK_DIR/updates"
    cp "$WORK_DIR/$ARTIFACT_NAME" "$WORK_DIR/updates/$ARTIFACT_NAME"
    SPARKLE_TOOLS="$ROOT_DIR/.build/distribution/artifacts/sparkle/Sparkle/bin"
    "$SPARKLE_TOOLS/generate_appcast" --account me.jacopobassan.peekforcodex \
        --download-url-prefix "https://github.com/JacopoBassan/Peek-for-Codex/releases/download/$RELEASE_TAG/" \
        --link "https://github.com/JacopoBassan/Peek-for-Codex" \
        --maximum-deltas 0 "$WORK_DIR/updates"
    "$SPARKLE_TOOLS/sign_update" --account me.jacopobassan.peekforcodex \
        --verify "$WORK_DIR/updates/appcast.xml"
    xcrun swift "$ROOT_DIR/Support/VerifyUpdateSignatures.swift" "$APP_DIR" \
        "$WORK_DIR/updates/appcast.xml" "$WORK_DIR/$ARTIFACT_NAME" \
        "https://github.com/JacopoBassan/Peek-for-Codex/releases/download/$RELEASE_TAG/$ARTIFACT_NAME"
fi
# Retain the previous verified outputs until the new image passes every check.
rm -rf "$OUTPUT_DIR/Peek for Codex.app"
mv "$APP_DIR" "$OUTPUT_DIR/Peek for Codex.app"
mv "$WORK_DIR/$ARTIFACT_NAME" "$OUTPUT_DIR/$ARTIFACT_NAME"
mv "$WORK_DIR/$ARTIFACT_NAME.sha256" "$OUTPUT_DIR/$ARTIFACT_NAME.sha256"
if [[ "$MODE" == release ]]; then
    mv "$WORK_DIR/notarization-result.plist" "$OUTPUT_DIR/notarization-result.plist"
    mv "$WORK_DIR/updates/appcast.xml" "$OUTPUT_DIR/appcast.xml"
fi

echo "Created $OUTPUT_DIR/$ARTIFACT_NAME"
if [[ "$MODE" == preview ]]; then
    echo "LOCAL PREVIEW: not notarized, not ready for public distribution."
else
    echo "Signed, notarized, and verified. Nothing has been published."
fi
