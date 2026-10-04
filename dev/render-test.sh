#!/usr/bin/env bash
# Render every theme into a throwaway home and sanity-check the output (no desktop needed).
set -euo pipefail
cd "$(dirname "$0")/.."
H=/tmp/ricehome
rm -rf "$H"
for f in themes/*.theme; do
  python3 lib/render.py "$(basename "$f" .theme)" --home "$H" --size 1280x720
done
python3 - "$H" <<'PY'
import json, pathlib, sys
h = pathlib.Path(sys.argv[1]) / ".config"
json.loads((h / "waybar/config.jsonc").read_text().split("\n", 1)[1])
json.loads((h / "swaync/config.json").read_text())
for f in ("fastfetch/kitty.jsonc", "fastfetch/config.jsonc"):
    json.loads((h / f).read_text())
for line in (h / "wlogout/layout").read_text().splitlines():
    json.loads(line)
print("json files ok")
PY
if command -v starship >/dev/null; then STARSHIP_CONFIG=$H/.config/starship.toml starship print-config >/dev/null && echo "starship config ok"; fi
find "$H" -type f | sed "s|$H/||" | sort
