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

escaped_message="$(printf '%s' "$message" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || printf '"%s"' "$message")"

normalized_json="{\"agent\":\"codex\",\"event\":\"${event_type}\",\"session_id\":\"${session_id}\",\"message\":${escaped_message},\"timestamp\":\"${timestamp}\"}"

if [[ -S "$SOCKET_PATH" ]]; then
  printf '%s\n' "$normalized_json" | nc -U "$SOCKET_PATH" 2>/dev/null && exit 0
fi

# Socket not available; silently exit (Codex fallback watcher handles this case)
exit 0
