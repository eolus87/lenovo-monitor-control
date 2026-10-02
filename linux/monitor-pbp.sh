#!/usr/bin/env bash
# PBP on the Lenovo R45w-30 over DDC/CI (Linux; needs ddcutil): USB-C always on the left, chosen input on the right.
# NOT YET TESTED on Linux - the PowerShell version (windows/monitor-pbp.ps1) is the verified one.
#
# VCP 0x60 packs two sources: low byte = main/left, high byte = sub/right (USB-C1 0x31, DP1 0x0F, HDMI1 0x11, HDMI2 0x12).
# VCP 0xF5 packs: low byte = position (0 off, 1 sub on right, 2 sub on left), high byte = ratio (1 = 1:1).
#
# usage: monitor-pbp.sh dp|hdmi1|hdmi2|off|status
# env:   DDC_DISPLAY=<n>   ddcutil display number (default: auto-detect by model "R45w-30")
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

cmd="${1:-}"
USBC1=0x31
PBP_RIGHT_HALF=0x0101

name() { case "$1" in 15) echo dp ;; 17) echo hdmi1 ;; 18) echo hdmi2 ;; 49) echo usbc ;; *) printf '0x%02X\n' "$1" ;; esac; }

status() {
  local f5 in pos
  f5="$(get_vcp 0xF5)" && in="$(get_vcp 0x60)" || { echo "Could not read PBP state from the monitor." >&2; return 1; }
  pos=$((f5 & 0xFF))
  if ((pos == 0)); then echo "pbp=off main=$(name $((in & 0xFF)))"
  else echo "pbp=on left=$(name $((in & 0xFF))) right=$(name $(((in >> 8) & 0xFF))) position=$pos ratio=$(((f5 >> 8) & 0xFF))"; fi
}

case "$cmd" in
  status) status ;;
  off) set_vcp 0xF5 0; sleep 0.8; status ;;
  dp | hdmi1 | hdmi2)
    case "$cmd" in dp) right=0x0F ;; hdmi1) right=0x11 ;; hdmi2) right=0x12 ;; esac
    set_vcp 0x60 "$(printf '0x%04X' $(((right << 8) | USBC1)))"
    sleep 0.3
    if [[ "$(get_vcp 0xF5 || echo -1)" != "$((PBP_RIGHT_HALF))" ]]; then
      set_vcp 0xF5 "$PBP_RIGHT_HALF"; sleep 0.8
    fi
    status ;;
  *) echo "usage: $0 dp|hdmi1|hdmi2|off|status" >&2; exit 2 ;;
esac
