#!/bin/bash
# Claude Code hands this script the only authoritative copy of the account's
# rate limits and the session's context window; it is forwarded to CrazyNotch
# and then passed through untouched to whatever status line was already set up.
input=$(cat)
printf '%s' "$input" > /tmp/crazynotch-last-statusline.json

printf '%s' "$input" | curl --silent --max-time 2 \
    --data-binary @- \
    --header 'Content-Type: application/json' \
    "http://127.0.0.1:8787/statusline" >/dev/null 2>&1 || true

DELEGATE_FILE="$(dirname "$0")/statusline-delegate"
if [ -s "$DELEGATE_FILE" ]; then
    printf '%s' "$input" | bash -c "$(cat "$DELEGATE_FILE")"
fi
