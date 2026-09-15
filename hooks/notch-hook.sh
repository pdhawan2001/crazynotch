#!/bin/bash
# Forwards the hook payload to CrazyNotch and echoes back whatever it answers.
# Only PermissionRequest gets a non-empty reply; every other event answers with
# an empty body, because hook stdout is injected into Claude's context.
# Any failure stays silent and exits 0 so a dead app never breaks a session.
curl --silent --show-error --max-time 595 \
     --data-binary @- \
     --header 'Content-Type: application/json' \
     "http://127.0.0.1:8787/hook" 2>/dev/null || true
exit 0
