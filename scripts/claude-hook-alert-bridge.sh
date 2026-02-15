#!/bin/zsh
set -euo pipefail

# Override output path with AGENTBAR_CLAUDE_HOOK_LOG when needed.
output_path="${AGENTBAR_CLAUDE_HOOK_LOG:-$HOME/.claude/agentbar/hook-events.jsonl}"
output_dir="${output_path:h}"

mkdir -p "$output_dir"

payload="$(cat)"
if [[ -z "${payload//[[:space:]]/}" ]]; then
  exit 0
fi

captured_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
payload_base64="$(printf '%s' "$payload" | base64 | tr -d '\n')"

printf '{"captured_at":"%s","payload_base64":"%s"}\n' \
  "$captured_at" \
  "$payload_base64" >> "$output_path"
