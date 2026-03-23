#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Peek for Codex.app"
SOURCE_APP="$ROOT_DIR/dist/$APP_NAME"
TARGET_DIR="${TARGET_DIR:-$HOME/Applications}"
TARGET_APP="$TARGET_DIR/$APP_NAME"
LEGACY_TARGET_APP="$TARGET_DIR/CodexUsageBar.app"

"$ROOT_DIR/scripts/build.sh"

mkdir -p "$TARGET_DIR"
if [[ -d "$LEGACY_TARGET_APP" && "$LEGACY_TARGET_APP" != "$TARGET_APP" ]]; then
    rm -rf "$LEGACY_TARGET_APP"
fi
rm -rf "$TARGET_APP"
ditto "$SOURCE_APP" "$TARGET_APP"

echo "Installed $TARGET_APP"
echo ""
echo "Launch with:"
echo "  open \"$TARGET_APP\""
