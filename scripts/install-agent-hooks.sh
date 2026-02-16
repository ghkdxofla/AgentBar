#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CODEX_CONFIG="${HOME}/.codex/config.toml"
CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
CLAUDE_HOOKS_CONFIG="${HOME}/.claude/hooks/config.json"
GEMINI_SETTINGS="${HOME}/.gemini/settings.json"
OPENCODE_PLUGIN="${HOME}/.config/opencode/plugins/agentbar-notify.js"

CODEX_HOOK_SCRIPT="${ROOT_DIR}/scripts/agentbar-codex-hook.sh"
CLAUDE_HOOK_SCRIPT="${ROOT_DIR}/scripts/agentbar-hook.sh"
GEMINI_HOOK_SCRIPT="${ROOT_DIR}/scripts/agentbar-gemini-hook.sh"
OPENCODE_HOOK_SCRIPT="${ROOT_DIR}/scripts/agentbar-opencode-hook.sh"

BACKUP_ROOT=""
BACKUP_INDEX_FILE="$(mktemp "${TMPDIR:-/tmp}/agentbar-hook-backups.XXXXXX")"
trap 'rm -f "$BACKUP_INDEX_FILE"' EXIT

MODIFIED_COUNT=0
MODIFIED_PATHS=()

ensure_backup_root() {
  if [[ -n "$BACKUP_ROOT" ]]; then
    return
  fi

  local timestamp
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  BACKUP_ROOT="${HOME}/.agentbar/backups/${timestamp}"
  mkdir -p "$BACKUP_ROOT"
}

backup_once() {
  local target="$1"
  if [[ ! -f "$target" ]]; then
    return
  fi

  if grep -Fxq "$target" "$BACKUP_INDEX_FILE"; then
    return
  fi

  ensure_backup_root

  local backup_target="${BACKUP_ROOT}/${target#/}"
  mkdir -p "$(dirname "$backup_target")"
  cp -p "$target" "$backup_target"
  printf '%s\n' "$target" >> "$BACKUP_INDEX_FILE"

  echo "Backed up: ${target} -> ${backup_target}"
}

write_if_changed() {
  local target="$1"
  local content="$2"

  local old_content=""
  if [[ -f "$target" ]]; then
    old_content="$(cat "$target")"
  fi

  if [[ "$old_content" == "$content" ]]; then
    return 0
  fi

  backup_once "$target"
  mkdir -p "$(dirname "$target")"
  printf '%s' "$content" > "$target"
  MODIFIED_COUNT=$((MODIFIED_COUNT + 1))
  MODIFIED_PATHS+=("$target")
  echo "Updated: ${target}"
}

install_codex_hook() {
  local rendered
  rendered="$(python3 - "$CODEX_CONFIG" "$CODEX_HOOK_SCRIPT" <<'PY'
import os
import re
import sys

path = sys.argv[1]
hook = sys.argv[2]
notify_line = f'notify = ["{hook}"]'

text = ""
if os.path.exists(path):
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()

# Always keep notify at top-level:
# 1) Remove existing notify assignments (possibly nested in tables),
# 2) Insert once before the first table header.
cleaned = re.sub(r"(?m)^\s*notify\s*=.*$(?:\n)?", "", text)
lines = cleaned.splitlines()
insert_index = len(lines)
for i, line in enumerate(lines):
    if line.strip().startswith("["):
        insert_index = i
        break

lines.insert(insert_index, notify_line)
new_text = "\n".join(lines).rstrip("\n") + "\n"

sys.stdout.write(new_text)
PY
)"

  write_if_changed "$CODEX_CONFIG" "$rendered"
}

render_claude_settings() {
  local target="$1"
  python3 - "$target" "$CLAUDE_HOOK_SCRIPT" <<'PY'
import json
import os
import sys

path = sys.argv[1]
hook = sys.argv[2]

if os.path.exists(path):
    raw = open(path, "r", encoding="utf-8").read().strip()
    data = json.loads(raw) if raw else {}
else:
    data = {}

if not isinstance(data, dict):
    data = {}

hooks = data.get("hooks")
if not isinstance(hooks, dict):
    hooks = {}

def has_hook_command(items):
    for item in items:
        if not isinstance(item, dict):
            continue
        nested = item.get("hooks")
        if not isinstance(nested, list):
            continue
        for hook_item in nested:
            if not isinstance(hook_item, dict):
                continue
            if hook_item.get("type") == "command" and hook_item.get("command") == hook:
                return True
    return False

for event_name in ["Notification", "Stop", "SubagentStop"]:
    event_hooks = hooks.get(event_name)
    if not isinstance(event_hooks, list):
        event_hooks = []

    if not has_hook_command(event_hooks):
        event_hooks.append({
            "description": "Forward events to AgentBar",
            "hooks": [
                {
                    "type": "command",
                    "command": hook,
                }
            ],
        })

    hooks[event_name] = event_hooks

data["hooks"] = hooks
sys.stdout.write(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
PY
}

install_claude_hook() {
  local rendered

  rendered="$(render_claude_settings "$CLAUDE_SETTINGS")"
  write_if_changed "$CLAUDE_SETTINGS" "$rendered"

  rendered="$(render_claude_settings "$CLAUDE_HOOKS_CONFIG")"
  write_if_changed "$CLAUDE_HOOKS_CONFIG" "$rendered"
}

install_gemini_hook() {
  local rendered
  rendered="$(python3 - "$GEMINI_SETTINGS" "$GEMINI_HOOK_SCRIPT" <<'PY'
import json
import os
import sys

path = sys.argv[1]
hook = sys.argv[2]

if os.path.exists(path):
    raw = open(path, "r", encoding="utf-8").read().strip()
    data = json.loads(raw) if raw else {}
else:
    data = {}

if not isinstance(data, dict):
    data = {}

hooks_config = data.get("hooksConfig")
if not isinstance(hooks_config, dict):
    hooks_config = {}
hooks_config["enabled"] = True
data["hooksConfig"] = hooks_config

hooks = data.get("hooks")
if not isinstance(hooks, dict):
    hooks = {}

def has_hook_command(items):
    for item in items:
        if not isinstance(item, dict):
            continue
        nested = item.get("hooks")
        if not isinstance(nested, list):
            continue
        for hook_item in nested:
            if not isinstance(hook_item, dict):
                continue
            if hook_item.get("type") == "command" and hook_item.get("command") == hook:
                return True
    return False

after_agent = hooks.get("AfterAgent")
if not isinstance(after_agent, list):
    after_agent = []
if not has_hook_command(after_agent):
    after_agent.append({
        "description": "Forward completion events to AgentBar",
        "hooks": [
            {
                "type": "command",
                "command": hook,
            }
        ],
    })
hooks["AfterAgent"] = after_agent

notification = hooks.get("Notification")
if not isinstance(notification, list):
    notification = []
if not has_hook_command(notification):
    notification.append({
        "description": "Forward permission notifications to AgentBar",
        "matcher": "ToolPermission",
        "hooks": [
            {
                "type": "command",
                "command": hook,
            }
        ],
    })
hooks["Notification"] = notification

data["hooks"] = hooks
sys.stdout.write(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
PY
)"

  write_if_changed "$GEMINI_SETTINGS" "$rendered"
}

render_opencode_plugin() {
  python3 - "$OPENCODE_HOOK_SCRIPT" <<'PY'
import json
import sys

hook_script = sys.argv[1]

hook_literal = json.dumps(hook_script)

content = f'''import {{ spawn }} from "node:child_process";

const HOOK_PATH = process.env.AGENTBAR_OPENCODE_HOOK || {hook_literal};
const FORWARDED_EVENT_TYPES = new Set([
  "session.idle",
  "session.completed",
  "permission.asked",
  "question.asked",
  "session.error",
]);

function forwardToAgentBar(eventPayload) {{
  return new Promise((resolve) => {{
    const child = spawn(HOOK_PATH, [], {{ stdio: ["pipe", "ignore", "ignore"] }});

    child.on("error", () => resolve());
    child.on("close", () => resolve());

    try {{
      child.stdin.write(JSON.stringify(eventPayload));
    }} catch (_error) {{
      // ignore serialization/pipe errors
    }} finally {{
      child.stdin.end();
    }}
  }});
}}

export const AgentBarNotifyPlugin = async () => {{
  return {{
    event: async (input) => {{
      const event = input?.event;
      if (!event || typeof event !== "object") {{
        return;
      }}

      if (!FORWARDED_EVENT_TYPES.has(event.type)) {{
        return;
      }}

      await forwardToAgentBar(event);
    }},
  }};
}};
'''

sys.stdout.write(content)
PY
}

install_opencode_hook() {
  local plugin_content
  plugin_content="$(render_opencode_plugin)"
  write_if_changed "$OPENCODE_PLUGIN" "$plugin_content"
}

ensure_scripts_executable() {
  chmod +x "$CODEX_HOOK_SCRIPT"
  chmod +x "$CLAUDE_HOOK_SCRIPT"
  chmod +x "$GEMINI_HOOK_SCRIPT"
  chmod +x "$OPENCODE_HOOK_SCRIPT"
}

main() {
  ensure_scripts_executable
  install_codex_hook
  install_claude_hook
  install_gemini_hook
  install_opencode_hook

  if [[ "$MODIFIED_COUNT" -eq 0 ]]; then
    echo "No changes needed. Hooks are already configured."
  else
    echo ""
    echo "Hook installation completed. Updated ${MODIFIED_COUNT} file(s):"
    for path in "${MODIFIED_PATHS[@]}"; do
      echo "- ${path}"
    done
  fi

  if [[ -n "$BACKUP_ROOT" ]]; then
    echo ""
    echo "Backups saved under: ${BACKUP_ROOT}"
  fi
}

main "$@"
