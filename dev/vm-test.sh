#!/usr/bin/env bash
# Boot the CISA Linux ISO in QEMU/KVM, copy this repo in, apply every theme as the live user,
# and screenshot each one to dev/vm-shots/. Run as root inside WSL/Linux:
#   bash dev/vm-test.sh [path/to/cisa-linux.iso] [theme ...]
set -euo pipefail
cd "$(dirname "$0")/.."
ISO="${1:-../cisa-linux/out/cisa-linux-2026.10-amd64.iso}"; shift || true
THEMES=("$@"); [[ ${#THEMES[@]} -eq 0 ]] && mapfile -t THEMES < <(ls themes | sed 's/\.theme$//')
OUT=dev/vm-shots; mkdir -p "$OUT"
T=/var/tmp/cisa-rice-vm; mkdir -p "$T"; MON="$T/mon.sock"; QGA="$T/qga.sock"; rm -f "$MON" "$QGA"

qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m 6144 -cdrom "$ISO" -boot d -vga virtio -display none \
  -nic user,model=virtio-net-pci \
  -monitor unix:"$MON",server,nowait \
  -chardev socket,path="$QGA",server=on,wait=off,id=qga0 \
  -device virtio-serial -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0 &
QPID=$!; trap 'kill $QPID 2>/dev/null || true' EXIT

qga() {
  local id=$RANDOM
  { printf '{"execute":"guest-sync","arguments":{"id":%d}}\n%s\n' "$id" "$1"; sleep "${2:-2}"; } \
    | socat -t10 - UNIX-CONNECT:"$QGA" | grep -vE "\"return\": ?$id\}" | tail -1 || true
}
# gexec <timeout-seconds> <shell command> [stdin-file]  — runs as root in the guest, waits, prints output
gexec() {
  local to=$1 cmd=$2 input=${3:-} req pid st i
  if [[ -n $input ]]; then
    base64 -w0 "$input" > "$T/input.b64"
    req=$(jq -cn --arg c "$cmd" --rawfile in "$T/input.b64" \
      '{execute:"guest-exec",arguments:{path:"/bin/bash",arg:["-c",$c],"input-data":$in,"capture-output":true}}')
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

AS_USER='runuser -u cisa -- env HOME=/home/cisa USER=cisa XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus WAYLAND_DISPLAY=wayland-0 DISPLAY=:0 XDG_CURRENT_DESKTOP=KDE XDG_SESSION_TYPE=wayland QT_QPA_PLATFORM=wayland'

echo "== waiting for desktop"
for i in $(seq 1 60); do
  sleep 5
  [[ $(qga '{"execute":"guest-ping"}') == *return* ]] && gexec 10 'pgrep -x plasmashell >/dev/null' >/dev/null 2>&1 && break
done
sleep 15
gexec 10 'pkill -f firefox-esr || true' >/dev/null 2>&1 || true

echo "== uploading repo"
tar czf "$T/repo.tgz" --exclude=dev/previews --exclude=dev/vm-shots .
gexec 30 'mkdir -p /home/cisa/cisa-rice && tar xzf - -C /home/cisa/cisa-rice && chown -R cisa:cisa /home/cisa/cisa-rice && echo uploaded' "$T/repo.tgz"

for th in "${THEMES[@]}"; do
  echo "== theme: $th"
  gexec 600 "$AS_USER bash /home/cisa/cisa-rice/rice.sh --theme $th --yes 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tail -14" || echo "  !! rice.sh exited non-zero"
  gexec 10 'pkill -x konsole; pkill -x dolphin; true' >/dev/null 2>&1 || true
  sleep 3
  gexec 10 "$AS_USER setsid -f dolphin /home/cisa >/dev/null 2>&1; sleep 2; $AS_USER setsid -f konsole >/dev/null 2>&1; true" >/dev/null 2>&1 || true
  sleep 9
  shot "theme-$th"
done

echo "== restore"
gexec 120 "$AS_USER bash /home/cisa/cisa-rice/rice.sh --restore 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tail -5" || true
gexec 10 'pkill -x konsole; pkill -x dolphin; true' >/dev/null 2>&1 || true
sleep 12; shot "restored"
