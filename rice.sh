#!/usr/bin/env bash
# CISA Rice: one-command desktop themes for CISA Linux (works on any Debian/KDE Plasma 6 system).
#
#   ./rice.sh                       pick a theme in a window
#   ./rice.sh --theme daylight      apply a theme directly
#   ./rice.sh --list                list themes
#   ./rice.sh --restore             undo everything (restore the backup taken on first run)
#
# Options: --layout win10|win11  --no-terminal  --no-login-screen  --yes (no questions)
set -euo pipefail
trap 'printf "\e[1;31m✗ Something went wrong (rice.sh line %s: %s). Your backup is safe; run with --restore to undo.\e[0m\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE="$DATA/cisa-rice"
BACKUP="$STATE/backup"
VERSION="1.0"

source "$HERE/lib/wallpaper.sh"

# ---------- helpers ----------------------------------------------------------
c_info()  { printf '\e[1;34m==>\e[0m %s\n' "$*"; }
c_ok()    { printf '\e[1;32m ✓\e[0m %s\n' "$*"; }
c_warn()  { printf '\e[1;33m !\e[0m %s\n' "$*" >&2; }
die()     { printf '\e[1;31m✗ %s\e[0m\n' "$*" >&2; exit 1; }
have()    { command -v "$1" >/dev/null 2>&1; }
gui()     { [[ -n ${WAYLAND_DISPLAY:-}${DISPLAY:-} ]] && have kdialog; }

hex_rgb() { local h=${1#\#}; printf '%d,%d,%d' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"; }
# mix <hexA> <hexB> <percent of B>  ->  hex
mix() {
  local a=${1#\#} b=${2#\#} p=$3 out="#" i ca cb
  for i in 0 2 4; do
    ca=$((16#${a:i:2})); cb=$((16#${b:i:2}))
    out+=$(printf '%02x' $(( (ca * (100 - p) + cb * p) / 100 )))
  done
  echo "$out"
}
# readable text color on top of <hex>
on_color() {
  local h=${1#\#} r g b
  r=$((16#${h:0:2})); g=$((16#${h:2:2})); b=$((16#${h:4:2}))
  (( (r * 299 + g * 587 + b * 114) / 1000 > 150 )) && echo "#101010" || echo "#ffffff"
}

kw()   { kwriteconfig6 "$@"; }
qdb()  { if have qdbus6; then qdbus6 "$@"; else qdbus "$@"; fi; }

theme_ids() { for f in "$HERE"/themes/*.theme; do basename "$f" .theme; done; }
theme_field() { ( source "$HERE/themes/$1.theme"; eval "echo \"\$$2\"" ); }

# ---------- arguments --------------------------------------------------------
THEME_ID=""; LAYOUT_OVERRIDE=""; DO_TERMINAL=1; DO_LOGIN=1; ASSUME_YES=0; ACTION=apply
while [[ $# -gt 0 ]]; do
  case $1 in
    --theme)  THEME_ID=$2; shift ;;
    --layout) LAYOUT_OVERRIDE=$2; shift ;;
    --no-terminal) DO_TERMINAL=0 ;;
    --no-login-screen) DO_LOGIN=0 ;;
    --yes|-y) ASSUME_YES=1 ;;
    --list)   ACTION=list ;;
    --restore) ACTION=restore ;;
    --version) echo "cisa-rice $VERSION"; exit 0 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "Unknown option: $1 (see --help)" ;;
  esac
  shift
done

[[ $EUID -eq 0 ]] && die "Run this as your normal user, not with sudo. It will ask for your password when needed."

if [[ $ACTION == list ]]; then
  for id in $(theme_ids); do printf '  %-16s %s\n' "$id" "$(theme_field "$id" DESC)"; done
  exit 0
fi

# ---------- backup / restore -------------------------------------------------
BACKUP_FILES=(
  "$CONF/kdeglobals" "$CONF/kwinrc" "$CONF/plasmarc" "$CONF/kcminputrc" "$CONF/konsolerc"
  "$CONF/kscreenlockerrc" "$CONF/plasmashellrc" "$CONF/plasma-org.kde.plasma.desktop-appletsrc"
  "$HOME/.bashrc"
)

take_backup() {
  [[ -d $BACKUP ]] && return 0          # keep the original pre-rice state, never overwrite it
  mkdir -p "$BACKUP"
  local f
  for f in "${BACKUP_FILES[@]}"; do
    if [[ -f $f ]]; then cp -a "$f" "$BACKUP/"; fi
  done
  date > "$BACKUP/.taken"
  c_ok "Backed up your current settings to $BACKUP"
}

do_restore() {
  [[ -d $BACKUP ]] || die "No backup found. Nothing to restore."
  c_info "Restoring your original desktop settings"
  systemctl --user stop plasma-plasmashell.service 2>/dev/null || true
  local f
  for f in "${BACKUP_FILES[@]}"; do
    if [[ -f $BACKUP/$(basename "$f") ]]; then cp -a "$BACKUP/$(basename "$f")" "$f"; fi
  done
  # remove our block from .bashrc if the backup predates it
  sed -i '/^# >>> cisa-rice >>>$/,/^# <<< cisa-rice <<<$/d' "$HOME/.bashrc" 2>/dev/null || true
  rm -f "$CONF/fastfetch/config.jsonc" "$CONF/starship.toml"
  systemctl --user start plasma-plasmashell.service 2>/dev/null || (plasmashell >/dev/null 2>&1 & disown)
  local scheme; scheme=$(kreadconfig6 --file kdeglobals --group General --key ColorScheme 2>/dev/null || true)
  [[ -n $scheme ]] && plasma-apply-colorscheme "$scheme" >/dev/null 2>&1 || true
  rm -f "$STATE/current"
  c_ok "Restored. Log out and back in if anything still looks off."
  exit 0
}
[[ $ACTION == restore ]] && do_restore

# ---------- checks & dependencies --------------------------------------------
have plasmashell || die "KDE Plasma isn't installed. CISA Rice themes the Plasma desktop."
have kwriteconfig6 || die "This needs KDE Plasma 6 (kwriteconfig6 not found)."

PKGS=(papirus-icon-theme bibata-cursor-theme fonts-jetbrains-mono librsvg2-bin kdialog fastfetch starship)
install_deps() {
  local missing=() p
  for p in "${PKGS[@]}"; do dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'ok installed' || missing+=("$p"); done
  [[ ${#missing[@]} -eq 0 ]] && return 0
  c_info "Installing theme packages: ${missing[*]}"
  echo "    (you may be asked for your password)"
  sudo apt-get update -qq || c_warn "apt update had errors; trying anyway"
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}" \
    || die "Couldn't install packages. Are you connected to the internet?"
}

# ---------- choosing ---------------------------------------------------------
choose_theme() {
  local ids=() args=() id cur
  cur=$(cat "$STATE/current" 2>/dev/null || echo cisa-navy)
  mapfile -t ids < <(theme_ids)
  if gui; then
    for id in "${ids[@]}"; do
      args+=("$id" "$(theme_field "$id" NAME): $(theme_field "$id" DESC)" "$([[ $id == "$cur" ]] && echo on || echo off)")
    done
    THEME_ID=$(kdialog --title "CISA Themes" --geometry 640x360 \
      --radiolist "Pick a look for your desktop:" "${args[@]}") || exit 0
  elif have whiptail; then
    for id in "${ids[@]}"; do args+=("$id" "$(theme_field "$id" DESC)" "$([[ $id == "$cur" ]] && echo ON || echo OFF)"); done
    THEME_ID=$(whiptail --title "CISA Themes" --radiolist "Pick a look:" 16 78 6 "${args[@]}" 3>&1 1>&2 2>&3 </dev/tty) || exit 0
  else
    local i=1; for id in "${ids[@]}"; do printf '  %d) %-16s %s\n' $i "$id" "$(theme_field "$id" DESC)"; i=$((i+1)); done
    read -rp "Theme number: " i </dev/tty; THEME_ID=${ids[$((i-1))]:-}
  fi
}

choose_layout() {
  [[ -n $LAYOUT_OVERRIDE || $ASSUME_YES -eq 1 ]] && return 0
  local def=$LAYOUT
  if gui; then
    LAYOUT_OVERRIDE=$(kdialog --title "CISA Themes" --radiolist "Taskbar style:" \
      win10 "Windows 10 style: icons on the left" "$([[ $def == win10 ]] && echo on || echo off)" \
      win11 "Windows 11 style: centered, floating" "$([[ $def == win11 ]] && echo on || echo off)") || exit 0
  fi
}

# ---------- generators -------------------------------------------------------
write_colorscheme() {  # write_colorscheme <file> <scheme-id>
  local f=$1 id=$2
  local view=$BG window=$SURFACE
  [[ $DARK -eq 0 ]] && { view="#ffffff"; window=$BG; }
  local button; button=$(mix "$window" "$FG" 7)
  local alt; alt=$(mix "$view" "$FG" 4)
  local sel_fg; sel_fg=$(on_color "$ACCENT")
  local hover=$ACCENT2

  _grp() {  # _grp <name> <bg> <alt-bg> <fg>
    cat <<EOF
[$1]
BackgroundAlternate=$(hex_rgb "$3")
BackgroundNormal=$(hex_rgb "$2")
DecorationFocus=$(hex_rgb "$ACCENT")
DecorationHover=$(hex_rgb "$hover")
ForegroundActive=$(hex_rgb "$ACCENT2")
ForegroundInactive=$(hex_rgb "$MUTED")
ForegroundLink=$(hex_rgb "$ACCENT2")
ForegroundNegative=$(hex_rgb "$RED")
ForegroundNeutral=$(hex_rgb "$YELLOW")
ForegroundNormal=$(hex_rgb "$4")
ForegroundPositive=$(hex_rgb "$GREEN")
ForegroundVisited=$(hex_rgb "$MAGENTA")

EOF
  }
  {
    cat <<EOF
[ColorEffects:Disabled]
Color=$(hex_rgb "$window")
ColorAmount=0.5
ColorEffect=3
ContrastAmount=0.5
ContrastEffect=0
IntensityAmount=0
IntensityEffect=0

[ColorEffects:Inactive]
ChangeSelectionColor=true
Color=$(hex_rgb "$window")
ColorAmount=0.025
ColorEffect=0
ContrastAmount=0.1
ContrastEffect=0
Enable=false
IntensityAmount=0
IntensityEffect=0

EOF
    _grp "Colors:Button" "$button" "$(mix "$button" "$FG" 4)" "$FG"
    _grp "Colors:Complementary" "$BG" "$SURFACE" "$FG"
    _grp "Colors:Header" "$window" "$(mix "$window" "$FG" 4)" "$FG"
    _grp "Colors:Header][Inactive" "$view" "$(mix "$view" "$FG" 4)" "$MUTED"
    _grp "Colors:Selection" "$ACCENT" "$(mix "$ACCENT" "$BG" 15)" "$sel_fg"
    _grp "Colors:Tooltip" "$window" "$alt" "$FG"
    _grp "Colors:View" "$view" "$alt" "$FG"
    _grp "Colors:Window" "$window" "$(mix "$window" "$FG" 4)" "$FG"
    cat <<EOF
[General]
ColorScheme=$id
Name=CISA $NAME
shadeSortColumn=true

[KDE]
contrast=4

[WM]
activeBackground=$(hex_rgb "$window")
activeBlend=$(hex_rgb "$FG")
activeForeground=$(hex_rgb "$FG")
inactiveBackground=$(hex_rgb "$view")
inactiveBlend=$(hex_rgb "$MUTED")
inactiveForeground=$(hex_rgb "$MUTED")
EOF
  } > "$f"
}

write_konsole() {  # konsole color scheme + "CISA" profile
  local d="$DATA/konsole"; mkdir -p "$d"
  local tbg=$BG; [[ $DARK -eq 0 ]] && tbg="#ffffff"
  local black white
  if [[ $DARK -eq 1 ]]; then black=$(mix "$BG" "#000000" 30); white=$FG; else black=$FG; white=$(mix "$BG" "#000000" 15); fi
  local -a cols=("$black" "$RED" "$GREEN" "$YELLOW" "$BLUE" "$MAGENTA" "$CYAN" "$white")
  {
    echo "[Background]"; echo "Color=$(hex_rgb "$tbg")"; echo
    echo "[BackgroundIntense]"; echo "Color=$(hex_rgb "$tbg")"; echo
    local i
    for i in 0 1 2 3 4 5 6 7; do
      echo "[Color$i]"; echo "Color=$(hex_rgb "${cols[$i]}")"; echo
      echo "[Color${i}Intense]"; echo "Color=$(hex_rgb "$(mix "${cols[$i]}" "#ffffff" 25)")"; echo
    done
    echo "[Foreground]"; echo "Color=$(hex_rgb "$FG")"; echo
    echo "[ForegroundIntense]"; echo "Color=$(hex_rgb "$ACCENT2")"; echo
    echo "[General]"; echo "Description=CISA $NAME"; echo "Opacity=$TERM_OPACITY"; echo "Blur=true"
  } > "$d/CISA-$THEME_ID.colorscheme"

  cat > "$d/CISA.profile" <<EOF
[Appearance]
ColorScheme=CISA-$THEME_ID
Font=JetBrains Mono,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1

[General]
Command=/bin/bash
Name=CISA
Parent=FALLBACK/
TerminalMargin=10

[Scrolling]
HistorySize=10000
EOF
  kw --file konsolerc --group "Desktop Entry" --key DefaultProfile "CISA.profile"
}

write_fetch_and_prompt() {
  mkdir -p "$CONF/fastfetch"
  cat > "$CONF/fastfetch/cisa-logo.txt" <<'EOF'
$1    ▄▄██████████▄▄
$1  ████▀▀▀▀▀▀▀▀▀▀████
$1  ███   $2▄▄████▄▄$1   ███
$1  ███  $2██▀    ▀██$1  ███
$1  ███ $2▄██▄▄▄▄▄▄██▄$1 ███
$1  ███ $2████▀  ▀████$1 ███
$1   ███ $2███▄  ▄███$1 ███
$1    ▀███ $2▀▀▀▀▀▀$1 ███▀
$1      ▀▀███▄▄███▀▀
$1          ▀██▀
EOF
  local a1 a2; a1="38;2;$(hex_rgb "$ACCENT" | tr , ';')"; a2="38;2;$(hex_rgb "$FG" | tr , ';')"
  local k="38;2;$(hex_rgb "$ACCENT2" | tr , ';')"
  cat > "$CONF/fastfetch/config.jsonc" <<EOF
{
  "\$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  "logo": { "type": "file", "source": "$CONF/fastfetch/cisa-logo.txt",
            "color": { "1": "$a1", "2": "$a2" }, "padding": { "top": 1, "right": 3 } },
  "display": { "separator": "  ", "color": { "keys": "$k" } },
  "modules": [
    { "type": "custom", "format": "\u001b[1;${a2}mCISA Linux\u001b[0m · Learn to hack. The legal way." },
    { "type": "custom", "format": "\u001b[${k}m──────────────────────────────────────\u001b[0m" },
    { "type": "os", "key": "OS    " },
    { "type": "kernel", "key": "Kernel" },
    { "type": "uptime", "key": "Uptime" },
    { "type": "de", "key": "Desktop" },
    { "type": "cpu", "key": "CPU   " },
    { "type": "memory", "key": "Memory" },
    { "type": "disk", "key": "Disk  ", "folders": "/" },
    { "type": "localip", "key": "IP    ", "showIpv6": false },
    { "type": "custom", "format": "Theme   $NAME" },
    "break",
    { "type": "colors", "symbol": "circle" }
  ]
}
EOF

  cat > "$CONF/starship.toml" <<EOF
# CISA Rice prompt ($NAME). Shows your VPN IP when connected to TryHackMe/OffSec (tun0).
add_newline = true
palette = "cisa"
format = "\$username\$hostname\$directory\$git_branch\$git_status\$python\${custom.vpn}\$cmd_duration\$line_break\$character"

[palettes.cisa]
accent = "$ACCENT"
accent2 = "$ACCENT2"
good = "$GREEN"
bad = "$RED"
warn = "$YELLOW"
muted = "$MUTED"

[username]
show_always = true
style_user = "bold accent2"
style_root = "bold bad"
format = "[\$user](\$style)"

[hostname]
ssh_only = false
style = "bold accent"
format = "[@\$hostname](\$style) "

[directory]
style = "bold accent2"
truncation_length = 4
read_only = " (read-only)"

[git_branch]
style = "bold warn"
format = "on [\$branch](\$style) "

[git_status]
style = "warn"

[python]
style = "warn"
format = "[py \$version](\$style) "

[cmd_duration]
style = "muted"
format = "took [\$duration](\$style) "

[character]
success_symbol = "[❯](bold good)"
error_symbol = "[❯](bold bad)"

[custom.vpn]
command = "ip -4 -o addr show tun0 | awk '{print \$4}' | cut -d/ -f1"
when = "ip link show tun0"
shell = ["bash", "--noprofile", "--norc"]
style = "bold good"
format = "[VPN \$output](\$style) "
EOF

  # (re)write our block in ~/.bashrc
  touch "$HOME/.bashrc"
  sed -i '/^# >>> cisa-rice >>>$/,/^# <<< cisa-rice <<<$/d' "$HOME/.bashrc"
  cat >> "$HOME/.bashrc" <<'EOF'
# >>> cisa-rice >>>
if [[ $- == *i* ]]; then
  [[ -z ${CISA_NO_FETCH:-} ]] && command -v fastfetch >/dev/null && fastfetch
  command -v starship >/dev/null && eval "$(starship init bash)"
fi
# <<< cisa-rice <<<
EOF
}

apply_panel() {  # rebuild the taskbar, keeping the user's pinned apps
  local layout=$1 float=$2 win11=false fl=false
  [[ $layout == win11 ]] && win11=true
  [[ $float -eq 1 ]] && fl=true
  local js
  js=$(cat <<EOF
var launchers = [];
panels().forEach(function (p) {
  p.widgets("org.kde.plasma.icontasks").forEach(function (w) {
    w.currentConfigGroup = ["General"];
    var l = w.readConfig("launchers", "");
    if (typeof l === "string") l = l.length ? l.split(",") : [];
    if (l.length) launchers = l;
  });
});
if (!launchers.length) launchers = ["applications:org.kde.dolphin.desktop", "applications:firefox-esr.desktop",
  "applications:org.kde.konsole.desktop", "applications:systemsettings.desktop"];
panels().forEach(function (p) { p.remove(); });

var panel = new Panel;
panel.location = "bottom";
panel.height = 2 * Math.floor(gridUnit * 2.4 / 2);
try { panel.floating = $fl; } catch (e) {}
if ($win11) panel.addWidget("org.kde.plasma.panelspacer");
var k = panel.addWidget("org.kde.plasma.kickoff");
k.currentConfigGroup = ["General"];
k.writeConfig("icon", "cisa-logo");
var t = panel.addWidget("org.kde.plasma.icontasks");
t.currentConfigGroup = ["General"];
t.writeConfig("launchers", launchers);
if ($win11) panel.addWidget("org.kde.plasma.panelspacer");
else panel.addWidget("org.kde.plasma.marginsseparator");
panel.addWidget("org.kde.plasma.systemtray");
panel.addWidget("org.kde.plasma.digitalclock");
panel.addWidget("org.kde.plasma.showdesktop");
EOF
)
  qdb org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$js" >/dev/null
}

# ---------- apply ------------------------------------------------------------
apply_theme() {
  local out="$STATE/generated/$THEME_ID"; mkdir -p "$out"
  local scheme_id="CISA${THEME_ID//-/}"
  local layout=${LAYOUT_OVERRIDE:-$LAYOUT}

  c_info "Applying \"$NAME\""

  # CISA badge as Start-menu icon (also works on non-CISA systems)
  local ic="$DATA/icons/hicolor/256x256/apps"; mkdir -p "$ic"
  cp "$HERE/assets/cisa-logo.png" "$ic/cisa-logo.png"

  # Wallpaper (desktop + lock screen)
  make_wallpaper_svg "$out/wallpaper.svg" "$HERE/assets/cisa-logo.png"
  rsvg-convert -w 2560 -h 1440 "$out/wallpaper.svg" -o "$out/wallpaper.png"
  plasma-apply-wallpaperimage "$out/wallpaper.png" >/dev/null
  kw --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General \
     --key Image "file://$out/wallpaper.png"
  c_ok "Wallpaper"

  # Colors + accent
  mkdir -p "$DATA/color-schemes"
  write_colorscheme "$DATA/color-schemes/$scheme_id.colors" "$scheme_id"
  # Plasma skips re-applying the scheme already in use, so bounce through Breeze first.
  # The scheme and the accent must be separate calls: with --accent-color, Plasma 6.3
  # only changes the accent and ignores the scheme name.
  plasma-apply-colorscheme BreezeClassic >/dev/null 2>&1 || true
  plasma-apply-colorscheme "$scheme_id" >/dev/null 2>&1 || true
  plasma-apply-colorscheme --accent-color "$ACCENT" >/dev/null 2>&1 || true
  plasma-apply-desktoptheme default >/dev/null 2>&1 || true
  if [[ $(kreadconfig6 --file kdeglobals --group General --key ColorScheme 2>/dev/null) == "$scheme_id" ]]; then
    c_ok "Colors"
  else
    c_warn "Plasma didn't switch the color scheme. Pick \"CISA $NAME\" in System Settings > Colors"
  fi

  # Icons + cursor + fonts
  local changeicons="" p
  for p in /usr/lib/*/libexec/plasma-changeicons /usr/libexec/plasma-changeicons; do
    if [[ -x $p ]]; then changeicons=$p; break; fi
  done
  if [[ -n $changeicons && -d /usr/share/icons/$ICONS ]]; then "$changeicons" "$ICONS" >/dev/null 2>&1 || true
  else c_warn "Icon theme $ICONS not found; kept current icons"; fi
  if [[ -d /usr/share/icons/$CURSOR ]]; then plasma-apply-cursortheme "$CURSOR" >/dev/null 2>&1 || true
  else c_warn "Cursor theme $CURSOR not found"; fi
  kw --file kdeglobals --group General --key fixed "JetBrains Mono,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
  c_ok "Icons, cursor and fonts"

  # Window effects: blur behind translucent windows, rounded Breeze titlebars
  kw --file kwinrc --group Plugins --key blurEnabled true
  kw --file kwinrc --group Plugins --key wobblywindowsEnabled false
  kw --file kwinrc --group org.kde.kdecoration2 --key library org.kde.breeze
  kw --file kwinrc --group org.kde.kdecoration2 --key theme Breeze
  kw --file breezerc --group Common --key OutlineIntensity OutlineLow
  qdb org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
  c_ok "Window effects"

  # Taskbar
  apply_panel "$layout" "$FLOAT" && c_ok "Taskbar ($layout style)" || c_warn "Couldn't rearrange the taskbar"

  # Terminal
  write_konsole
  if [[ $DO_TERMINAL -eq 1 ]]; then write_fetch_and_prompt; c_ok "Terminal theme, fastfetch and prompt"
  else c_ok "Terminal colors"; fi

  # Login screen (needs admin rights)
  if [[ $DO_LOGIN -eq 1 && -d /usr/share/sddm/themes/breeze ]]; then
    if sudo -n true 2>/dev/null || [[ $ASSUME_YES -eq 0 ]]; then
      if sudo install -Dm644 "$out/wallpaper.png" /usr/share/wallpapers/cisa-rice-login.png \
         && printf '[General]\nbackground=/usr/share/wallpapers/cisa-rice-login.png\ntype=image\n' \
            | sudo tee /usr/share/sddm/themes/breeze/theme.conf.user >/dev/null; then
        c_ok "Login screen"
      else c_warn "Skipped login screen"; fi
    fi
  fi

  echo "$THEME_ID" > "$STATE/current"
}

install_launcher() {  # "CISA Themes" entry in the Start menu
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
}

# ---------- main -------------------------------------------------------------
mkdir -p "$STATE"
install_deps
[[ -z $THEME_ID ]] && choose_theme
[[ -n $THEME_ID && -f $HERE/themes/$THEME_ID.theme ]] || die "Unknown theme '$THEME_ID'. Try --list."
# shellcheck source=/dev/null
source "$HERE/themes/$THEME_ID.theme"
choose_layout
take_backup
apply_theme
install_launcher

echo
c_info "Done! \"$NAME\" is on. Open a new terminal to see the new prompt."
echo "    Change theme any time: Start menu > CISA Themes   (or: $HERE/rice.sh)"
echo "    Undo everything:       $HERE/rice.sh --restore"
gui && [[ $ASSUME_YES -eq 0 ]] && kdialog --title "CISA Themes" --passivepopup "\"$NAME\" applied" 5 2>/dev/null || true
