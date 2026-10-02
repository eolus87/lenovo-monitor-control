#!/usr/bin/env bash
# Switch the Lenovo R45w-30 USB hub between PCs over DDC/CI (Linux; needs ddcutil + lsusb).
# NOT YET TESTED on Linux - the PowerShell version is the verified one.
#
# Sends VCP 0xF8=0x08 (select "Switch KVM") then 0xF7=1. The monitor treats any write as a toggle, so state is
# read locally: the hub (USB 17ef:109e / 17ef:109f) is present only while this PC owns it.
#
# usage: monitor-usb.sh status|here|away|toggle
# env:   DDC_DISPLAY=<n>   ddcutil display number (default: auto-detect by model "R45w")
#        TIMEOUT=<sec>     wait for the hub to (dis)appear after a switch (default 15)
set -euo pipefail

cmd="${1:-}"
TIMEOUT="${TIMEOUT:-15}"

hub_here() { lsusb -d 17ef:109e >/dev/null 2>&1 || lsusb -d 17ef:109f >/dev/null 2>&1; }
state() { if hub_here; then echo here; else echo away; fi; }

display_arg() {
  if [[ -n "${DDC_DISPLAY:-}" ]]; then echo "--display $DDC_DISPLAY"; else echo "--model R45w-30"; fi
}

send_toggle() {
  # shellcheck disable=SC2046
  ddcutil $(display_arg) --noverify setvcp 0xF8 0x08
  sleep 0.15
  # shellcheck disable=SC2046
  ddcutil $(display_arg) --noverify setvcp 0xF7 1
}

switch_and_verify() { # $1 = want "here" or "away"
  send_toggle
  for ((i = 0; i < TIMEOUT * 2; i++)); do
    sleep 0.5
    [[ "$(state)" == "$1" ]] && { echo "$1"; return 0; }
  done
  echo "Sent switch but hub is still '$(state)'." >&2
  return 1
}

case "$cmd" in
  status) state ;;
  here | away) if [[ "$(state)" == "$cmd" ]]; then echo "$cmd"; else switch_and_verify "$cmd"; fi ;;
  toggle) if [[ "$(state)" == here ]]; then switch_and_verify away; else switch_and_verify here; fi ;;
  *) echo "usage: $0 status|here|away|toggle" >&2; exit 2 ;;
esac
