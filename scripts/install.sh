#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Peek for Codex.app"
SOURCE_APP="$ROOT_DIR/dist/$APP_NAME"
TARGET_DIR="${TARGET_DIR:-$HOME/Applications}"
TARGET_APP="$TARGET_DIR/$APP_NAME"

"$ROOT_DIR/scripts/build.sh"

mkdir -p "$TARGET_DIR"
rm -rf "$TARGET_APP"
ditto "$SOURCE_APP" "$TARGET_APP"

echo "Installed $TARGET_APP"
echo ""
echo "Launch with:"
echo "  open \"$TARGET_APP\""
echo ""
echo "If you find Peek for Codex useful, consider starring the repo on GitHub."
