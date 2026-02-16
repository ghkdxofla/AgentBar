#!/bin/zsh
set -euo pipefail

# AgentBar hook adapter for OpenAI Codex
# Usage: Configure in ~/.codex/config.toml as notify command
# Example: notify = ["path/to/agentbar-codex-hook.sh"]
# Reads Codex event data from arguments/stdin and sends to AgentBar socket.

SOCKET_PATH="${AGENTBAR_SOCKET:-$HOME/.agentbar/events.sock}"

# Codex notify passes event type as first argument
event_arg="${1:-}"

event_type=""
message=""
case "$event_arg" in
  task_complete|completed|done)
    event_type="stop"
    message="Codex task completed."
    ;;
  permission|escalation|require_escalated)
    event_type="permission"
    message="Codex requested elevated permissions."
    ;;
  decision|input|prompt)
    event_type="decision"
    message="Codex is waiting for your input."
    ;;
  *)
    # Try reading from stdin if no recognized argument
    stdin_payload="$(cat 2>/dev/null || true)"
    if [[ -n "${stdin_payload//[[:space:]]/}" ]]; then
      event_type="stop"
      message="$stdin_payload"
    else
      exit 0
    fi
    ;;
esac

timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
session_id="${CODEX_SESSION_ID:-}"

# Build JSON safely; prefer python3 for proper escaping, fall back to printf
if command -v python3 >/dev/null 2>&1; then
  normalized_json="$(python3 -c "
import json, sys
print(json.dumps({
    'agent': 'codex',
    'event': sys.argv[1],
    'session_id': sys.argv[2],
    'message': sys.argv[3],
    'timestamp': sys.argv[4]
}))
" "$event_type" "$session_id" "$message" "$timestamp" 2>/dev/null)" || exit 0
else
  # Minimal fallback: strip quotes from values to prevent injection
  safe_event="${event_type//\"/}"
  safe_sid="${session_id//\"/}"
  safe_msg="${message//\"/}"
  safe_ts="${timestamp//\"/}"
  normalized_json="{\"agent\":\"codex\",\"event\":\"${safe_event}\",\"session_id\":\"${safe_sid}\",\"message\":\"${safe_msg}\",\"timestamp\":\"${safe_ts}\"}"
fi

if [[ -S "$SOCKET_PATH" ]]; then
  printf '%s\n' "$normalized_json" | nc -U "$SOCKET_PATH" 2>/dev/null && exit 0
fi

# Socket not available; silently exit (Codex fallback watcher handles this case)
exit 0
