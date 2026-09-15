#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/CrazyNotch"
APP="build/CrazyNotch.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CrazyNotch"
cp Resources/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources/logos"
cp Resources/logos/*-mark.png "$APP/Contents/Resources/logos/" 2>/dev/null || true

codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"
