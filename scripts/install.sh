#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Peek for Codex.app"
SOURCE_APP="$ROOT_DIR/dist/$APP_NAME"
TARGET_DIR="${TARGET_DIR:-$HOME/Applications}"
TARGET_APP="$TARGET_DIR/$APP_NAME"
LEGACY_TARGET_APP="$TARGET_DIR/CodexUsageBar.app"
LAUNCH_AGENT_LABEL="me.jacopobassan.peekforcodex"
LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/$LAUNCH_AGENT_LABEL.plist"
APP_EXECUTABLE="$TARGET_APP/Contents/MacOS/PeekForCodex"

sync_launch_agent_if_needed() {
    [[ -f "$LAUNCH_AGENT_PLIST" ]] || return

    plutil -replace ProgramArguments -json "[\"$APP_EXECUTABLE\"]" "$LAUNCH_AGENT_PLIST"
}

"$ROOT_DIR/scripts/build.sh"

mkdir -p "$TARGET_DIR"
if [[ -d "$LEGACY_TARGET_APP" && "$LEGACY_TARGET_APP" != "$TARGET_APP" ]]; then
    rm -rf "$LEGACY_TARGET_APP"
fi
rm -rf "$TARGET_APP"
ditto "$SOURCE_APP" "$TARGET_APP"
sync_launch_agent_if_needed

echo "Installed $TARGET_APP"
echo ""
echo "Launch with:"
echo "  open \"$TARGET_APP\""
echo ""
echo "If you find Peek for Codex useful, consider starring the repo on GitHub."
