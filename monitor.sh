#!/usr/bin/env bash
# Entry point (Linux) for controlling the Lenovo Legion R45w-30 over DDC/CI. Dispatches to linux/monitor-<feature>.sh.
# NOT YET TESTED on Linux.
#
#   ./monitor.sh usb   status|here|away|toggle
#   ./monitor.sh pbp   dp|hdmi1|hdmi2|off|status
#   ./monitor.sh split equal|uneven|off [dp|hdmi1|hdmi2]|status
set -euo pipefail

feature="${1:-}"
case "$feature" in
  usb | pbp | split) shift; exec "$(dirname "$0")/linux/monitor-$feature.sh" "$@" ;;
  *) echo "usage: $0 usb|pbp|split <command>   (see README.md)" >&2; exit 2 ;;
esac
