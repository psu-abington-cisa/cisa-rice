#!/usr/bin/env bash
# Render every theme's wallpaper, lock background and icon to dev/previews/ (no KDE/Hyprland needed).
set -euo pipefail
cd "$(dirname "$0")/.."
command -v rsvg-convert >/dev/null || apt-get install -y librsvg2-bin >/dev/null
mkdir -p dev/previews
python3 - <<'PY'
import pathlib, subprocess, sys
sys.path.insert(0, "lib")
import art
out = pathlib.Path("dev/previews")
for f in sorted(pathlib.Path("themes").glob("*.theme")):
    t = art.load_theme(f.stem)
    for kind, svg, w, h in (("wall", art.wallpaper_svg(t), 1280, 720), ("lock", art.lock_svg(t), 640, 360),
                            ("icon", art.icon_svg(t), 128, 128)):
        p = out / f"{f.stem}-{kind}.svg"
        p.write_text(svg)
        subprocess.run(["rsvg-convert", "-w", str(w), "-h", str(h), str(p), "-o", str(p.with_suffix(".png"))], check=True)
        p.unlink()
    print("rendered", f.stem)
PY
