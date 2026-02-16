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

has_python3=false
has_perl=false
if command -v python3 >/dev/null 2>&1; then
  has_python3=true
fi
if command -v perl >/dev/null 2>&1; then
  has_perl=true
fi
if [[ "$has_python3" == false && "$has_perl" == false ]]; then
  echo "agentbar-hook: python3 or perl is required to parse JSON payloads" >&2
  exit 0
fi

# Parse helpers
extract_field_with_python3() {
  local field="$1"
  printf '%s' "$payload" | python3 -c "import sys,json; d=json.load(sys.stdin); v=d.get(sys.argv[1], ''); print(v if isinstance(v, str) else '')" "$field" 2>/dev/null
}

extract_field_with_perl() {
  local field="$1"
  printf '%s' "$payload" | perl -MJSON::PP=decode_json -e '
use strict;
use warnings;
local $/;
my $json = <STDIN>;
my $field = shift @ARGV;
my $data = eval { decode_json($json) };
if (!$data || ref($data) ne "HASH") { exit 1; }
my $value = $data->{$field};
if (!defined $value || ref($value)) { print ""; exit 0; }
print $value;
' "$field" 2>/dev/null
}

# Extract fields from Claude hook JSON
if [[ "$has_python3" == true ]]; then
  hook_event_name="$(extract_field_with_python3 "hook_event_name" || echo "")"
  session_id="$(extract_field_with_python3 "session_id" || echo "")"
  message="$(extract_field_with_python3 "message" || echo "")"
else
  hook_event_name="$(extract_field_with_perl "hook_event_name" || echo "")"
  session_id="$(extract_field_with_perl "session_id" || echo "")"
  message="$(extract_field_with_perl "message" || echo "")"
fi

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

# Build JSON safely with a real serializer
if [[ "$has_python3" == true ]]; then
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
elif [[ "$has_perl" == true ]]; then
  normalized_json="$(perl -MJSON::PP=encode_json -e '
use strict;
use warnings;
my ($event, $session_id, $message, $timestamp) = @ARGV;
print encode_json({
  agent => "claude",
  event => $event,
  session_id => $session_id,
  message => $message,
  timestamp => $timestamp
});
' "$event_type" "$session_id" "$message" "$timestamp" 2>/dev/null)" || exit 0
else
  echo "agentbar-hook: python3 or perl is required to encode JSON payloads" >&2
  exit 0
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
