#!/bin/zsh
set -euo pipefail

# AgentBar hook adapter for Gemini CLI
# Expected hook payload: JSON on stdin (similar to Claude hook schema).
# Normalizes to AgentBar socket format.

SOCKET_PATH="${AGENTBAR_SOCKET:-$HOME/.agentbar/events.sock}"

payload="$(cat 2>/dev/null || true)"
event_arg="${1:-}"
session_arg="${2:-}"
message_arg="${3:-}"

if [[ -z "${payload//[[:space:]]/}" && -z "${event_arg//[[:space:]]/}" ]]; then
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
  echo "agentbar-gemini-hook: python3 or perl is required" >&2
  exit 0
fi

extract_field() {
  local field="$1"
  if [[ "$has_python3" == true ]]; then
    printf '%s' "$payload" | python3 -c "import sys,json
try:
    d=json.load(sys.stdin)
except Exception:
    print('')
    raise SystemExit(0)
v=d.get(sys.argv[1], '')
print(v if isinstance(v, str) else '')" "$field" 2>/dev/null
  else
    printf '%s' "$payload" | perl -MJSON::PP=decode_json -e '
use strict;
use warnings;
local $/;
my $json = <STDIN>;
my $field = shift @ARGV;
my $data = eval { decode_json($json) };
if (!$data || ref($data) ne "HASH") { print ""; exit 0; }
my $value = $data->{$field};
if (!defined $value || ref($value)) { print ""; exit 0; }
print $value;
' "$field" 2>/dev/null
  fi
}

hook_event_name="${event_arg}"
session_id="${session_arg}"
message="${message_arg}"
notification_type=""

if [[ -n "${payload//[[:space:]]/}" ]]; then
  extracted_event="$(extract_field "hook_event_name" || true)"
  extracted_alt_event="$(extract_field "event" || true)"
  extracted_session="$(extract_field "session_id" || true)"
  extracted_message="$(extract_field "message" || true)"
  extracted_prompt_response="$(extract_field "prompt_response" || true)"
  extracted_notification_type="$(extract_field "notification_type" || true)"

  if [[ -n "${extracted_event}" ]]; then
    hook_event_name="$extracted_event"
  elif [[ -n "${extracted_alt_event}" ]]; then
    hook_event_name="$extracted_alt_event"
  fi

  if [[ -n "${extracted_session}" ]]; then
    session_id="$extracted_session"
  fi

  if [[ -n "${extracted_message}" ]]; then
    message="$extracted_message"
  elif [[ -n "${extracted_prompt_response}" ]]; then
    message="$extracted_prompt_response"
  fi

  if [[ -n "${extracted_notification_type}" ]]; then
    notification_type="$extracted_notification_type"
  fi
fi

lower_event="$(printf '%s' "$hook_event_name" | tr '[:upper:]' '[:lower:]')"
lower_message="$(printf '%s' "$message" | tr '[:upper:]' '[:lower:]')"
lower_notification_type="$(printf '%s' "$notification_type" | tr '[:upper:]' '[:lower:]')"

event_type=""
case "$lower_event" in
  stop|subagentstop|subagent_stop|task_complete|completed|done|afteragent|sessionend)
    event_type="stop"
    ;;
  permission|approval|permission_required)
    event_type="permission"
    ;;
  decision|input|required_input)
    event_type="decision"
    ;;
  notification)
    if [[ "$lower_notification_type" == *"toolpermission"* ]] || \
       [[ "$lower_message" == *"permission"* ]] || [[ "$lower_message" == *"approve"* ]] || \
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

if [[ "$has_python3" == true ]]; then
  normalized_json="$(python3 -c "
import json, sys
print(json.dumps({
    'agent': 'gemini',
    'event': sys.argv[1],
    'session_id': sys.argv[2],
    'message': sys.argv[3],
    'timestamp': sys.argv[4]
}))
" "$event_type" "$session_id" "$message" "$timestamp" 2>/dev/null)" || exit 0
else
  normalized_json="$(perl -MJSON::PP=encode_json -e '
use strict;
use warnings;
my ($event, $session_id, $message, $timestamp) = @ARGV;
print encode_json({
  agent => "gemini",
  event => $event,
  session_id => $session_id,
  message => $message,
  timestamp => $timestamp
});
' "$event_type" "$session_id" "$message" "$timestamp" 2>/dev/null)" || exit 0
fi

if [[ -S "$SOCKET_PATH" ]]; then
  printf '%s\n' "$normalized_json" | nc -U "$SOCKET_PATH" 2>/dev/null && exit 0
fi

exit 0
