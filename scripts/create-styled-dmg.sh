#!/usr/bin/env bash
set -euo pipefail

# Create a styled DMG installer for AgentBar.
#
# Usage:
#   ./scripts/create-styled-dmg.sh <app-path> <dmg-output-path>
#
# Example:
#   ./scripts/create-styled-dmg.sh build/Build/Products/Debug/AgentBar.app AgentBar.dmg

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKGROUND="$ROOT_DIR/docs/assets/dmg-background@2x.png"

# Prefer build/icons/AgentBar.icns, fall back to app bundle icon
VOLUME_ICON="$ROOT_DIR/build/icons/AgentBar.icns"
if [[ ! -f "$VOLUME_ICON" ]]; then
  VOLUME_ICON=""
fi

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <app-path> <dmg-output-path>" >&2
  exit 1
fi

APP_PATH="$1"
DMG_PATH="$2"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH" >&2
  exit 1
fi

if ! command -v create-dmg &>/dev/null; then
  echo "create-dmg not found. Install with: brew install create-dmg" >&2
  exit 1
fi

if [[ ! -f "$BACKGROUND" ]]; then
  echo "Background image not found: $BACKGROUND" >&2
  echo "Generate it with: python3 scripts/generate-dmg-background.py" >&2
  exit 1
fi

# Remove existing DMG (create-dmg won't overwrite)
rm -f "$DMG_PATH"

# Build create-dmg args
ARGS=(
  --volname "AgentBar"
  --background "$BACKGROUND"
  --window-pos 200 120
  --window-size 600 400
  --icon-size 128
  --icon "AgentBar.app" 150 200
  --app-drop-link 450 200
  --hide-extension "AgentBar.app"
  --no-internet-enable
)

if [[ -n "$VOLUME_ICON" ]]; then
  ARGS+=(--volicon "$VOLUME_ICON")
fi

create-dmg "${ARGS[@]}" "$DMG_PATH" "$APP_PATH"

echo "Styled DMG created: $DMG_PATH"
