# Lenovo Legion R45w-30 (EDID `LEN67B1`) - control protocol findings

## Key result
Lenovo's app does not use a hidden channel. It uses plain DDC/CI VCP `Set`/`Get` on two vendor codes with an
**index + value** scheme:

1. `SetVCPFeature(0xF8, <feature index>)`  - select a feature
2. `GetVCPFeature(0xF7)` / `SetVCPFeature(0xF7, <value>)` - read / write that feature's value

(Earlier tests wrote to `0xF7` without selecting an index first, hence no effect.)

Source: strings in `LenovoAccessoriesAndDisplayControlCenterService.exe`
(`SetDPSelectState set 0xF8 / 0xF7`, `KVM Switch(0xF7,0xF8)`, `PIP/PBP(0xF2,0xF4,0xF5)`) and
`C:\Program Files\Lenovo\Lenovo Accessories and Display Manager\VCPCodeDef.json` (full index/value table).
`MonitorControl.dll` is only a generic dxva2 wrapper; `OneUpdate.dll` exports `SetKVMPort/SetKVMStatus/SetMonitorPBPMode`.

## 0xF8 feature indexes of interest
| Index | Feature | 0xF7 values |
|---|---|---|
| 0x07 | Enable/disable KVM binding | 0 disabled, 1 enabled |
| 0x0107 / 0x0207 | Set video source + USB source for PC1 / PC2 | 2-byte packed (unknown layout) |
| 0x08 | Switch KVM | write-only action (reads 0/0) - value TBD |
| 0x0B | DP select | 0 DP1.2, 1 DP1.4, 2 DP1.1 |
| 0x0D | USB select | 0 USB2.0, 1 USB3.0, 2 USB3.2 (speed, likely NOT host) |
| 0x14 | eKVM | 0 off, 1 on, 2 keyboard on, 3 mouse on |
| 0x15 | True Split | 0 off, 1 1:1, 3 3:1, 2 1:3, 4 1:1:1 |
| 0x23 | Video source capability query | - |

Direct VCP codes: `0xF5` PBP control (hi/lo byte: position 0 off/1 right/2 left/3 top/4 bottom; ratio 0 off/1 1:1/2 2:1/3 1:2/4 3:1),
`0xF4` PIP size (0-100), `0xF2` PIP/PBP swap (0 disable, 1 swap source, 3 exit full screen).

## Read-only probe on this machine (nothing written except the 0xF8 selector)
| Index | 0xF7 read |
|---|---|
| 0x07 | 0x0001 (KVM binding on) |
| 0x0107 | 0x3131 |
| 0x0207 | 0x510F |
| 0x08 | 0x0000 (max 0) |
| 0x0B | 0x0001 |
| 0x0D | 0x0002 |
| 0x14 | 0x0002 |
| 0x15 | 0x0000 |
| 0x23 | 0x0201 |

VCP `0xF5` = 0x0101, `0xF2` = 0x0000, `0x60` (input) = 0x0F31.

## Confirmed: USB hub switch (2026-10-02)
- Transport is DDC/CI (I2C inside the video cable, via the GPU driver), not USB.
- `0xF8=0x08` then `0xF7=<anything>` **toggles** the hub. Tested `F7=1` and `F7=0`: both toggle, the value does not
  select a port. Works in both directions.
- It can be sent from the PC that does NOT currently own the hub, as long as that PC keeps the video input
  (DDC rides the video cable).
- The monitor offers no readback of hub owner (`0x08` reads 0/0). State is inferred locally instead: the hub's USB
  devices (`VID_17EF&PID_109E/109F`) are present on a PC only while it owns the hub.
- Combining toggle + local presence check gives a real "set" command: see `windows/monitor-usb.ps1` (verified on Windows:
  status/here/away round trip) and `linux/monitor-usb.sh` (Linux, ddcutil, **untested on hardware**).

```powershell
.\monitor.ps1 usb status|here|away|toggle
```

Open caveats:
- DDC reached the monitor from this PC while its own input was hidden (PBP right half switched away), but a PC with
  no video cable connected at all can't send DDC.
- On Linux, ddcutil may need `--force-unrecognized-vcp-codes` or different display selection (`DDC_DISPLAY=<n>`).

## Confirmed: PBP (2026-10-02)
- **VCP 0x60 (input source) is two bytes**: low byte = main/left source, high byte = sub/right source.
  Codes: 0x31 USB-C1, 0x0F DP1, 0x11 HDMI1, 0x12 HDMI2. Writing `0x1131` gave left USB-C / right HDMI1, `0x1231` right
  HDMI2, `0x0F31` right DP; left stayed on USB-C each time (observed on screen).
- **VCP 0xF5 (PBP control) is two bytes**: low byte = position (0 off, 1 sub on right, 2 sub on left), high byte = ratio
  (1 = 1:1). Max reply 0x0402 suggests only left/right positions on this model. `0xF5=0x0101` = right sub window 1:1;
  `0xF5=0` turned PBP off, leaving only the main source (USB-C) full screen. Writing `0xF5=0x0101` again turned it on.
- Monitor handles go stale and reads fail (`ERR`) for a second or two while the display re-syncs after input/PBP changes;
  writes still succeed. Re-enumerate the monitor and retry reads.
- DDC writes work from a PC whose input is not currently displayed (restored DP after the right half left this PC).
- Scripts: `windows/monitor-pbp.ps1` (verified: dp/hdmi1/hdmi2/off/status), `linux/monitor-pbp.sh` (untested on hardware).
- Not tested: ratios other than 1:1, sub window on the left, `0xF2` swap, `0xF4` PIP size, `0xF1` PIP/PBP colour preset,
  `0xF8=0x15` True Split.

## Confirmed: True Split (2026-10-02)
True Split = one source (USB-C1) fed to both halves of the screen (two virtual displays from one PC), as opposed to PBP
where two PCs share the screen.
- Capabilities string lists index 0x15 for 0xF7/0xF8, so the model supports it. Full capabilities string (for reference):
  `cmds(01 02 03 07 0C E3 F3)`, `0x60` accepts `0F 11 12 31 FF` (DP1, HDMI1, HDMI2, USB-C1, Auto), `F0` audio source
  accepts the same four, `F8/F7` indexes `01 02 04 07 08 09 0A 0B 0D 15 1A`, `mccs_ver(2.2)`.
- `0xF8=0x15`, then `0xF7`: **0 off, 1 equal halves, 2 uneven**. **3 is rejected** (reads back 0).
- Writing 1 or 2 makes the monitor set PBP itself: `0xF5` = 0x0101 (equal) / 0x0401 (value 2, ratio byte 4) and
  `0x60` = 0x3131 (both halves USB-C1). That also explains the 0x3131 read from index 0x0107 (PC1 video+USB source = USB-C1).
- The write is **ignored while PBP is active**: PBP must be turned off first (`0xF5=0`).
- Writing 0 turns True Split off **and leaves PBP off** (`0xF5=0`, `0x60=0x0031`, USB-C full screen). It does not restore
  the previous PBP layout - re-apply it with `monitor-pbp.ps1`.
- Writes are sometimes dropped while the display re-syncs (one "off" silently failed), so the script verifies each write
  by reading it back and retries.
- While True Split was on, Windows on the DP PC kept seeing a single 2560x1440 screen (it is not the displayed source).
  With PBP off, that PC sees 5120x1440 (the monitor's native size).
- Script: `windows/monitor-split.ps1 equal|uneven|off|status` (`off -Then dp|hdmi1|hdmi2` returns to PBP). Verified: equal, off,
  off+dp, status. Not verified: which half is wider in "uneven" (1:3 vs 3:1), what the USB-C PC sees (expected: two
  displays), the Linux version (`linux/monitor-split.sh`, only run against a fake ddcutil).

## Not done / next
- 0x0107 / 0x0207 (video source + USB source per PC) deliberately NOT written: a wrong value could switch the video
  input away from the PC. Readings: PC1=0x3131, PC2=0x510F (low byte 0x0F = standard DP1 code; layout still a guess).
- Watch the "uneven" True Split and PBP ratios (`0xF5` high byte 2, 3, 4) to see which half is wider; test the left-side
  sub window (`0xF5` low byte 2); `0xF2` swap; `0xF4` PIP size.
- Run the Linux scripts on real hardware. Unknowns: exact `ddcutil --terse getvcp` output for vendor codes `0xF5/0xF7/0x60`
  (parsed in `linux/lib.sh:get_vcp`), whether `ddcutil` needs `--force-unrecognized-vcp-codes` for `0xF7/0xF8`, and
  `--model R45w-30` auto-detection.
