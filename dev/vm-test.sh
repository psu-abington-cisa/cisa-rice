#!/usr/bin/env bash
# End-to-end test in a VM: boot the CISA Linux ISO, install CISA Rice, log into the Hyprland
# session, apply every theme and screenshot each (plus launcher, power menu and lock screen).
# Run as root inside WSL/Linux:
#   bash dev/vm-test.sh [path/to/cisa-linux.iso] [theme ...]
#   FROM_GITHUB=1 bash dev/vm-test.sh ...   # install with the published curl | bash command instead
set -euo pipefail
cd "$(dirname "$0")/.."
ISO="${1:-../cisa-linux/out/cisa-linux-2026.10-amd64.iso}"; shift || true
THEMES=("$@"); [[ ${#THEMES[@]} -eq 0 ]] && mapfile -t THEMES < <(ls themes | sed 's/\.theme$//')
OUT=dev/vm-shots; mkdir -p "$OUT"; rm -f "$OUT"/*.png
T=/var/tmp/cisa-rice-vm; mkdir -p "$T"; MON="$T/mon.sock"; QGA="$T/qga.sock"; rm -f "$MON" "$QGA"

qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m 6144 -cdrom "$ISO" -boot d -vga virtio -display none \
  -nic user,model=virtio-net-pci -monitor unix:"$MON",server,nowait \
  -chardev socket,path="$QGA",server=on,wait=off,id=qga0 \
  -device virtio-serial -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0 &
QPID=$!; trap 'kill $QPID 2>/dev/null || true' EXIT

qga() {
  local id=$RANDOM
  { printf '{"execute":"guest-sync","arguments":{"id":%d}}\n%s\n' "$id" "$1"; sleep "${2:-2}"; } \
    | socat -t10 - UNIX-CONNECT:"$QGA" | grep -vE "\"return\": ?$id\}" | tail -1 || true
}
gexec() {  # gexec <timeout> <command> [stdin-file]: run as root in the guest, wait, print output
  local to=$1 cmd=$2 input=${3:-} req pid st i
  if [[ -n $input ]]; then
    base64 -w0 "$input" > "$T/input.b64"
    req=$(jq -cn --arg c "$cmd" --rawfile in "$T/input.b64" '{execute:"guest-exec",arguments:{path:"/bin/bash",arg:["-c",$c],"input-data":$in,"capture-output":true}}')
  else
    req=$(jq -cn --arg c "$cmd" '{execute:"guest-exec",arguments:{path:"/bin/bash",arg:["-c",$c],"capture-output":true}}')
  fi
  pid=$(qga "$req" | jq -r '.return.pid // empty')
  [[ -n $pid ]] || { echo "(guest-exec failed)"; return 1; }
  for ((i = 0; i < to; i += 3)); do
    st=$(qga "{\"execute\":\"guest-exec-status\",\"arguments\":{\"pid\":$pid}}" 1)
    if [[ $(echo "$st" | jq -r '.return.exited') == true ]]; then
      echo "$st" | jq -r '.return["out-data"] // empty' | base64 -d
      echo "$st" | jq -r '.return["err-data"] // empty' | base64 -d | tail -15 >&2
      return "$(echo "$st" | jq -r '.return.exitcode // 0')"
    fi
    sleep 2
  done
  echo "(timed out after ${to}s)"; return 1
}
shot() { echo "screendump $T/s.ppm" | socat - UNIX-CONNECT:"$MON" >/dev/null; sleep 1; convert "$T/s.ppm" "$OUT/$1.png"; echo "  screenshot $OUT/$1.png"; }

USER_ENV='HOME=/home/cisa USER=cisa XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus'
AS_USER="runuser -u cisa -- env $USER_ENV"
# inside Hyprland: find its instance signature and wayland socket
HYPR_ENV='sig=$(ls -t /run/user/1000/hypr/ 2>/dev/null | head -1); wl=$(ls /run/user/1000/ | grep -E "^wayland-[0-9]+$" | head -1); export HYPRLAND_INSTANCE_SIGNATURE=$sig WAYLAND_DISPLAY=$wl XDG_CURRENT_DESKTOP=Hyprland'
HYPR_USER="$HYPR_ENV; runuser -u cisa -- env $USER_ENV HYPRLAND_INSTANCE_SIGNATURE=\$sig WAYLAND_DISPLAY=\$wl XDG_CURRENT_DESKTOP=Hyprland"

echo "== waiting for the live desktop"
for i in $(seq 1 60); do
  sleep 5
  [[ $(qga '{"execute":"guest-ping"}') == *return* ]] && gexec 10 'pgrep -x plasmashell >/dev/null' >/dev/null 2>&1 && break
done
sleep 10

RICE=/home/cisa/cisa-rice/rice.sh
if [[ -n ${UPGRADE_FROM:-} ]]; then
  # simulate an existing user: install an older release first (e.g. UPGRADE_FROM=6e9101d for 1.0)
  echo "== installing old release $UPGRADE_FROM first"
  gexec 600 "$AS_USER WAYLAND_DISPLAY=wayland-0 XDG_CURRENT_DESKTOP=KDE bash -c 'mkdir -p ~/old && curl -fsSL https://github.com/psu-abington-cisa/cisa-rice/archive/$UPGRADE_FROM.tar.gz | tar xz -C ~/old --strip-components=1 && bash ~/old/rice.sh --theme daylight --yes' 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tail -6" || echo "  !! old release failed"
  gexec 10 "ls -la /home/cisa/.local/share/cisa-rice/" || true
fi
if [[ ${FROM_GITHUB:-} == 1 ]]; then
  URL=https://raw.githubusercontent.com/psu-abington-cisa/cisa-rice/main/install.sh
  echo "== installing from GitHub (Plasma session): $URL"
  gexec 900 "$AS_USER WAYLAND_DISPLAY=wayland-0 XDG_CURRENT_DESKTOP=KDE script -qec 'curl -fsSL $URL | bash -s -- --theme ${THEMES[0]} --yes' /dev/null 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tail -16" || echo "  !! install failed"
  RICE=/home/cisa/.local/share/cisa-rice/app/rice.sh
else
  echo "== uploading repo and installing (Plasma session)"
  tar czf "$T/repo.tgz" --exclude=dev/previews --exclude=dev/vm-shots --exclude=.git .
  gexec 30 'mkdir -p /home/cisa/cisa-rice && tar xzf - -C /home/cisa/cisa-rice && chown -R cisa:cisa /home/cisa/cisa-rice && echo uploaded' "$T/repo.tgz"
  gexec 900 "$AS_USER WAYLAND_DISPLAY=wayland-0 XDG_CURRENT_DESKTOP=KDE bash $RICE --theme ${THEMES[0]} --yes 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tail -16" || echo "  !! rice.sh failed"
fi
sleep 5; gexec 10 "pkill -f firefox-esr; true" >/dev/null 2>&1 || true; sleep 3; shot "plasma-${THEMES[0]}"
# Super (Meta) in Plasma should open the CISA menu
echo "sendkey meta_l" | socat - UNIX-CONNECT:"$MON" >/dev/null; sleep 4; shot "plasma-menu"
gexec 10 "pgrep -af cisa-menu | head -2; pkill -f bin/cisa-menu; rm -f /run/user/1000/cisa-menu.pid; true" || true
if [[ ${PLASMA_DEBUG:-} == 1 ]]; then
  echo "== plasma debug"
  gexec 30 "$AS_USER bash -c 'echo launch=\$(kreadconfig6 --file kglobalshortcutsrc --group services --group cisa-menu.desktop --key _launch); echo launcher=\$(kreadconfig6 --file kglobalshortcutsrc --group plasmashell --key \"activate application launcher\"); systemctl --user list-units --no-pager | grep -E \"waybar|hypridle|swaync\" || echo \"no hypr units running in plasma\"'" || true
  shot "plasma-menu-direct"
  gexec 10 "pkill -f bin/cisa-menu; true" >/dev/null 2>&1 || true
  echo "== plasma relogin, then Super"
  gexec 30 "grep -q '^Relogin=' /etc/sddm.conf && sed -i 's/^Relogin=.*/Relogin=true/' /etc/sddm.conf || sed -i '/^\[Autologin\]/a Relogin=true' /etc/sddm.conf; pkill -x plasmashell; systemctl restart sddm; echo restarted" || true
  sleep 15
  for i in $(seq 1 30); do sleep 4; gexec 10 'pgrep -x plasmashell >/dev/null' >/dev/null 2>&1 && break; done
  sleep 20
  echo "sendkey meta_l 150" | socat - UNIX-CONNECT:"$MON" >/dev/null; sleep 5; shot "plasma-menu-relogin"
  gexec 10 "pgrep -af 'bin/cisa-menu' | grep -v pgrep | head -2 || echo 'menu not running'" || true
  gexec 30 "$AS_USER bash -c 'echo launch=\$(kreadconfig6 --file kglobalshortcutsrc --group services --group cisa-menu.desktop --key _launch); pgrep -af bin/cisa-menu | grep -v pgrep || echo \"menu not running\"'" || true
  exit 0
fi

echo "== logging into the Hyprland session"
# live-config writes the Plasma autologin into /etc/sddm.conf, which beats conf.d drop-ins
gexec 60 'grep -rhs "^Session=" /etc/sddm.conf /etc/sddm.conf.d/; sed -i "s/^Session=.*/Session=hyprland.desktop/" /etc/sddm.conf /etc/sddm.conf.d/*.conf 2>/dev/null; grep -rhs "^Session=" /etc/sddm.conf /etc/sddm.conf.d/; systemctl restart sddm; echo restarted'
for i in $(seq 1 30); do sleep 4; gexec 10 'pgrep -f -i "bin/hyprland" >/dev/null && pgrep -x waybar >/dev/null' >/dev/null 2>&1 && break; done
sleep 8
gexec 30 "$HYPR_ENV; echo sig=\$sig wl=\$wl; ps -eo comm,args | grep -iE '^(hyprland|\.?hypr|waybar|swaync|swaybg|hypridle|plasmashell)' | cut -c1-90; echo '-- version:'; runuser -u cisa -- env $USER_ENV HYPRLAND_INSTANCE_SIGNATURE=\$sig hyprctl version | head -2; echo '-- config errors:'; runuser -u cisa -- env $USER_ENV HYPRLAND_INSTANCE_SIGNATURE=\$sig hyprctl configerrors; echo '-- log tail:'; tail -15 /run/user/1000/hypr/\$sig/hyprland.log 2>/dev/null | cut -c1-160" || true
shot "hypr-first-login"
gexec 10 "echo -n 'papirus kali-* icons: '; ls /usr/share/icons/Papirus/48x48/apps 2>/dev/null | grep -c '^kali-'; ls /usr/share/icons/Papirus/48x48/apps | grep -E '^(kali-(nmap|metasploit-framework|ghidra|burpsuite|sqlmap|john|hashcat)|ghidra|burpsuite|btop)\.svg' | tr '\n' ' '; echo" || true
gexec 10 "echo '-- waybar.log:'; echo \"starts: \$(grep -c 'starting waybar' /run/user/1000/waybar.log 2>/dev/null)\"; grep -viE 'info|No batteries|minimum height|^\$' /run/user/1000/waybar.log 2>/dev/null | tail -12" || true
echo "== waybar check"
gexec 40 "$HYPR_ENV; if pgrep -x waybar >/dev/null; then echo 'waybar running'; else echo 'waybar NOT running; starting it to capture errors:'; runuser -u cisa -- env $USER_ENV HYPRLAND_INSTANCE_SIGNATURE=\$sig WAYLAND_DISPLAY=\$wl XDG_CURRENT_DESKTOP=Hyprland timeout 8 waybar 2>&1 | grep -viE 'debug|^\$' | tail -15; fi; grep -i waybar /home/cisa/.local/share/sddm/wayland-session.log 2>/dev/null | tail -5" || true

for th in "${THEMES[@]}"; do
  echo "== theme: $th"
  gexec 300 "$HYPR_USER bash $RICE --theme $th --yes 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E '✓|!|✗|Done'" || echo "  !! rice.sh exited non-zero"
  gexec 20 "$HYPR_USER hyprctl dispatch workspace 1 >/dev/null; pkill -u cisa -x kitty; true" >/dev/null 2>&1 || true
  sleep 2
  gexec 30 "$HYPR_USER cisa-dashboard >/dev/null 2>&1; true" >/dev/null 2>&1 || true
  sleep 6
  shot "theme-$th"
done

echo "== launcher, power menu, lock screen (${THEMES[-1]})"
gexec 10 "$HYPR_USER setsid -f cisa-menu >/dev/null 2>&1; true" >/dev/null; sleep 4; shot "ui-launcher"
gexec 10 "pkill -f bin/cisa-menu; rm -f /run/user/1000/cisa-menu.pid; true" >/dev/null 2>&1 || true
gexec 20 "$HYPR_USER hyprctl dispatch workspace 2 >/dev/null; $HYPR_USER setsid -f kitty bash -c 'cd ~/cisa-rice && ls --color=always && echo && exec bash' >/dev/null 2>&1; true" >/dev/null; sleep 5; shot "ui-terminal"
gexec 10 "$HYPR_USER setsid -f cisa-power >/dev/null 2>&1; true" >/dev/null; sleep 3; shot "ui-power-menu"
gexec 10 "pkill -x wlogout; $HYPR_USER setsid -f cisa-keys >/dev/null 2>&1; true" >/dev/null; sleep 3; shot "ui-keys"
gexec 10 "pkill -x fuzzel; $HYPR_USER setsid -f hyprlock >/dev/null 2>&1; true" >/dev/null; sleep 4; shot "ui-lock"
gexec 20 "$HYPR_ENV; runuser -u cisa -- env $USER_ENV HYPRLAND_INSTANCE_SIGNATURE=\$sig hyprctl configerrors" || true
gexec 10 "pkill -x hyprlock; true" >/dev/null 2>&1 || true

echo "== restore"
gexec 120 "$HYPR_USER bash $RICE --restore 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tail -4; ls /home/cisa/.config | tr '\n' ' '; echo; grep -c cisa-rice /home/cisa/.bashrc || true" || echo "  !! restore failed"
