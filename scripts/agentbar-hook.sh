#!/bin/zsh
set -euo pipefail

# AgentBar hook adapter for Claude Code
# Usage: Configure as a Claude Code hook (Stop, SubagentStop, Notification)
# Reads hook JSON from stdin, normalizes to AgentBar event format,
# sends to Unix socket. Falls back to JSONL file if socket unavailable.

SOCKET_PATH="${AGENTBAR_SOCKET:-$HOME/.agentbar/events.sock}"
FALLBACK_LOG="${AGENTBAR_CLAUDE_HOOK_LOG:-$HOME/.claude/agentbar/hook-events.jsonl}"

payload="$(cat)"
if [[ -z "${payload//[[:space:]]/}" ]]; then
  exit 0
fi

# Extract fields from Claude hook JSON
hook_event_name="$(printf '%s' "$payload" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('hook_event_name',''))" 2>/dev/null || echo "")"
session_id="$(printf '%s' "$payload" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id',''))" 2>/dev/null || echo "")"
message="$(printf '%s' "$payload" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('message',''))" 2>/dev/null || echo "")"

# Map hook_event_name to normalized event type
event_type=""
case "$hook_event_name" in
  Stop)          event_type="stop" ;;
  SubagentStop)  event_type="subagent_stop" ;;
  Notification)
    # Detect permission vs decision vs task completion from message
    lower_message="$(printf '%s' "$message" | tr '[:upper:]' '[:lower:]')"
    if [[ "$lower_message" == *"permission"* ]] || [[ "$lower_message" == *"approve"* ]] || \
       [[ "$lower_message" == *"sandbox"* ]] || [[ "$lower_message" == *"elevated"* ]]; then
      event_type="permission"
    elif [[ "$lower_message" == *"?"* ]] || [[ "$lower_message" == *"waiting for"* ]] || \
         [[ "$lower_message" == *"choose"* ]] || [[ "$lower_message" == *"select"* ]]; then
      event_type="decision"
    elif [[ "$lower_message" == *"completed"* ]] || [[ "$lower_message" == *"finished"* ]] || \
         [[ "$lower_message" == *"all done"* ]] || [[ "$lower_message" == *"task complete"* ]]; then
      event_type="stop"
    else
      exit 0
    fi
    ;;
  *)
    exit 0
    ;;
esac

timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Build JSON safely; prefer python3 for proper escaping, fall back to printf
if command -v python3 >/dev/null 2>&1; then
  normalized_json="$(python3 -c "
import json, sys
print(json.dumps({
    'agent': 'claude',
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
  normalized_json="{\"agent\":\"claude\",\"event\":\"${safe_event}\",\"session_id\":\"${safe_sid}\",\"message\":\"${safe_msg}\",\"timestamp\":\"${safe_ts}\"}"
fi

# Try socket first
if [[ -S "$SOCKET_PATH" ]]; then
  printf '%s\n' "$normalized_json" | nc -U "$SOCKET_PATH" 2>/dev/null && exit 0
fi

# Fallback: append to JSONL file (legacy bridge format)
output_dir="${FALLBACK_LOG:h}"
mkdir -p "$output_dir"

captured_at="$timestamp"
payload_base64="$(printf '%s' "$payload" | base64 | tr -d '\n')"

printf '{"captured_at":"%s","payload_base64":"%s"}\n' \
  "$captured_at" \
  "$payload_base64" >> "$FALLBACK_LOG"
