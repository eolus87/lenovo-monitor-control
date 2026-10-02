<#
.SYNOPSIS
  Picture-by-picture on the Lenovo R45w-30 over DDC/CI: USB-C always on the left, a chosen input on the right.

.DESCRIPTION
  VCP 0x60 (input source) packs two sources: low byte = main/left, high byte = sub/right.
  VCP 0xF5 (PBP control) packs: low byte = position (0 off, 1 sub on right, 2 sub on left), high byte = ratio
  (1 = 1:1). This script keeps USB-C1 (0x31) as main, sets the sub source, and turns PBP on at 1:1 with the sub on the right.
  "off" writes 0xF5=0 and leaves the monitor on the main source (USB-C).

.EXAMPLE
  .\monitor-pbp.ps1 dp        # left USB-C, right DisplayPort
  .\monitor-pbp.ps1 hdmi1     # left USB-C, right HDMI 1
  .\monitor-pbp.ps1 hdmi2     # left USB-C, right HDMI 2
  .\monitor-pbp.ps1 off       # single full-screen USB-C
  .\monitor-pbp.ps1 status
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][ValidateSet('dp', 'hdmi1', 'hdmi2', 'off', 'status')][string]$Command,
    [string]$Monitor = 'R45w'
)

. "$PSScriptRoot\DdcLib.ps1"

$USBC1 = 0x31
$Sources = @{ dp = 0x0F; hdmi1 = 0x11; hdmi2 = 0x12 }
$SourceNames = @{ 0x0F = 'dp'; 0x11 = 'hdmi1'; 0x12 = 'hdmi2'; 0x31 = 'usbc' }
$PbpRightHalf = 0x0101   # ratio 1:1, sub window on the right

function Get-Status {
    $f5 = Get-Vcp $Monitor 0xF5
    $in = Get-Vcp $Monitor 0x60
    if ($null -eq $f5 -or $null -eq $in) { throw 'Could not read PBP state from the monitor.' }
    $pos = $f5 -band 0xFF
    $left = $in -band 0xFF
    $right = ($in -shr 8) -band 0xFF
    $name = { param($c) if ($SourceNames.ContainsKey([int]$c)) { $SourceNames[[int]$c] } else { '0x{0:X2}' -f $c } }
    if ($pos -eq 0) { "pbp=off main=$(& $name $left)" }
    else { "pbp=on left=$(& $name $left) right=$(& $name $right) position=$pos ratio=$(($f5 -shr 8) -band 0xFF)" }
}

switch ($Command) {
    'status' { Get-Status }
    'off' {
        Set-Vcp $Monitor 0xF5 0
        Start-Sleep -Milliseconds 800
        Get-Status
    }
    default {
        $value = ($Sources[$Command] -shl 8) -bor $USBC1
        Set-Vcp $Monitor 0x60 $value
        Start-Sleep -Milliseconds 300
        if ((Get-Vcp $Monitor 0xF5) -ne $PbpRightHalf) {
            Set-Vcp $Monitor 0xF5 $PbpRightHalf
            Start-Sleep -Milliseconds 800
        }
        Get-Status
    }
}
