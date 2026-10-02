# lenovo-monitor-control

Control a Lenovo Legion R45w-30 from the command line over DDC/CI, without Lenovo's Display Control Center app.

Currently supported: switching the monitor's built-in USB hub between two PCs. True Split and PBP are next.

## USB hub switch

The monitor only offers a toggle and cannot report who owns the hub. The scripts work around that by checking locally
whether the hub's USB devices (`17ef:109e` / `17ef:109f`) are present on this PC, and toggling only when needed.

### Windows (verified)

```powershell
.\monitor-usb.ps1 status   # prints "here" or "away"
.\monitor-usb.ps1 here     # make this PC own the hub
.\monitor-usb.ps1 away     # hand the hub to the other PC
.\monitor-usb.ps1 toggle
```

Needs no extra software. Use `-Monitor <text>` to match a different monitor description (default `R45w`) and
`-TimeoutSec` to change how long it waits for the switch to take effect (default 15).

### Linux (untested)

```bash
./monitor-usb.sh status|here|away|toggle
```

Needs `ddcutil` and `lsusb`. Set `DDC_DISPLAY=<n>` if auto-detection by model fails.

## How it works

Two standard DDC/CI VCP writes on Lenovo vendor codes:

1. `0xF8 = 0x08` selects the "Switch KVM" feature.
2. `0xF7 = 1` triggers it. Any value toggles.

The transport is DDC/CI over the video cable, not USB, so the command works from whichever PC is feeding the monitor
video, even if it doesn't currently own the hub. See [FINDINGS.md](FINDINGS.md) for the full index table, probe results,
and how the protocol was found.

## Caveats

- Writes to the wrong VCP codes can change monitor settings. Only the codes documented in `FINDINGS.md` have been tested.
- Whether a PC that isn't the video source can send the command is untested.
