$ErrorActionPreference = 'Stop'
# Independent OS probe: this program neither loads nor references DeviceReadout.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ReadoutMemoryProbe {
    [StructLayout(LayoutKind.Sequential)]
    public struct Status {
        public uint Length, Load;
        public ulong TotalPhysical, AvailablePhysical, TotalPageFile, AvailablePageFile;
        public ulong TotalVirtual, AvailableVirtual, AvailableExtendedVirtual;
    }
    [DllImport("kernel32.dll")] public static extern bool GlobalMemoryStatusEx(ref Status value);
    [DllImport("kernel32.dll")] public static extern bool GetPhysicallyInstalledSystemMemory(out ulong kibibytes);
    [DllImport("kernel32.dll")] public static extern IntPtr CreateMemoryResourceNotification(int kind);
    [DllImport("kernel32.dll")] public static extern bool QueryMemoryResourceNotification(IntPtr handle, out bool state);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr handle);
}
'@
$status = New-Object ReadoutMemoryProbe+Status
$status.Length = [Runtime.InteropServices.Marshal]::SizeOf($status)
if (-not [ReadoutMemoryProbe]::GlobalMemoryStatusEx([ref]$status)) { throw 'Independent memory status query failed.' }
[UInt64]$installedKiB = 0
$physical = if ([ReadoutMemoryProbe]::GetPhysicallyInstalledSystemMemory([ref]$installedKiB)) { ([UInt64]($installedKiB * 1024)).ToString() } else { $null }
$lowMemory = $null
$notification = [ReadoutMemoryProbe]::CreateMemoryResourceNotification(0)
if ($notification -ne [IntPtr]::Zero) {
    try {
        $state = $false
        if ([ReadoutMemoryProbe]::QueryMemoryResourceNotification($notification, [ref]$state)) { $lowMemory = $state }
    } finally {
        if (-not [ReadoutMemoryProbe]::CloseHandle($notification)) { throw 'Independent notification cleanup failed.' }
    }
}
[ordered]@{
    physicalBytes = $physical
    kernelAccessibleBytes = $status.TotalPhysical.ToString()
    availableBytes = $status.AvailablePhysical.ToString()
    lowMemory = $lowMemory
} | ConvertTo-Json -Compress
