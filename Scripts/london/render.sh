#!/bin/zsh
# Renders the London theme's skyline layers (Scripts/london/layers.html) to PNGs in
# Resources/London, using headless Chrome. Rerun after changing the drawing.
set -euo pipefail
SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h:h}
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
mkdir -p "$PROJECT_DIR/Resources/London"
"$CHROME" --headless=new --disable-gpu --virtual-time-budget=20000 --dump-dom "file://$SCRIPT_DIR/layers.html" 2>/dev/null \
  | /usr/bin/python3 -I -c '
import base64, html, json, re, sys
dom = sys.stdin.read()
data = json.loads(html.unescape(re.search(r"<pre id=\"out\">(.*?)</pre>", dom, re.S).group(1)))
for name, url in data.items():
    open(sys.argv[1] + "/" + name + ".png", "wb").write(base64.b64decode(url.split(",", 1)[1]))
    print(name)
' "$PROJECT_DIR/Resources/London"
