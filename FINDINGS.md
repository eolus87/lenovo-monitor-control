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
- Combining toggle + local presence check gives a real "set" command: see `monitor-usb.ps1` (verified on Windows:
  status/here/away round trip) and `monitor-usb.sh` (Linux, ddcutil, **untested**).

```powershell
.\monitor-usb.ps1 status|here|away|toggle
```

Open caveats:
- A PC that is NOT the video source for the monitor can't be assumed to reach DDC (untested).
- On Linux, ddcutil may need `--force-unrecognized-vcp-codes` or different display selection (`DDC_DISPLAY=<n>`).

## Not done / next
- 0x0107 / 0x0207 (video source + USB source per PC) deliberately NOT written: a wrong value could switch the video
  input away from the PC. Readings: PC1=0x3131, PC2=0x510F (low byte 0x0F = standard DP1 code; layout still a guess).
- Test True Split (`0xF8=0x15`, then `0xF7` 1..4) and PBP (`0xF5`, packed position/ratio) the same way.
