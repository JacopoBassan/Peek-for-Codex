#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="$(mktemp -d /tmp/peek-for-codex-icon.XXXXXX)"
# Cleanup is limited to this script's exact, newly created /tmp workspace.
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir "$WORK_DIR/compiled"
xcrun actool "$ROOT_DIR/PeekForCodex.icon" \
    --compile "$WORK_DIR/compiled" \
    --platform macosx --minimum-deployment-target 14.0 \
    --app-icon PeekForCodex \
    --output-partial-info-plist "$WORK_DIR/icon-info.plist"

cp "$WORK_DIR/compiled/PeekForCodex.icns" "$ROOT_DIR/Resources/PeekForCodex.icns"
cp "$WORK_DIR/compiled/Assets.car" "$ROOT_DIR/Resources/Assets.car"

echo "Generated macOS icon resources from PeekForCodex.icon"
