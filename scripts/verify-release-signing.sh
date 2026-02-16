#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/AgentBar.xcodeproj"
SCHEME="AgentBar"
TEAM_ID="${DEVELOPMENT_TEAM:-}"
SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:-Developer ID Application}"
ARCHIVE_PATH="$ROOT_DIR/build/AgentBar.xcarchive"
REQUIRE_NOTARIZED=0

usage() {
  cat <<'EOF'
Usage: verify-release-signing.sh [--require-notarized] [archive-path]

Options:
  --require-notarized   Fail if Gatekeeper assessment indicates the app is not notarized.

Environment:
  DEVELOPMENT_TEAM      Apple Developer Team ID (required for archive signing).
  CODE_SIGN_IDENTITY    Signing identity (default: Developer ID Application).
EOF
}

parse_args() {
  local archive_path_set=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --require-notarized)
        REQUIRE_NOTARIZED=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        if [[ $archive_path_set -eq 1 ]]; then
          echo "Unexpected argument: $1" >&2
          usage >&2
          exit 1
        fi
        ARCHIVE_PATH="$1"
        archive_path_set=1
        ;;
    esac
    shift
  done
}

is_pre_notarization_rejection() {
  local spctl_output="$1"
  local lowered_output
  lowered_output="$(printf '%s' "$spctl_output" | tr '[:upper:]' '[:lower:]')"

  [[ "$lowered_output" =~ source[[:space:]]*=[[:space:]]*unnotarized[[:space:]]+developer[[:space:]]+id ]] && return 0
  [[ "$lowered_output" =~ unnotarized[[:space:]]+developer[[:space:]]+id ]] && return 0
  [[ "$lowered_output" =~ not[[:space:]]+notarized ]] && return 0
  [[ "$lowered_output" =~ notarization[[:space:]]+(failed|required) ]] && return 0

  return 1
}

archive_release_app() {
  xcodebuild archive \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY"
}

require_team_id() {
  if [[ -n "${TEAM_ID//[[:space:]]/}" ]]; then
    return
  fi

  cat <<'EOF' >&2
DEVELOPMENT_TEAM is required for release signing.
Example:
  DEVELOPMENT_TEAM=YOUR_TEAM_ID ./scripts/verify-release-signing.sh
EOF
  exit 1
}

verify_codesign() {
  local app_path="$1"
  local signing_details

  codesign --verify --deep --strict --verbose=2 "$app_path"

  signing_details="$(codesign -dv --verbose=4 "$app_path" 2>&1)"
  if ! grep -q "Authority=Developer ID Application" <<< "$signing_details"; then
    echo "Expected Developer ID Application signing authority was not found." >&2
    echo "$signing_details" >&2
    return 1
  fi
}

verify_gatekeeper() {
  local app_path="$1"
  local spctl_output
  local spctl_status

  set +e
  spctl_output="$(spctl --assess --type execute --verbose=4 "$app_path" 2>&1)"
  spctl_status=$?
  set -e

  if [[ $spctl_status -eq 0 ]]; then
    echo "$spctl_output"
    return 0
  fi

  if [[ $REQUIRE_NOTARIZED -eq 1 ]]; then
    echo "$spctl_output" >&2
    return "$spctl_status"
  fi

  if is_pre_notarization_rejection "$spctl_output"; then
    echo "$spctl_output"
    echo "Gatekeeper check is expected to fail before notarization." >&2
    return 0
  fi

  echo "$spctl_output" >&2
  return "$spctl_status"
}

main() {
  local app_path

  parse_args "$@"
  require_team_id
  archive_release_app

  app_path="$ARCHIVE_PATH/Products/Applications/AgentBar.app"
  if [[ ! -d "$app_path" ]]; then
    echo "Archive succeeded but app bundle was not found at: $app_path" >&2
    exit 1
  fi

  verify_codesign "$app_path"
  verify_gatekeeper "$app_path"
  echo "Release signing verification passed for $app_path"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
