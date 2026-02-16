#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/verify-release-signing.sh
source "$ROOT_DIR/scripts/verify-release-signing.sh"

assert_equals() {
  local expected="$1"
  local actual="$2"
  local description="$3"

  if [[ "$actual" != "$expected" ]]; then
    echo "Assertion failed: $description (expected '$expected', got '$actual')" >&2
    exit 1
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local description="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    echo "Assertion failed: expected '$needle' in $description" >&2
    echo "Actual output:" >&2
    echo "$haystack" >&2
    exit 1
  fi
}

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

run_verify_gatekeeper() {
  local require_notarized="$1"
  local spctl_status="$2"
  local spctl_output="$3"
  local stdout_file
  local stderr_file

  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"

  set +e
  PATH="$SPCTL_STUB_DIR:$PATH" \
  SPCTL_STUB_STATUS="$spctl_status" \
  SPCTL_STUB_OUTPUT="$spctl_output" \
    /bin/bash -c "set -euo pipefail; source \"$ROOT_DIR/scripts/verify-release-signing.sh\"; REQUIRE_NOTARIZED=$require_notarized; verify_gatekeeper \"$ROOT_DIR/fake.app\"" \
    >"$stdout_file" 2>"$stderr_file"
  VERIFY_STATUS=$?
  set -e

  VERIFY_STDOUT="$(cat "$stdout_file")"
  VERIFY_STDERR="$(cat "$stderr_file")"
  rm -f "$stdout_file" "$stderr_file"
}

assert_matches_pre_notarized $'AgentBar.app: rejected\nsource=Unnotarized Developer ID' "source=Unnotarized Developer ID"
assert_matches_pre_notarized "Unnotarized Developer ID" "plain unnotarized phrase"
assert_matches_pre_notarized "Gatekeeper blocked launch because the app is not notarized." "not notarized phrase"
assert_matches_pre_notarized "notarization required for this software" "notarization required phrase"

assert_does_not_match_pre_notarized $'AgentBar.app: rejected\nsource=no usable signature' "missing usable signature"
assert_does_not_match_pre_notarized "CSSMERR_TP_NOT_TRUSTED" "certificate trust failure"

DEFAULT_ARCHIVE_PATH="$ARCHIVE_PATH"

ARCHIVE_PATH="$DEFAULT_ARCHIVE_PATH"
REQUIRE_NOTARIZED=0
parse_args
assert_equals "$DEFAULT_ARCHIVE_PATH" "$ARCHIVE_PATH" "default archive path should be preserved"
assert_equals "0" "$REQUIRE_NOTARIZED" "require-notarized should default to disabled"

ARCHIVE_PATH="$DEFAULT_ARCHIVE_PATH"
REQUIRE_NOTARIZED=0
parse_args --require-notarized "/tmp/custom.xcarchive"
assert_equals "/tmp/custom.xcarchive" "$ARCHIVE_PATH" "archive path argument should be parsed"
assert_equals "1" "$REQUIRE_NOTARIZED" "require-notarized flag should be enabled"

set +e
help_output="$(
  /bin/bash <<BASH 2>&1
set -euo pipefail
source "$ROOT_DIR/scripts/verify-release-signing.sh"
parse_args --help
BASH
)"
help_status=$?
set -e
assert_equals "0" "$help_status" "--help should exit successfully"
assert_contains "$help_output" "Usage: verify-release-signing.sh" "--help output"

set +e
invalid_output="$(
  /bin/bash <<BASH 2>&1
set -euo pipefail
source "$ROOT_DIR/scripts/verify-release-signing.sh"
parse_args first second
BASH
)"
invalid_status=$?
set -e
assert_equals "1" "$invalid_status" "multiple archive args should fail"
assert_contains "$invalid_output" "Unexpected argument: second" "invalid argument output"

set +e
missing_team_output="$(
  /bin/bash <<BASH 2>&1
set -euo pipefail
source "$ROOT_DIR/scripts/verify-release-signing.sh"
TEAM_ID=""
require_team_id
BASH
)"
missing_team_status=$?
set -e
assert_equals "1" "$missing_team_status" "require_team_id should fail when team is missing"
assert_contains "$missing_team_output" "DEVELOPMENT_TEAM is required" "missing team error output"

/bin/bash <<BASH >/dev/null 2>&1
set -euo pipefail
source "$ROOT_DIR/scripts/verify-release-signing.sh"
TEAM_ID="ABCDEFGHIJ"
require_team_id
BASH

SPCTL_STUB_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$SPCTL_STUB_DIR"
}
trap cleanup EXIT

cat >"$SPCTL_STUB_DIR/spctl" <<'BASH'
#!/usr/bin/env bash
printf '%s' "${SPCTL_STUB_OUTPUT:-}"
exit "${SPCTL_STUB_STATUS:-0}"
BASH
chmod +x "$SPCTL_STUB_DIR/spctl"

run_verify_gatekeeper 0 0 $'accepted\nsource=Notarized Developer ID'
assert_equals "0" "$VERIFY_STATUS" "successful Gatekeeper check should pass"
assert_contains "$VERIFY_STDOUT" "accepted" "successful Gatekeeper stdout"
assert_equals "" "$VERIFY_STDERR" "successful Gatekeeper should not print stderr"

run_verify_gatekeeper 0 1 $'AgentBar.app: rejected\nsource=Unnotarized Developer ID'
assert_equals "0" "$VERIFY_STATUS" "pre-notarization rejection should be tolerated by default"
assert_contains "$VERIFY_STDOUT" "source=Unnotarized Developer ID" "pre-notarization stdout"
assert_contains "$VERIFY_STDERR" "expected to fail before notarization" "pre-notarization stderr note"

run_verify_gatekeeper 0 1 $'AgentBar.app: rejected\nsource=no usable signature'
assert_equals "1" "$VERIFY_STATUS" "non-notarization Gatekeeper rejection should fail"
assert_contains "$VERIFY_STDERR" "source=no usable signature" "non-notarization failure stderr"

run_verify_gatekeeper 1 1 $'AgentBar.app: rejected\nsource=Unnotarized Developer ID'
assert_equals "1" "$VERIFY_STATUS" "require-notarized should fail on pre-notarization rejection"
assert_contains "$VERIFY_STDERR" "source=Unnotarized Developer ID" "require-notarized stderr"

set +e
/bin/bash <<BASH >/dev/null 2>&1
set -euo pipefail
source "$ROOT_DIR/scripts/verify-release-signing.sh"
is_pre_notarization_rejection "Unnotarized Developer ID"
BASH
bash_compat_status=$?
set -e
assert_equals "0" "$bash_compat_status" "/bin/bash compatibility check should pass"

echo "verify-release-signing parser and gatekeeper tests passed."
