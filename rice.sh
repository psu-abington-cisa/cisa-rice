#!/usr/bin/env bash
# CISA Rice: a riced Hyprland desktop + matching Plasma theme for CISA Linux (Debian 13).
#
#   ./rice.sh                       pick a theme in a window
#   ./rice.sh --theme glass         apply a theme directly
#   ./rice.sh --list                list themes
#   ./rice.sh --restore             undo everything (restores the backup taken on first run)
#
# Options: --layout win10|win11 (Plasma taskbar)  --no-terminal  --no-login-screen  --yes (no questions)
set -euo pipefail
trap 'printf "\e[1;31m✗ Something went wrong (rice.sh line %s: %s). Your backup is safe; run with --restore to undo.\e[0m\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE="$DATA/cisa-rice"
CUR="$STATE/current"
BACKUP="$STATE/backup"
VERSION="2.0"

c_info()  { printf '\e[1;34m==>\e[0m %s\n' "$*"; }
c_ok()    { printf '\e[1;32m ✓\e[0m %s\n' "$*"; }
c_warn()  { printf '\e[1;33m !\e[0m %s\n' "$*" >&2; }
die()     { printf '\e[1;31m✗ %s\e[0m\n' "$*" >&2; exit 1; }
have()    { command -v "$1" >/dev/null 2>&1; }
gui()     { [[ -n ${WAYLAND_DISPLAY:-}${DISPLAY:-} ]] && have kdialog; }
kw()      { kwriteconfig6 "$@"; }
qdb()     { if have qdbus6; then qdbus6 "$@"; else qdbus "$@"; fi; }
in_hypr() { [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; }
in_plasma() { [[ ${XDG_CURRENT_DESKTOP:-} == *KDE* ]]; }

theme_ids()   { for f in "$HERE"/themes/*.theme; do basename "$f" .theme; done; }
theme_field() { ( source "$HERE/themes/$1.theme"; eval "echo \"\$$2\"" ); }

# ---------- arguments --------------------------------------------------------
THEME_ID=""; LAYOUT=""; DO_TERMINAL=1; DO_LOGIN=1; ASSUME_YES=0; ACTION=apply
while [[ $# -gt 0 ]]; do
  case $1 in
    --theme)  THEME_ID=$2; shift ;;
    --layout) LAYOUT=$2; shift ;;
    --no-terminal) DO_TERMINAL=0 ;;
    --no-login-screen) DO_LOGIN=0 ;;
    --yes|-y) ASSUME_YES=1 ;;
    --list)   ACTION=list ;;
    --restore) ACTION=restore ;;
    --plasma-panel-only) ACTION=panel; LAYOUT=${2:-dock}; shift ;;
    --version) echo "cisa-rice $VERSION"; exit 0 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "Unknown option: $1 (see --help)" ;;
  esac
  shift
done

[[ $EUID -eq 0 ]] && die "Run this as your normal user, not with sudo. It asks for your password when needed."

if [[ $ACTION == list ]]; then
  for id in $(theme_ids); do printf '  %-12s %s\n' "$id" "$(theme_field "$id" DESC)"; done
  exit 0
fi

# ---------- backup / restore -------------------------------------------------
CONF_DIRS=(hypr waybar fuzzel wlogout swaync kitty btop cava fastfetch)
CONF_FILES=(starship.toml kdeglobals kwinrc plasmarc kcminputrc konsolerc kscreenlockerrc plasmashellrc
            plasma-org.kde.plasma.desktop-appletsrc kglobalshortcutsrc)

migrate_v1() {
  # CISA Rice 1.x kept the theme name in a *file* called "current" (2.x uses that path as a folder),
  # rendered into "generated/", and backed up loose files instead of home.tgz.
  if [[ -f $STATE/current ]]; then mv -f "$STATE/current" "$STATE/current-theme"; fi
  rm -rf "$STATE/generated"
}

take_backup() {
  [[ -e $BACKUP/.taken ]] && return 0          # keep the original pre-rice state, never overwrite it
  mkdir -p "$BACKUP"
  local items=() x
  for x in "${CONF_DIRS[@]}" "${CONF_FILES[@]}"; do [[ -e $CONF/$x ]] && items+=(".config/$x"); done
  [[ -f $HOME/.bashrc ]] && items+=(".bashrc")
  tar -C "$HOME" -czf "$BACKUP/home.tgz" "${items[@]}" 2>/dev/null || true
  printf '%s\n' "${items[@]}" > "$BACKUP/items"
  date > "$BACKUP/.taken"
  c_ok "Backed up your current settings to $BACKUP"
}

do_restore() {
  [[ -e $BACKUP/.taken ]] || die "No backup found. Nothing to restore."
  c_info "Restoring your original desktop settings"
  local x
  for x in "${CONF_DIRS[@]}"; do rm -rf "${CONF:?}/$x"; done
  rm -f "$CONF/starship.toml" "$CONF/plasma-workspace/env/cisa-rice.sh" "$CONF/autostart/cisa-plasma-panel.desktop"
  if [[ -f $BACKUP/home.tgz ]]; then
    tar -C "$HOME" -xzf "$BACKUP/home.tgz"
  else
    # backup made by CISA Rice 1.x: loose copies of Plasma config files and .bashrc
    for x in "$BACKUP"/*; do
      [[ -f $x ]] || continue
      if [[ $(basename "$x") == .bashrc ]]; then cp -a "$x" "$HOME/.bashrc"; else cp -a "$x" "$CONF/"; fi
    done
    [[ -f $BACKUP/.bashrc ]] && cp -a "$BACKUP/.bashrc" "$HOME/.bashrc"
  fi
  sed -i '/^# >>> cisa-rice >>>$/,/^# <<< cisa-rice <<<$/d' "$HOME/.bashrc" 2>/dev/null || true
  rm -f "$STATE/current-theme"
  if in_plasma; then
    systemctl --user restart plasma-plasmashell.service 2>/dev/null || true
    local scheme; scheme=$(kreadconfig6 --file kdeglobals --group General --key ColorScheme 2>/dev/null || true)
    [[ -n $scheme ]] && plasma-apply-colorscheme "$scheme" >/dev/null 2>&1 || true
  fi
  in_hypr && hyprctl reload >/dev/null 2>&1 || true
  c_ok "Restored. Log out and back in if anything still looks off."
  exit 0
}
[[ $ACTION == restore ]] && do_restore

# ---------- packages ---------------------------------------------------------
# Everything comes from Debian. Hyprland and its lock/idle tools are in the official
# trixie-backports archive (Debian-signed); backports only install when asked for by name.
PKGS=(waybar fuzzel kitty wlogout sway-notification-center swaybg grim slurp wl-clipboard cliphist
      brightnessctl playerctl pavucontrol-qt network-manager-gnome libnotify-bin xdg-user-dirs
      btop cava fastfetch cbonsai starship librsvg2-bin python3 kdialog
      python3-gi gir1.2-gtk-3.0 gir1.2-gtklayershell-0.1
      fonts-jetbrains-mono fonts-font-awesome papirus-icon-theme bibata-cursor-theme)
BPO_PKGS=(hyprland hyprlock hypridle hyprpicker hyprpolkitagent xdg-desktop-portal-hyprland)

missing_pkgs() {
  local p
  for p in "$@"; do dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'ok installed' || echo "$p"; done
}

install_deps() {
  local miss bmiss
  mapfile -t miss < <(missing_pkgs "${PKGS[@]}")
  mapfile -t bmiss < <(missing_pkgs "${BPO_PKGS[@]}")
  [[ ${#miss[@]} -eq 0 && ${#bmiss[@]} -eq 0 ]] && return 0
  c_info "Installing desktop packages (you may be asked for your password)"
  if [[ ${#bmiss[@]} -gt 0 ]] && ! grep -rqs 'trixie-backports' /etc/apt/sources.list /etc/apt/sources.list.d/; then
    printf 'Types: deb\nURIs: http://deb.debian.org/debian\nSuites: trixie-backports\nComponents: main contrib non-free non-free-firmware\nSigned-By: /usr/share/keyrings/debian-archive-keyring.gpg\n' \
      | sudo tee /etc/apt/sources.list.d/debian-backports.sources >/dev/null
    c_ok "Enabled Debian's official backports archive (only used for Hyprland)"
  fi
  sudo apt-get update -qq || c_warn "apt update had errors; trying anyway"
  [[ ${#miss[@]} -gt 0 ]] && { sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${miss[@]}" \
    || die "Couldn't install packages. Are you connected to the internet?"; }
  [[ ${#bmiss[@]} -gt 0 ]] && { sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq -t trixie-backports "${bmiss[@]}" \
    || die "Couldn't install Hyprland from Debian backports."; }
  c_ok "Packages installed"
}

install_helpers() {
  # cisa-* helpers go in /usr/local/bin so every session (Hyprland, Plasma, terminals) finds them
  local f need=0
  for f in "$HERE"/bin/*; do
    [[ $(readlink -f "/usr/local/bin/$(basename "$f")" 2>/dev/null) == "$f" ]] || need=1
  done
  if [[ $need -eq 1 ]]; then
    chmod +x "$HERE"/bin/*
    for f in "$HERE"/bin/*; do sudo ln -sfn "$f" "/usr/local/bin/$(basename "$f")"; done
  fi
  mkdir -p "$STATE"; echo "$HERE" > "$STATE/app-path"
  mkdir -p "$DATA/applications"
  cat > "$DATA/applications/cisa-themes.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=CISA Themes
Comment=Change the look of your desktop
Exec=konsole --hold -e "$HERE/rice.sh"
Icon=cisa-logo
Categories=Settings;DesktopSettings;
EOF
  # the CISA menu as an app: Plasma's panel Start button and the Meta key launch it
  cat > "$DATA/applications/cisa-menu.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=CISA Menu
Comment=Apps, CISA tools and power options
Exec=cisa-menu
Icon=cisa-logo
NoDisplay=true
EOF
}

# ---------- choosing ---------------------------------------------------------
choose_theme() {
  local ids=() args=() id cur
  cur=$(cat "$STATE/current-theme" 2>/dev/null || echo cisa-navy)
  mapfile -t ids < <(theme_ids)
  if gui; then
    for id in "${ids[@]}"; do
      args+=("$id" "$(theme_field "$id" NAME): $(theme_field "$id" DESC)" "$([[ $id == "$cur" ]] && echo on || echo off)")
    done
    THEME_ID=$(kdialog --title "CISA Themes" --radiolist "Pick a look for your desktop:" "${args[@]}" 2>/dev/null) || exit 0
  elif have whiptail; then
    for id in "${ids[@]}"; do args+=("$id" "$(theme_field "$id" DESC)" "$([[ $id == "$cur" ]] && echo ON || echo OFF)"); done
    THEME_ID=$(whiptail --title "CISA Themes" --radiolist "Pick a look:" 18 78 9 "${args[@]}" 3>&1 1>&2 2>&3 </dev/tty) || exit 0
  else
    local i=1; for id in "${ids[@]}"; do printf '  %d) %-12s %s\n' $i "$id" "$(theme_field "$id" DESC)"; i=$((i+1)); done
    read -rp "Theme number: " i </dev/tty; THEME_ID=${ids[$((i-1))]:-}
  fi
}

# ---------- Plasma -----------------------------------------------------------
apply_plasma() {
  have plasma-apply-colorscheme || return 0
  # shellcheck source=/dev/null
  source "$CUR/theme.env"
  plasma-apply-wallpaperimage "$CUR/wallpaper.png" >/dev/null 2>&1 || true
  kw --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General \
     --key Image "file://$CUR/lock.png"
  # Plasma ignores re-applying the active scheme, so bounce through Breeze. Scheme and accent are
  # separate calls: with --accent-color, Plasma 6.3 changes only the accent and ignores the scheme.
  plasma-apply-colorscheme BreezeClassic >/dev/null 2>&1 || true
  plasma-apply-colorscheme "$SCHEME_ID" >/dev/null 2>&1 || true
  plasma-apply-colorscheme --accent-color "$ACCENT" >/dev/null 2>&1 || true
  kw --file kdeglobals --group General --key ColorScheme "$SCHEME_ID"
  plasma-apply-desktoptheme default >/dev/null 2>&1 || true
  local p changeicons=""
  for p in /usr/lib/*/libexec/plasma-changeicons /usr/libexec/plasma-changeicons; do
    if [[ -x $p ]]; then changeicons=$p; break; fi
  done
  if [[ -n $changeicons && -d /usr/share/icons/$ICONS ]]; then "$changeicons" "$ICONS" >/dev/null 2>&1 || true; fi
  if [[ -d /usr/share/icons/$CURSOR ]]; then plasma-apply-cursortheme "$CURSOR" >/dev/null 2>&1 || true; fi
  kw --file kdeglobals --group General --key fixed "JetBrains Mono,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
  # Konsole: matching colours
  cat > "$DATA/konsole/CISA.profile" <<EOF
[Appearance]
ColorScheme=CISA-$ID
Font=JetBrains Mono,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1

[General]
Command=/bin/bash
Name=CISA
Parent=FALLBACK/
TerminalMargin=10
EOF
  kw --file konsolerc --group "Desktop Entry" --key DefaultProfile "CISA.profile"
  kw --file kwinrc --group Plugins --key blurEnabled true
  qdb org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
  # The Meta key opens the CISA menu. In Plasma 6, Meta alone is an ordinary global shortcut, held by
  # KWin (kglobalaccel runs inside it) and written back on logout, so edits during a session don't stick.
  # Plasma runs ~/.config/plasma-workspace/env/*.sh at every login *before* KWin starts: set it there.
  mkdir -p "$CONF/plasma-workspace/env"
  cat > "$CONF/plasma-workspace/env/cisa-rice.sh" <<'EOF'
#!/bin/sh
# CISA Rice: Meta (the Windows key) opens the CISA menu instead of the default launcher (Alt+F1 still does).
kwriteconfig6 --file kglobalshortcutsrc --group plasmashell --key "activate application launcher" "Alt+F1,Meta	Alt+F1,Activate Application Launcher"
kwriteconfig6 --file kglobalshortcutsrc --group services --group cisa-menu.desktop --key _launch "Meta"
EOF
  if in_plasma; then
    apply_plasma_panel "${LAYOUT:-dock}"
  else
    # plasmashell isn't running (e.g. we're in Hyprland): rearrange the panel at the next Plasma login
    mkdir -p "$CONF/autostart"
    cat > "$CONF/autostart/cisa-plasma-panel.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=CISA panel setup
Exec=sh -c '"$HERE/rice.sh" --plasma-panel-only ${LAYOUT:-dock}; rm -f "$CONF/autostart/cisa-plasma-panel.desktop"'
OnlyShowIn=KDE;
NoDisplay=true
X-KDE-autostart-phase=2
EOF
  fi
  c_ok "Plasma desktop themed too (pick it or Hyprland on the login screen)"
}

apply_plasma_panel() {  # dock (default): floating, centred, fits its contents. full: classic full-width taskbar
  local fit=true; [[ ${1:-dock} == full || $1 == win10 ]] && fit=false
  local js out id
  js=$(cat <<EOF
var launchers = [];
panels().forEach(function (p) { p.widgets("org.kde.plasma.icontasks").forEach(function (w) {
  w.currentConfigGroup = ["General"]; var l = w.readConfig("launchers", "");
  if (typeof l === "string") l = l.length ? l.split(",") : []; if (l.length) launchers = l; }); });
panels().forEach(function (p) { p.remove(); });
var panel = new Panel;
panel.location = "bottom";
panel.height = 2 * Math.floor(gridUnit * 2.3 / 2);
try { panel.floating = true; } catch (e) {}
if ($fit) { try { panel.lengthMode = "fit"; } catch (e) {} try { panel.alignment = "center"; } catch (e) {} }
var start = panel.addWidget("org.kde.plasma.icon");
start.currentConfigGroup = ["General"];
start.writeConfig("url", "file://$DATA/applications/cisa-menu.desktop");
var t = panel.addWidget("org.kde.plasma.icontasks");
t.currentConfigGroup = ["General"];
t.writeConfig("launchers", launchers);
t.writeConfig("maxStripes", 1);
panel.addWidget("org.kde.plasma.marginsseparator");
panel.addWidget("org.kde.plasma.systemtray");
var clock = panel.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("showDate", true);
clock.writeConfig("dateDisplayFormat", 1);
clock.writeConfig("dateFormat", "custom");
clock.writeConfig("customDateFormat", "ddd d MMM");
clock.writeConfig("use24hFormat", 2);
clock.writeConfig("autoFontAndSize", false);
clock.writeConfig("fontFamily", "JetBrains Mono");
clock.writeConfig("fontWeight", 600);
clock.writeConfig("fontSize", 10);
if (!$fit) panel.addWidget("org.kde.plasma.showdesktop");
print(panel.id);
EOF
)
  out=$(qdb org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$js" 2>/dev/null) \
    || { c_warn "Couldn't rearrange the Plasma panel"; return 0; }
  id=$(grep -oE '[0-9]+' <<<"$out" | tail -1)
  if [[ -n $id ]]; then
    # translucent panel with blur behind it (0 adaptive, 1 opaque, 2 translucent); needs a shell restart
    kw --file plasmashellrc --group PlasmaViews --group "Panel $id" --key panelOpacity 2
    systemctl --user restart plasma-plasmashell.service >/dev/null 2>&1 || true
  fi
  if [[ $fit == true ]]; then c_ok "Plasma panel: floating dock"; else c_ok "Plasma panel: floating taskbar"; fi
}

HYPR_UNITS=(waybar.service swaync.service hypridle.service hyprpaper.service hyprpolkitagent.service hyprsunset.service)

disable_global_autostart() {
  # Debian's waybar, swaync and hypr* packages enable systemd user units for *every* graphical session:
  # that put Waybar (and hypridle) inside Plasma and raced the Hyprland session's own copies.
  # The Hyprland session starts everything it needs itself (hyprland.conf exec-once).
  local u need=()
  for u in "${HYPR_UNITS[@]}"; do
    [[ -e /etc/systemd/user/graphical-session.target.wants/$u ]] && need+=("$u")
  done
  if [[ ${#need[@]} -gt 0 ]]; then
    sudo systemctl --global disable "${need[@]}" >/dev/null 2>&1 || true
    c_ok "Stopped Hyprland's bar/notifications/idle services auto-starting in every session"
  fi
  systemctl --user disable "${HYPR_UNITS[@]}" >/dev/null 2>&1 || true
  if in_plasma; then systemctl --user stop "${HYPR_UNITS[@]}" >/dev/null 2>&1 || true; fi
}

# ---------- terminal ---------------------------------------------------------
apply_shell() {
  touch "$HOME/.bashrc"
  sed -i '/^# >>> cisa-rice >>>$/,/^# <<< cisa-rice <<<$/d' "$HOME/.bashrc"
  cat >> "$HOME/.bashrc" <<'EOF'
# >>> cisa-rice >>>
if [[ $- == *i* ]]; then
  # system info banner: type "fetch" (the dashboard opens with it)
  fetch() { if [[ $TERM == xterm-kitty ]]; then fastfetch -c ~/.config/fastfetch/kitty.jsonc; else fastfetch; fi; }
  [[ -n ${CISA_FETCH:-} ]] && command -v fastfetch >/dev/null && { fetch; unset CISA_FETCH; }
  command -v starship >/dev/null && eval "$(starship init bash)"
fi
# <<< cisa-rice <<<
EOF
}

# ---------- live reload ------------------------------------------------------
reload_hypr() {
  in_hypr || return 0
  hyprctl reload >/dev/null 2>&1 || true
  pkill -x swaybg 2>/dev/null || true
  setsid -f swaybg -i "$CUR/wallpaper.png" -m fill >/dev/null 2>&1
  # reload Waybar's config and style in place; cisa-bar (started by Hyprland) keeps it alive
  if pgrep -x waybar >/dev/null; then pkill -USR2 -x waybar
  elif ! pgrep -f bin/cisa-bar >/dev/null; then setsid -f cisa-bar >/dev/null 2>&1; fi
  swaync-client -rs >/dev/null 2>&1 || true
  hyprctl setcursor "$(theme_field "$THEME_ID" CURSOR)" 24 >/dev/null 2>&1 || true
  local errs; errs=$(hyprctl configerrors 2>/dev/null | grep -v '^$' || true)
  [[ -n $errs && $errs != *"no errors"* ]] && c_warn "Hyprland config warnings: $errs"
  c_ok "Hyprland reloaded"
}

apply_login_screen() {
  [[ $DO_LOGIN -eq 1 && -d /usr/share/sddm/themes/breeze ]] || return 0
  if sudo -n true 2>/dev/null || [[ $ASSUME_YES -eq 0 ]]; then
    if sudo install -Dm644 "$CUR/lock.png" /usr/share/wallpapers/cisa-rice-login.png \
       && printf '[General]\nbackground=/usr/share/wallpapers/cisa-rice-login.png\ntype=image\n' \
          | sudo tee /usr/share/sddm/themes/breeze/theme.conf.user >/dev/null; then
      c_ok "Login screen"
    fi
  fi
}

# ---------- main -------------------------------------------------------------
if [[ $ACTION == panel ]]; then
  in_plasma && apply_plasma_panel "$LAYOUT"
  exit 0
fi

mkdir -p "$STATE"
migrate_v1
install_deps
disable_global_autostart
install_helpers
[[ -z $THEME_ID ]] && choose_theme
[[ -n $THEME_ID && -f $HERE/themes/$THEME_ID.theme ]] || die "Unknown theme '$THEME_ID'. Try --list."
take_backup

c_info "Applying \"$(theme_field "$THEME_ID" NAME)\""
python3 "$HERE/lib/render.py" "$THEME_ID" >/dev/null
c_ok "Hyprland, Waybar, launcher, lock screen, power menu, notifications, kitty, btop, cava, fastfetch"
mkdir -p "$DATA/icons/hicolor/scalable/apps"
cp "$HERE/assets/cisa-logo.svg" "$DATA/icons/hicolor/scalable/apps/cisa-logo.svg"
[[ $DO_TERMINAL -eq 1 ]] && { apply_shell; c_ok "Terminal banner and prompt"; }
apply_plasma
apply_login_screen
echo "$THEME_ID" > "$STATE/current-theme"
reload_hypr

echo
c_info "Done! \"$(theme_field "$THEME_ID" NAME)\" is on."
if ! in_hypr; then
  echo "    To try the riced desktop: log out, pick \"Hyprland\" on the login screen (bottom-left), log in."
fi
echo "    In Hyprland: Super opens apps, Super+/ shows every shortcut, Super+Shift+T changes theme."
echo "    Undo everything: $HERE/rice.sh --restore"
