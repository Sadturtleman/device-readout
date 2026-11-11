using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;

namespace DeviceReadout.Windows;

internal interface IWindowsCpuPlatform
{
    int PointerSize => IntPtr.Size;
    bool AffinityMasksReliable => true;
    byte[] Topology(CancellationToken token);
    byte[]? PowerInformation(int count, CancellationToken token) => null;
}

[SupportedOSPlatform("windows")]
internal sealed class WindowsCpuPlatform : IWindowsCpuPlatform
{
    public bool AffinityMasksReliable => Environment.Is64BitProcess || !Environment.Is64BitOperatingSystem;
    public byte[]? PowerInformation(int count, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        var output = new byte[checked(count * 24)];
        var status = CallNtPowerInformation(11, 0, 0, output, (uint)output.Length);
        token.ThrowIfCancellationRequested();return status == 0 ? output : null;
    }
    public byte[] Topology(CancellationToken token)
    {
        token.ThrowIfCancellationRequested();uint length = 0;
        if (GetLogicalProcessorInformationEx(0xffff, null, ref length)) throw new DeviceReadoutException(ErrorCode.ReadFailed, "Unexpected empty topology response.");
        var error = Marshal.GetLastPInvokeError();
        if (error != 122) throw new Win32Exception(error);
        for (var attempt = 0; attempt < 3; attempt++) {
            token.ThrowIfCancellationRequested();
            if (length is < 8 or > 8 * 1024 * 1024) throw new DeviceReadoutException(ErrorCode.ReadFailed, "Invalid CPU topology buffer size.");
            var data = new byte[length];
            if (GetLogicalProcessorInformationEx(0xffff, data, ref length)) {
                token.ThrowIfCancellationRequested();
                if (length is < 8 || length > data.Length) throw new DeviceReadoutException(ErrorCode.ReadFailed, "Invalid CPU topology response size.");
                return data[..(int)length];
            }
            error = Marshal.GetLastPInvokeError();
            if (error != 122) throw new Win32Exception(error);
            if (length <= data.Length) break;
        }
        throw new DeviceReadoutException(ErrorCode.ReadFailed, "CPU topology changed during buffer negotiation.");
    }
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetLogicalProcessorInformationEx(uint relationship, [Out] byte[]? buffer, ref uint length);
    [DllImport("powrprof.dll")]
    private static extern uint CallNtPowerInformation(uint level, nint input, uint inputSize, [Out] byte[] output, uint outputSize);
}
