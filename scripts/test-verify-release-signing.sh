#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/verify-release-signing.sh
source "$ROOT_DIR/scripts/verify-release-signing.sh"

assert_matches_pre_notarized() {
  local sample="$1"
  local description="$2"

  if ! is_pre_notarization_rejection "$sample"; then
    echo "Assertion failed: expected pre-notarization match for $description" >&2
    exit 1
  fi
}

assert_does_not_match_pre_notarized() {
  local sample="$1"
  local description="$2"

  if is_pre_notarization_rejection "$sample"; then
    echo "Assertion failed: expected non-matching output for $description" >&2
    exit 1
  fi
}

assert_matches_pre_notarized $'CCUsageBar.app: rejected\nsource=Unnotarized Developer ID' "source=Unnotarized Developer ID"
assert_matches_pre_notarized "Unnotarized Developer ID" "plain unnotarized phrase"
assert_matches_pre_notarized "Gatekeeper blocked launch because the app is not notarized." "not notarized phrase"
assert_matches_pre_notarized "notarization required for this software" "notarization required phrase"

assert_does_not_match_pre_notarized $'CCUsageBar.app: rejected\nsource=no usable signature' "missing usable signature"
assert_does_not_match_pre_notarized "CSSMERR_TP_NOT_TRUSTED" "certificate trust failure"

echo "verify-release-signing parser tests passed."
