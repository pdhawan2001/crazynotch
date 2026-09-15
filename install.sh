#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
HOOK="$(pwd)/hooks/notch-hook.sh"
SETTINGS="$HOME/.claude/settings.json"

chmod +x "$HOOK"
cp "$SETTINGS" "$SETTINGS.backup-$(date +%Y%m%d-%H%M%S)"

python3 - "$SETTINGS" "$HOOK" <<'PY'
import json, sys
settings_path, hook = sys.argv[1], sys.argv[2]
with open(settings_path) as f:
    settings = json.load(f)

def entry(timeout=None):
    h = {"type": "command", "command": hook}
    if timeout:
        h["timeout"] = timeout
    return h

wanted = {
    "SessionStart":     [{"hooks": [entry()]}],
    "UserPromptSubmit": [{"hooks": [entry()]}],
    "Stop":             [{"hooks": [entry()]}],
    "Notification":     [{"hooks": [entry()]}],
    "SessionEnd":       [{"hooks": [entry()]}],
    "PermissionRequest":[{"matcher": "*", "hooks": [entry(timeout=600)]}],
}

hooks = settings.setdefault("hooks", {})
for event, config in wanted.items():
    existing = [g for g in hooks.get(event, [])
                if not any(hook in x.get("command", "") for x in g.get("hooks", []))]
    hooks[event] = existing + config

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
print("hooks installed:", ", ".join(sorted(wanted)))
PY

python3 -c "import json;json.load(open('$SETTINGS'));print('settings.json is valid JSON')"
