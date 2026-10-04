#!/usr/bin/env bash
# Copy VM test shots (from dev/vm-test.sh) into screenshots/ for the README.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p screenshots
for t in themes/*.theme; do
  id=$(basename "$t" .theme)
  convert "dev/vm-shots/theme-$id.png" -resize 960x -quality 85 "screenshots/$id.jpg"
  echo "screenshots/$id.jpg"
done
