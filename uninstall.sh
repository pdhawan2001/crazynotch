#!/bin/bash
# Removes the app, the login item, and this tool's hooks. Your own settings and
# any status line you had before are left as they were.
set -euo pipefail
LABEL="app.crazynotch.local"
SETTINGS="$HOME/.claude/settings.json"
ROOT="$(cd "$(dirname "$0")" && pwd)"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
pkill -f "CrazyNotch.app/Contents/MacOS" 2>/dev/null || true
rm -rf /Applications/CrazyNotch.app

python3 - "$SETTINGS" "$ROOT" <<'PY'
import json, sys
from pathlib import Path
settings_path, root = Path(sys.argv[1]), Path(sys.argv[2])
if not settings_path.exists():
    raise SystemExit
settings = json.loads(settings_path.read_text() or "{}")

for event, groups in list(settings.get("hooks", {}).items()):
    kept = [g for g in groups
            if not any(str(root) in x.get("command", "") for x in g.get("hooks", []))]
    if kept: settings["hooks"][event] = kept
    else: settings["hooks"].pop(event, None)
if not settings.get("hooks"): settings.pop("hooks", None)

delegate = root / "hooks" / "statusline-delegate"
previous = delegate.read_text().strip() if delegate.exists() else ""
if str(root) in (settings.get("statusLine") or {}).get("command", ""):
    if previous: settings["statusLine"] = {"type": "command", "command": previous}
    else: settings.pop("statusLine", None)

settings_path.write_text(json.dumps(settings, indent=2) + "\n")
print("hooks removed; previous status line restored" if previous else "hooks removed")
PY
echo "Uninstalled."
