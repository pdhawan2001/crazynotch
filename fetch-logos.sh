#!/bin/bash
# Downloads each vendor's own icon and reduces it to a white-on-transparent
# template the app can tint. These are third-party trademarks, so they are
# fetched on your machine rather than committed to this repository.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p Resources/logos && cd Resources/logos

fetch() { curl -sSL --max-time 15 -A "Mozilla/5.0" -o "$1" "$2" 2>/dev/null || true; }
fetch claude.png "https://claude.ai/apple-touch-icon.png"
fetch cursor.png "https://www.cursor.com/apple-touch-icon.png"
fetch kimi.png   "https://www.kimi.com/favicon.ico"

python3 - <<'PY'
from PIL import Image
import os
for src, dst in [("claude.png","claude-mark.png"),("cursor.png","cursor-mark.png"),("kimi.png","kimi-mark.png")]:
    if not os.path.exists(src):
        continue
    im = Image.open(src).convert("RGBA")
    out = Image.new("RGBA", im.size, (0,0,0,0))
    sp, op = im.load(), out.load()
    for y in range(im.height):
        for x in range(im.width):
            r,g,b,a = sp[x,y]
            if a > 20 and (r*299+g*587+b*114)//1000 > 170:
                op[x,y] = (255,255,255,a)
    box = out.getbbox()
    if box: out = out.crop(box)
    out.save(dst)
    print("wrote", dst, out.size)
PY
echo "Logos ready. Without them the app draws its own fallback marks."
