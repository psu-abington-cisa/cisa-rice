#!/usr/bin/env bash
# CISA Rice installer. Run as your normal user:
#   curl -fsSL https://raw.githubusercontent.com/psu-abington-cisa/cisa-rice/main/install.sh | bash
# Extra options are passed through to rice.sh, e.g.  ... | bash -s -- --theme daylight
set -euo pipefail

REPO="${CISA_RICE_REPO:-https://github.com/psu-abington-cisa/cisa-rice.git}"
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/cisa-rice/app"

if [[ $EUID -eq 0 ]]; then
  echo "Run this as your normal user (without sudo)." >&2
  exit 1
fi

if ! command -v git >/dev/null; then
  echo "==> Installing git (you may be asked for your password)"
  sudo apt-get update -qq && sudo apt-get install -y -qq git
fi

if [[ -d $DEST/.git ]]; then
  echo "==> Updating CISA Rice"
  git -C "$DEST" pull --ff-only --quiet
else
  echo "==> Downloading CISA Rice"
  mkdir -p "$(dirname "$DEST")"
  git clone --depth 1 --quiet "$REPO" "$DEST"
fi

# stdin is the curl pipe, so hand the terminal back for questions/password prompts
exec bash "$DEST/rice.sh" "$@" </dev/tty
