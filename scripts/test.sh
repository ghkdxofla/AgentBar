#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/build}"
PARALLEL_TESTING_ENABLED="${PARALLEL_TESTING_ENABLED:-NO}"
PARALLEL_TESTING_WORKERS="${PARALLEL_TESTING_WORKERS:-1}"
DESTINATION="${DESTINATION:-platform=macOS,arch=$(uname -m)}"

xcodebuild test \
  -project "$ROOT_DIR/AgentBar.xcodeproj" \
  -scheme AgentBar \
  -configuration Debug \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -parallel-testing-enabled "$PARALLEL_TESTING_ENABLED" \
  -parallel-testing-worker-count "$PARALLEL_TESTING_WORKERS" \
  -quiet
