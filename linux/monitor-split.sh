#!/usr/bin/env bash
# True Split on the Lenovo R45w-30 over DDC/CI (Linux; needs ddcutil): one source (USB-C) fed to both halves.
# NOT YET TESTED on Linux - the PowerShell version (windows/monitor-split.ps1) is the verified one.
#
# VCP 0xF8=0x15 selects "True Split", then VCP 0xF7 holds the layout: 0 off, 1 equal halves, 2 uneven (3 is rejected).
# The monitor ignores it while PBP is active, so PBP is turned off first. Turning it off leaves PBP off, so
# "off <dp|hdmi1|hdmi2>" goes straight back to a PBP layout. Every write is read back and retried.
#
# usage: monitor-split.sh equal|uneven|off [dp|hdmi1|hdmi2]|status
# env:   DDC_DISPLAY=<n>   ddcutil display number (default: auto-detect by model "R45w-30")
set -euo pipefail
dir="$(dirname "$0")"
# shellcheck source=lib.sh
. "$dir/lib.sh"

cmd="${1:-}"
then="${2:-none}"

# Write the True Split value and wait until the monitor reports it. Writes can be dropped while the display re-syncs.
set_truesplit() {
  local want="$1" try
  for ((try = 0; try < 6; try++)); do
    { set_vcp 0xF8 0x15 && sleep 0.3 && set_vcp 0xF7 "$want"; } || true
    sleep 3
    [[ "$(get_truesplit || echo -1)" == "$want" ]] && return 0
  done
  echo "True Split did not reach value $want." >&2
  return 1
}

status() {
  local ts f5 in label
  ts="$(get_truesplit)"; f5="$(get_vcp 0xF5)"; in="$(get_vcp 0x60)"
  case "$ts" in 0) label=off ;; 1) label=equal ;; 2) label=uneven ;; *) label="$ts" ;; esac
  printf 'truesplit=%s pbp_raw=0x%04X input_raw=0x%04X\n' "$label" "$f5" "$in"
}

case "$cmd" in
  status) status ;;
  off)
    case "$then" in none | dp | hdmi1 | hdmi2) ;; *) echo "usage: $0 off [dp|hdmi1|hdmi2]" >&2; exit 2 ;; esac
    set_truesplit 0
    if [[ "$then" == none ]]; then status; else "$dir/monitor-pbp.sh" "$then"; fi ;;
  equal | uneven)
    [[ "$(get_truesplit || echo -1)" != 0 ]] && set_truesplit 0   # re-apply from a clean state
    set_vcp 0xF5 0; sleep 3                                        # PBP must be off first
    if [[ "$cmd" == equal ]]; then set_truesplit 1; else set_truesplit 2; fi
    status ;;
  *) echo "usage: $0 equal|uneven|off [dp|hdmi1|hdmi2]|status" >&2; exit 2 ;;
esac
