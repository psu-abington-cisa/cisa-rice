#!/usr/bin/env python3
"""Render a CISA Rice theme: every config file plus the artwork.

    python3 lib/render.py <theme-id> [--home DIR] [--size 3840x2160]

Writes into the home directory:
  ~/.config/{hypr,waybar,fuzzel,wlogout,swaync,kitty,btop,cava,fastfetch}/..., ~/.config/starship.toml
  ~/.local/share/cisa-rice/current/   wallpaper.png lock.png icon.png wlogout/*.svg theme.env
  ~/.local/share/color-schemes/CISA<id>.colors      (KDE colours: Plasma, and Qt apps under Hyprland)
  ~/.local/share/konsole/CISA-<id>.colorscheme
"""
import argparse
import pathlib
import shlex
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import art      # noqa: E402
import configs  # noqa: E402


def render_png(svg, out, w, h):
    tmp = out.with_suffix(".svg")
    tmp.write_text(svg)
    subprocess.run(["rsvg-convert", "-w", str(w), "-h", str(h), str(tmp), "-o", str(out)], check=True)
    tmp.unlink()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("theme")
    ap.add_argument("--home", default=str(pathlib.Path.home()))
    ap.add_argument("--size", default="3840x2160")
    a = ap.parse_args()

    home = pathlib.Path(a.home)
    cfg_home, data_home = home / ".config", home / ".local/share"
    cur = data_home / "cisa-rice/current"
    if cur.is_file():          # CISA Rice 1.x stored the theme name in a file at this path
        cur.unlink()
    (cur / "wlogout").mkdir(parents=True, exist_ok=True)
    w, h = (int(x) for x in a.size.split("x"))
    t = art.load_theme(a.theme)

    # artwork (vector, rendered at full resolution so nothing is blurry)
    render_png(art.wallpaper_svg(t), cur / "wallpaper.png", w, h)
    render_png(art.lock_svg(t), cur / "lock.png", w, h)
    render_png(art.icon_svg(t), cur / "icon.png", 512, 512)
    for name, svg in configs.wlogout_icons(t).items():
        (cur / "wlogout" / f"{name}.svg").write_text(svg)

    # app configs
    written = []
    for gen in configs.ALL:
        for rel, content in gen(t, str(cur)).items():
            p = cfg_home / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(content)
            written.append(str(p))
    user_conf = cfg_home / "hypr/user.conf"
    if not user_conf.exists():
        user_conf.write_text("# Your own Hyprland settings. CISA Rice never overwrites this file.\n")

    # KDE colour scheme + Konsole colours
    scheme_id = "CISA" + t["ID"].replace("-", "")
    (data_home / "color-schemes").mkdir(parents=True, exist_ok=True)
    (data_home / "color-schemes" / f"{scheme_id}.colors").write_text(configs.kde_colors(t, scheme_id))
    (data_home / "konsole").mkdir(parents=True, exist_ok=True)
    (data_home / "konsole" / f"CISA-{t['ID']}.colorscheme").write_text(configs.konsole(t))

    # theme.env: for rice.sh and the cisa-* helper scripts
    env = {k: v for k, v in t.items() if isinstance(v, (str, int))}
    env["SCHEME_ID"] = scheme_id
    (cur / "theme.env").write_text("".join(f"{k}={shlex.quote(str(v))}\n" for k, v in sorted(env.items())))
    print(f"rendered {t['NAME']}: {len(written)} config files, artwork in {cur}")


if __name__ == "__main__":
    main()
