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

has_python3=false
has_perl=false
if command -v python3 >/dev/null 2>&1; then
  has_python3=true
fi
if command -v perl >/dev/null 2>&1; then
  has_perl=true
fi
if [[ "$has_python3" == false && "$has_perl" == false ]]; then
  echo "agentbar-codex-hook: python3 or perl is required to encode JSON payloads" >&2
  exit 0
fi

# Build JSON safely with a real serializer
if [[ "$has_python3" == true ]]; then
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
elif [[ "$has_perl" == true ]]; then
  normalized_json="$(perl -MJSON::PP=encode_json -e '
use strict;
use warnings;
my ($event, $session_id, $message, $timestamp) = @ARGV;
print encode_json({
  agent => "codex",
  event => $event,
  session_id => $session_id,
  message => $message,
  timestamp => $timestamp
});
' "$event_type" "$session_id" "$message" "$timestamp" 2>/dev/null)" || exit 0
else
  echo "agentbar-codex-hook: python3 or perl is required to encode JSON payloads" >&2
  exit 0
fi

if [[ -S "$SOCKET_PATH" ]]; then
  printf '%s\n' "$normalized_json" | nc -U "$SOCKET_PATH" 2>/dev/null && exit 0
fi

# Socket not available; silently exit (Codex fallback watcher handles this case)
exit 0
