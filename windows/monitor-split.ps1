<#
.SYNOPSIS
  True Split on the Lenovo R45w-30 over DDC/CI: one source (USB-C) fed to both halves of the screen, as two virtual displays.

.DESCRIPTION
  Uses the indexed vendor channel: VCP 0xF8 = 0x15 selects "True Split", then VCP 0xF7 holds the layout
  (0 off, 1 equal halves, 2 uneven). 3 is rejected by this monitor. Turning True Split on makes the monitor switch PBP on
  with both halves on USB-C1; it is ignored while PBP is active, so PBP is turned off first. Turning it off leaves PBP off
  (USB-C full screen), so use -Then to go straight back to a PBP layout.
  Every write is verified by reading it back and retried if it did not land.

.EXAMPLE
  .\monitor-split.ps1 equal            # two equal halves of the USB-C source
  .\monitor-split.ps1 uneven           # uneven split (which half is wider: see FINDINGS.md)
  .\monitor-split.ps1 off              # back to a single full-screen USB-C
  .\monitor-split.ps1 off -Then dp     # off, then PBP with USB-C left and DisplayPort right
  .\monitor-split.ps1 status
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][ValidateSet('equal', 'uneven', 'off', 'status')][string]$Command,
    [ValidateSet('none', 'dp', 'hdmi1', 'hdmi2')][string]$Then = 'none',
    [string]$Monitor = 'R45w'
)

. "$PSScriptRoot\DdcLib.ps1"

$Layouts = @{ off = 0; equal = 1; uneven = 2 }

function Get-TrueSplit {
    Set-Vcp $Monitor 0xF8 0x15
    Start-Sleep -Milliseconds 300
    return Get-Vcp $Monitor 0xF7
}

# Write the True Split value and wait until the monitor reports it. Writes can be dropped while the display re-syncs.
function Set-TrueSplit([int]$Value) {
    for ($try = 0; $try -lt 6; $try++) {
        try {
            Set-Vcp $Monitor 0xF8 0x15
            Start-Sleep -Milliseconds 300
            Set-Vcp $Monitor 0xF7 $Value
        } catch { }
        Start-Sleep -Seconds 3
        if ((Get-TrueSplit) -eq $Value) { return }
    }
    throw "True Split did not reach value $Value."
}

function Get-Status {
    $ts = Get-TrueSplit
    $f5 = Get-Vcp $Monitor 0xF5
    $in = Get-Vcp $Monitor 0x60
    $label = switch ($ts) { 0 { 'off' } 1 { 'equal' } 2 { 'uneven' } default { "0x{0:X}" -f $ts } }
    "truesplit=$label pbp_raw=0x{0:X4} input_raw=0x{1:X4}" -f $f5, $in
}

switch ($Command) {
    'status' { Get-Status }
    'off' {
        Set-TrueSplit 0
        if ($Then -ne 'none') { & "$PSScriptRoot\monitor-pbp.ps1" $Then } else { Get-Status }
    }
    default {
        if ((Get-TrueSplit) -ne 0) { Set-TrueSplit 0 }                 # re-apply from a clean state
        Set-Vcp $Monitor 0xF5 0; Start-Sleep -Seconds 3                 # PBP must be off first
        Set-TrueSplit $Layouts[$Command]
        Get-Status
    }
}
