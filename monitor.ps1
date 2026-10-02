<#
.SYNOPSIS
  Entry point (Windows) for controlling the Lenovo Legion R45w-30 over DDC/CI. Dispatches to windows\monitor-<feature>.ps1.

.EXAMPLE
  .\monitor.ps1 usb status|here|away|toggle
  .\monitor.ps1 pbp dp|hdmi1|hdmi2|off|status
  .\monitor.ps1 split equal|uneven|off|status
  .\monitor.ps1 split off -Then dp      # True Split off, then PBP with USB-C left and DisplayPort right
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][ValidateSet('usb', 'pbp', 'split')][string]$Feature,
    [Parameter(Mandatory, Position = 1)][string]$Command,
    [ValidateSet('none', 'dp', 'hdmi1', 'hdmi2')][string]$Then,   # split only
    [string]$Monitor,                                             # substring of the monitor name (default R45w)
    [int]$TimeoutSec                                              # usb only
)

$forward = @{ Command = $Command }
foreach ($name in 'Then', 'Monitor', 'TimeoutSec') {
    if ($PSBoundParameters.ContainsKey($name)) { $forward[$name] = $PSBoundParameters[$name] }
}
if ($Feature -ne 'split') { $forward.Remove('Then') }
if ($Feature -ne 'usb') { $forward.Remove('TimeoutSec') }

& "$PSScriptRoot\windows\monitor-$Feature.ps1" @forward
exit $LASTEXITCODE
