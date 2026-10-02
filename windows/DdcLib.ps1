# Shared DDC/CI helpers (dxva2). Dot-source from the monitor-*.ps1 scripts:  . "$PSScriptRoot\DdcLib.ps1"
# Windows only.

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
  [DllImport("dxva2.dll")] static extern bool GetVCPFeatureAndVCPFeatureReply(IntPtr h, byte code, out uint type, out uint cur, out uint max);
  [DllImport("dxva2.dll")] static extern bool SetVCPFeature(IntPtr h, byte code, uint val);
  public static List<PHYS> All() {
    var l = new List<PHYS>();
    EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (m,dc,rc,d)=>{ uint n; if(GetNumberOfPhysicalMonitorsFromHMONITOR(m,out n)&&n>0){ var a=new PHYS[n]; if(GetPhysicalMonitorsFromHMONITOR(m,n,a)) l.AddRange(a);} return true; }, IntPtr.Zero);
    return l;
  }
  public static bool Get(IntPtr h, byte c, out uint cur, out uint max){ uint t; return GetVCPFeatureAndVCPFeatureReply(h,c,out t,out cur,out max); }
  public static bool Set(IntPtr h, byte c, uint v){ return SetVCPFeature(h, c, v); }
}
'@
}

# Physical monitor handles go stale when the display re-syncs (PBP/input changes), so look the monitor up on every call.
function Find-DdcMonitor([string]$Match = 'R45w') {
    $mon = [Ddc]::All() | Where-Object { $_.desc -match [regex]::Escape($Match) } | Select-Object -First 1
    if (-not $mon) { throw "No DDC/CI monitor matching '$Match' found." }
    return $mon.h
}

function Set-Vcp([string]$Match, [byte]$Code, [uint32]$Value) {
    if (-not [Ddc]::Set((Find-DdcMonitor $Match), $Code, $Value)) {
        throw ('DDC write failed (0x{0:X2}=0x{1:X}).' -f $Code, $Value)
    }
}

# Returns the current value, or $null if the read failed. Reads fail briefly while the display re-syncs after an
# input/PBP change, so retry for a few seconds.
function Get-Vcp([string]$Match, [byte]$Code, [int]$Retries = 10) {
    for ($i = 0; $i -lt $Retries; $i++) {
        [uint32]$cur = 0; [uint32]$max = 0
        try {
            if ([Ddc]::Get((Find-DdcMonitor $Match), $Code, [ref]$cur, [ref]$max)) { return [int]$cur }
        } catch { }
        Start-Sleep -Milliseconds 400
    }
    return $null
}
