#!/bin/bash
# One-command install: build, place the app, wire the Claude Code hooks and the
# status line, and register it to start at login. Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")"

ROOT="$(pwd)"
APP="/Applications/CrazyNotch.app"
LABEL="app.crazynotch.local"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SETTINGS="$HOME/.claude/settings.json"

step() { printf '\033[1m==>\033[0m %s\n' "$1"; }
fail() { printf '\033[31mx\033[0m %s\n' "$1" >&2; exit 1; }

command -v swift >/dev/null || fail "Swift not found. Install Xcode or the Command Line Tools: xcode-select --install"
[ -f "$SETTINGS" ] || { mkdir -p "$HOME/.claude"; echo '{}' > "$SETTINGS"; }

step "Building"
./build.sh release >/dev/null

step "Installing to /Applications"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
pkill -f "CrazyNotch.app/Contents/MacOS" 2>/dev/null || true
sleep 1
rm -rf "$APP"
cp -R build/CrazyNotch.app "$APP"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

step "Wiring Claude Code hooks and status line"
python3 - "$SETTINGS" "$ROOT" <<'PY'
import json, shutil, sys, time
from pathlib import Path

settings_path, root = Path(sys.argv[1]), Path(sys.argv[2])
shutil.copy(settings_path, settings_path.with_name(
    f"settings.json.backup-{time.strftime('%Y%m%d-%H%M%S')}"))

settings = json.loads(settings_path.read_text() or "{}")
hook = str(root / "hooks" / "notch-hook.sh")
statusline = str(root / "hooks" / "notch-statusline.sh")

def entry(timeout=None):
    h = {"type": "command", "command": hook}
    if timeout:
        h["timeout"] = timeout
    return h

wanted = {
    "SessionStart":      [{"hooks": [entry()]}],
    "UserPromptSubmit":  [{"hooks": [entry()]}],
    "Stop":              [{"hooks": [entry()]}],
    "Notification":      [{"hooks": [entry()]}],
    "SessionEnd":        [{"hooks": [entry()]}],
    "PermissionRequest": [{"matcher": "*", "hooks": [entry(timeout=30)]}],
}

hooks = settings.setdefault("hooks", {})
for event, config in wanted.items():
    kept = [g for g in hooks.get(event, [])
            if not any(hook in x.get("command", "") for x in g.get("hooks", []))]
    hooks[event] = kept + config

# Preserve whatever status line was already configured; the wrapper delegates to it.
current = (settings.get("statusLine") or {}).get("command", "")
delegate = root / "hooks" / "statusline-delegate"
if current and statusline not in current:
    delegate.write_text(current)
elif not delegate.exists():
    delegate.write_text("")
settings["statusLine"] = {"type": "command", "command": f'bash "{statusline}"'}

settings_path.write_text(json.dumps(settings, indent=2) + "\n")
json.loads(settings_path.read_text())
print("   hooks + status line wired (settings backed up)")
PY

chmod +x hooks/notch-hook.sh hooks/notch-statusline.sh

step "Registering login item"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key><array><string>$APP/Contents/MacOS/CrazyNotch</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
    <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
PLIST
plutil -lint "$PLIST" >/dev/null
launchctl bootstrap "gui/$(id -u)" "$PLIST"

sleep 3
if curl -sf --max-time 5 http://127.0.0.1:8787/health >/dev/null; then
    printf '\n\033[32mDone.\033[0m CrazyNotch is running and starts at login.\n'
    echo "Start a NEW Claude Code session — hooks load at session start."
else
    fail "Installed, but the app is not responding on 127.0.0.1:8787"
fi
