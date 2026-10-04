#!/usr/bin/env bash
# Render every theme's wallpaper to dev/previews/ (for checking designs without a KDE session).
set -euo pipefail
cd "$(dirname "$0")/.."
command -v rsvg-convert >/dev/null || apt-get install -y librsvg2-bin >/dev/null
source lib/wallpaper.sh
mkdir -p dev/previews
for t in themes/*.theme; do
  ( source "$t"; id=$(basename "$t" .theme)
    make_wallpaper_svg "dev/previews/$id.svg" assets/cisa-logo.png
    rsvg-convert -w 1280 -h 720 "dev/previews/$id.svg" -o "dev/previews/$id.png"
    rm "dev/previews/$id.svg"; echo "rendered $id" )
done
