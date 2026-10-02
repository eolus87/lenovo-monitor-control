#!/usr/bin/env bash
# Shared DDC/CI helpers (ddcutil) for the monitor-*.sh scripts. Source it:  . "$(dirname "$0")/lib.sh"
# NOT YET TESTED on Linux - the Windows scripts are the verified reference.
#
# env: DDC_DISPLAY=<n>   ddcutil display number (default: auto-detect by model "R45w-30")

ddc() {
  if [[ -n "${DDC_DISPLAY:-}" ]]; then ddcutil --display "$DDC_DISPLAY" "$@"; else ddcutil --model R45w-30 "$@"; fi
}

set_vcp() { ddc --noverify setvcp "$1" "$2"; }   # --noverify: 0xF8 is write-only, so ddcutil's read-back would fail

# Print the current value of a VCP code as an integer. Retries for a few seconds because reads fail while the display
# re-syncs after an input/PBP change. Handles terse "VCP 60 SNC x0f x31" (hex bytes, last = low) and "VCP 10 C 50 100".
get_vcp() {
  local line type sh sl
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if line="$(ddc --terse getvcp "$1" 2>/dev/null)" && [[ "$line" == VCP* ]]; then
      type="$(awk '{print $3}' <<<"$line")"
      if [[ "$type" == C ]]; then awk '{print $4}' <<<"$line"; return 0; fi
      sl="$(awk '{print $NF}' <<<"$line")"
      sh="$(awk '{ if (NF >= 5) print $(NF-1); else print "x00" }' <<<"$line")"
      echo $(((16#${sh#x} << 8) | 16#${sl#x}))
      return 0
    fi
    sleep 0.4
  done
  return 1
}

# True Split lives behind the indexed channel: select index 0x15 on 0xF8, then use 0xF7.
get_truesplit() { set_vcp 0xF8 0x15 && sleep 0.3 && get_vcp 0xF7; }
