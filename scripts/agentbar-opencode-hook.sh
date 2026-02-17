#!/bin/zsh
set -euo pipefail

# AgentBar hook adapter for OpenCode events.
# Reads OpenCode event JSON from stdin and normalizes it to AgentBar socket format.

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
  echo "agentbar-opencode-hook: python3 or perl is required" >&2
  exit 0
fi

extract_field() {
  local field="$1"
  if [[ "$has_python3" == true ]]; then
    printf '%s' "$payload" | python3 -c "import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print('')
    raise SystemExit(0)

parts = sys.argv[1].split('.')
value = d
for part in parts:
    if isinstance(value, dict):
        value = value.get(part)
    else:
        value = None
        break

if isinstance(value, str):
    print(value)
elif value is None:
    print('')
else:
    print(str(value))" "$field" 2>/dev/null
  else
    printf '%s' "$payload" | perl -MJSON::PP=decode_json -e '
use strict;
use warnings;
local $/;
my $json = <STDIN>;
my $field = shift @ARGV;
my $data = eval { decode_json($json) };
if (!$data || ref($data) ne "HASH") { print ""; exit 0; }

my @parts = split /\./, $field;
my $value = $data;
for my $part (@parts) {
  if (ref($value) eq "HASH") {
    $value = $value->{$part};
  } else {
    $value = undef;
    last;
  }
}

if (!defined $value) { print ""; exit 0; }
if (ref($value)) { print ""; exit 0; }
print $value;
' "$field" 2>/dev/null
  fi
}

hook_event_name="$event_arg"
session_id="$session_arg"
message="$message_arg"

if [[ -n "${payload//[[:space:]]/}" ]]; then
  extracted_event="$(extract_field "type" || true)"
  extracted_session="$(extract_field "properties.sessionID" || true)"
  extracted_message="$(extract_field "properties.message" || true)"
  extracted_error_message="$(extract_field "properties.error.message" || true)"
  extracted_permission="$(extract_field "properties.permission" || true)"

  if [[ -n "$extracted_event" ]]; then
    hook_event_name="$extracted_event"
  fi

  if [[ -n "$extracted_session" ]]; then
    session_id="$extracted_session"
  fi

  if [[ -n "$extracted_message" ]]; then
    message="$extracted_message"
  elif [[ -n "$extracted_error_message" ]]; then
    message="$extracted_error_message"
  elif [[ -n "$extracted_permission" ]]; then
    message="Permission requested: $extracted_permission"
  fi
fi

lower_event="$(printf '%s' "$hook_event_name" | tr '[:upper:]' '[:lower:]')"
event_type=""

case "$lower_event" in
  session.idle|session.completed|stop|done|task_complete)
    event_type="stop"
    ;;
  permission.asked|permission|required_permission)
    event_type="decision"
    ;;
  question.asked|question|required_input|decision)
    event_type="decision"
    ;;
  session.error|error)
    event_type="decision"
    ;;
  *)
    exit 0
    ;;
esac

if [[ -z "${message//[[:space:]]/}" ]]; then
  case "$event_type" in
    stop)
      message="OpenCode task completed."
      ;;
    decision)
      message="OpenCode is waiting for your input."
      ;;
  esac
fi

timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

if [[ "$has_python3" == true ]]; then
  normalized_json="$(python3 -c "
import json, sys
print(json.dumps({
    'agent': 'opencode',
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
  agent => "opencode",
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
