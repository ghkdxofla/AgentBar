#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/CCUsageBar.xcodeproj"
SCHEME="CCUsageBar"
ARCHIVE_PATH="${1:-$ROOT_DIR/build/CCUsageBar.xcarchive}"
TEAM_ID="${DEVELOPMENT_TEAM:-<TEAM_ID>}"
SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:-Developer ID Application}"

xcodebuild archive \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY"

APP_PATH="$ARCHIVE_PATH/Products/Applications/CCUsageBar.app"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Archive succeeded but app bundle was not found at: $APP_PATH" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

SIGNING_DETAILS="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1)"
if ! grep -q "Authority=Developer ID Application" <<< "$SIGNING_DETAILS"; then
  echo "Expected Developer ID Application signing authority was not found." >&2
  echo "$SIGNING_DETAILS" >&2
  exit 1
fi

set +e
SPCTL_OUTPUT="$(spctl --assess --type execute --verbose "$APP_PATH" 2>&1)"
SPCTL_STATUS=$?
set -e

if [[ $SPCTL_STATUS -eq 0 ]]; then
  echo "$SPCTL_OUTPUT"
elif grep -q "Unnotarized Developer ID" <<< "$SPCTL_OUTPUT"; then
  echo "$SPCTL_OUTPUT"
  echo "Gatekeeper check is expected to fail before notarization." >&2
else
  echo "$SPCTL_OUTPUT" >&2
  exit $SPCTL_STATUS
fi

echo "Release signing verification passed for $APP_PATH"
