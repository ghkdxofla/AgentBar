#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/AgentBar.xcodeproj"

get_build_setting() {
  local target="$1"
  local configuration="$2"
  local key="$3"

  xcodebuild \
    -project "$PROJECT_PATH" \
    -target "$target" \
    -configuration "$configuration" \
    -showBuildSettings \
    2>/dev/null | awk -F " = " -v lookup_key="$key" '
      $1 ~ "^[[:space:]]*" lookup_key "$" {
        gsub(/^[[:space:]]+/, "", $2)
        print $2
        found = 1
        exit
      }
      END {
        if (!found) {
          exit 1
        }
      }
    '
}

assert_equals() {
  local actual="$1"
  local expected="$2"
  local description="$3"

  if [[ "$actual" != "$expected" ]]; then
    echo "Assertion failed: $description (expected '$expected', got '$actual')" >&2
    exit 1
  fi
}

assert_contains() {
  local actual="$1"
  local expected_substring="$2"
  local description="$3"

  if [[ "$actual" != *"$expected_substring"* ]]; then
    echo "Assertion failed: $description (expected to include '$expected_substring', got '$actual')" >&2
    exit 1
  fi
}

app_debug_sign_style="$(get_build_setting "AgentBar" "Debug" "CODE_SIGN_STYLE")"
app_release_sign_style="$(get_build_setting "AgentBar" "Release" "CODE_SIGN_STYLE")"
app_release_identity="$(get_build_setting "AgentBar" "Release" "CODE_SIGN_IDENTITY")"
tests_debug_sign_style="$(get_build_setting "AgentBarTests" "Debug" "CODE_SIGN_STYLE")"
tests_release_sign_style="$(get_build_setting "AgentBarTests" "Release" "CODE_SIGN_STYLE")"

assert_equals "$app_debug_sign_style" "Automatic" "AgentBar Debug signing style"
assert_equals "$app_release_sign_style" "Manual" "AgentBar Release signing style"
assert_contains "$app_release_identity" "Developer ID Application" "AgentBar Release signing identity"
assert_equals "$tests_debug_sign_style" "Automatic" "AgentBarTests Debug signing style"
assert_equals "$tests_release_sign_style" "Automatic" "AgentBarTests Release signing style"

echo "Signing matrix verification passed."
