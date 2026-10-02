<#
.SYNOPSIS
  Switch the Lenovo R45w-30 USB hub between PCs over DDC/CI (no Lenovo app needed).

.DESCRIPTION
  Sends VCP 0xF8=0x08 (select "Switch KVM") then 0xF7=1 via dxva2. The monitor treats any write as a toggle,
  so state is read locally: the monitor's hub (USB VID_17EF PID_109E/109F) is present on this PC only while
  this PC owns the hub. "here"/"away" toggle only when needed and verify the result.

.EXAMPLE
  .\monitor-usb.ps1 status      # prints "here" or "away"
  .\monitor-usb.ps1 here        # make this PC own the hub
  .\monitor-usb.ps1 away        # give the hub to the other PC
  .\monitor-usb.ps1 toggle
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][ValidateSet('status', 'here', 'away', 'toggle')][string]$Command,
    [string]$Monitor = 'R45w',      # substring of the physical monitor description
    [int]$TimeoutSec = 15           # how long to wait for the hub to (dis)appear after a switch
)

if (-not ('Ddc' -as [type])) {
    Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class Ddc {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct PHYS { public IntPtr h; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string desc; }
  delegate bool EnumProc(IntPtr hMon, IntPtr hdc, IntPtr rc, IntPtr d);
  [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr a, IntPtr b, EnumProc p, IntPtr d);
  [DllImport("dxva2.dll")] static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr m, out uint n);
  [DllImport("dxva2.dll")] static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr m, uint n, [Out] PHYS[] a);
  [DllImport("dxva2.dll")] static extern bool SetVCPFeature(IntPtr h, byte code, uint val);
  public static List<PHYS> All() {
    var l = new List<PHYS>();
    EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (m,dc,rc,d)=>{ uint n; if(GetNumberOfPhysicalMonitorsFromHMONITOR(m,out n)&&n>0){ var a=new PHYS[n]; if(GetPhysicalMonitorsFromHMONITOR(m,n,a)) l.AddRange(a);} return true; }, IntPtr.Zero);
    return l;
  }
  public static bool Set(IntPtr h, byte c, uint v){ return SetVCPFeature(h, c, v); }
}
'@
}

function Test-HubHere {
    $found = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match 'USB\\VID_17EF&PID_109[EF]\\' }
    return [bool]$found
}

function Send-Toggle {
    $mon = [Ddc]::All() | Where-Object { $_.desc -match [regex]::Escape($Monitor) } | Select-Object -First 1
    if (-not $mon) { throw "No DDC/CI monitor matching '$Monitor' found." }
    if (-not [Ddc]::Set($mon.h, 0xF8, 0x08)) { throw 'DDC write failed (0xF8=0x08).' }
    Start-Sleep -Milliseconds 150
    if (-not [Ddc]::Set($mon.h, 0xF7, 1)) { throw 'DDC write failed (0xF7=1).' }
}

function Switch-AndVerify([bool]$wantHere) {
    Send-Toggle
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        if ((Test-HubHere) -eq $wantHere) { return $true }
    }
    return $false
}

function Get-StateName { if (Test-HubHere) { 'here' } else { 'away' } }

$isHere = Test-HubHere
switch ($Command) {
    'status' { Get-StateName; break }
    { $_ -in 'here', 'away' } {
        $wantHere = $Command -eq 'here'
        if ($isHere -eq $wantHere) { Get-StateName; break }   # already in desired state
        if (Switch-AndVerify $wantHere) { Get-StateName } else { Write-Error "Sent switch but hub is still '$(Get-StateName)'."; exit 1 }
        break
    }
    'toggle' {
        if (Switch-AndVerify (-not $isHere)) { Get-StateName } else { Write-Error "Sent switch but state is still '$(Get-StateName)'."; exit 1 }
    }
}
