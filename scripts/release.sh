#!/usr/bin/env bash
set -euo pipefail

# AgentBar release pipeline: archive → sign → notarize → staple → DMG
#
# Prerequisites:
#   xcrun notarytool store-credentials "AgentBar" \
#     --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
#
# Usage:
#   ./scripts/release.sh              # full pipeline
#   ./scripts/release.sh --skip-tests # skip xcodebuild test
#   DEVELOPMENT_TEAM=YOUR_TEAM_ID ./scripts/release.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/AgentBar.xcodeproj"
SCHEME="AgentBar"
TEAM_ID="${DEVELOPMENT_TEAM:-}"
SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:-Developer ID Application}"
ARCHIVE_PATH="$ROOT_DIR/build/AgentBar.xcarchive"
DMG_PATH="$ROOT_DIR/AgentBar.dmg"
NOTARY_PROFILE="AgentBar"
SKIP_TESTS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-tests) SKIP_TESTS=1 ;;
    -h|--help)
      echo "Usage: release.sh [--skip-tests]"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

step() { echo ""; echo "==> $1"; }

if [[ -z "${TEAM_ID//[[:space:]]/}" ]]; then
  echo "DEVELOPMENT_TEAM is required for release signing." >&2
  echo "Example: DEVELOPMENT_TEAM=YOUR_TEAM_ID ./scripts/release.sh" >&2
  exit 1
fi

# 1. Test
if [[ $SKIP_TESTS -eq 0 ]]; then
  step "Running tests"
  xcodebuild test \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -destination 'platform=macOS' \
    -quiet
  echo "All tests passed."
fi

# 2. Archive with Developer ID signing
step "Archiving release build"
xcodebuild archive \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  -quiet

APP_PATH="$ARCHIVE_PATH/Products/Applications/AgentBar.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Archive succeeded but app not found at: $APP_PATH" >&2
  exit 1
fi
echo "Archive: $ARCHIVE_PATH"

# 3. Verify codesign
step "Verifying code signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "Code signature valid."

# 4. Notarize
step "Submitting for notarization"
ZIP_PATH="$ROOT_DIR/build/AgentBar-notarize.zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

xcrun notarytool submit "$ZIP_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

rm -f "$ZIP_PATH"
echo "Notarization complete."

# 5. Staple
step "Stapling notarization ticket"
xcrun stapler staple "$APP_PATH"
echo "Ticket stapled."

# 6. Verify Gatekeeper (post-notarization)
step "Verifying Gatekeeper assessment"
spctl --assess --type execute --verbose=4 "$APP_PATH" 2>&1 || true

# 7. Create DMG
step "Creating DMG"
hdiutil create \
  -volname AgentBar \
  -srcfolder "$APP_PATH" \
  -ov -format UDZO \
  "$DMG_PATH"

# 8. Notarize the DMG too
step "Notarizing DMG"
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

xcrun stapler staple "$DMG_PATH"
echo "DMG notarized and stapled."

step "Done"
echo "Release artifact: $DMG_PATH"
echo ""
echo "To publish:"
echo "  git tag vX.Y && git push upstream main --tags"
echo "  gh release create vX.Y $DMG_PATH --title 'AgentBar vX.Y' --notes '...'"
