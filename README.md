# lenovo-monitor-control

Control a Lenovo Legion R45w-30 from the command line over DDC/CI, without Lenovo's Display Control Center app.

- **USB hub**: switch the monitor's built-in USB hub between two PCs.
- **PBP**: USB-C always on the left, DisplayPort / HDMI 1 / HDMI 2 on the right.
- **True Split**: feed one source (USB-C) to both halves of the screen, equal or uneven.

| | Windows (PowerShell) | Linux (bash + ddcutil) |
|---|---|---|
| Entry point | `.\monitor.ps1` | `./monitor.sh` |
| Scripts | `windows/` | `linux/` |
| Status | **verified** on this monitor | written, only tested against a fake `ddcutil` - **not tried on real hardware** |

## Usage

Same commands on both platforms (`.\monitor.ps1 ...` on Windows, `./monitor.sh ...` on Linux):

```
monitor usb   status | here | away | toggle
monitor pbp   dp | hdmi1 | hdmi2 | off | status
monitor split equal | uneven | off | status
```

Windows: `.\monitor.ps1 split off -Then dp` &nbsp;|&nbsp; Linux: `./monitor.sh split off dp`
(turn True Split off and go straight back to PBP).

### USB hub

The monitor only offers a toggle and cannot report who owns the hub. The scripts work around that by checking locally
whether the hub's USB devices (`17ef:109e` / `17ef:109f`) are present on this PC, and toggling only when needed, then
waiting for the hub to (dis)appear to confirm. `status` prints `here` or `away`.

### PBP (picture by picture)

USB-C is always the left half; you choose what goes on the right. Both halves are 1:1.
`status` prints e.g. `pbp=on left=usbc right=dp position=1 ratio=1`. `off` leaves the monitor on USB-C only.

### True Split

One source (USB-C) feeds both halves, as two virtual displays. Turning it on first turns PBP off (the monitor ignores
True Split while PBP is active), and turning it off leaves PBP off, so use `-Then` / the extra argument to go straight back
to a PBP layout. Every write is read back and retried, because the monitor sometimes drops writes while the display re-syncs.

## Requirements

- **Windows**: nothing extra (uses `dxva2.dll`). PowerShell 5.1 or 7.
- **Linux**: `ddcutil` (with `i2c-dev` loaded and permission to `/dev/i2c-*`) and `lsusb`. Set `DDC_DISPLAY=<n>` if
  auto-detection by model name fails; if `ddcutil` refuses the vendor codes, try adding `--force-unrecognized-vcp-codes`
  to `ddc()` in `linux/lib.sh`.

## How it works

Everything is plain DDC/CI VCP `Set`/`Get`, carried by the video cable (not USB), so the commands work from any PC with a
video connection to the monitor, even if its input isn't currently displayed.

- USB hub: `0xF8=0x08` then `0xF7=1` (any value toggles).
- PBP: `0x60` holds both sources (low byte left, high byte right: `0x31` USB-C1, `0x0F` DP1, `0x11` HDMI1, `0x12` HDMI2) and
  `0xF5` holds position (low byte) and ratio (high byte).
- True Split: `0xF8=0x15` then `0xF7`: 0 off, 1 equal, 2 uneven.

`0xF8` selects a feature index and `0xF7` reads/writes its value - that is Lenovo's vendor scheme. See
[FINDINGS.md](FINDINGS.md) for the full index table, probe results and how it was found.

## Caveats

- Writes to the wrong VCP codes can change monitor settings. Only the codes documented in `FINDINGS.md` have been tested.
- Right after an input/PBP change the display re-syncs and DDC reads fail for a moment; the scripts retry.
- Only run from a PC on DisplayPort has been tested. USB-C, HDMI and docks/adapters may differ (some drop DDC).
- Which half is wider in `split uneven` is not yet recorded.

## Layout

```
monitor.ps1  monitor.sh        entry points
windows/   DdcLib.ps1 monitor-usb.ps1 monitor-pbp.ps1 monitor-split.ps1
linux/     lib.sh monitor-usb.sh monitor-pbp.sh monitor-split.sh
FINDINGS.md                    protocol notes and test log
```
