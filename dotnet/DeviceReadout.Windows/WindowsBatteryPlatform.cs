using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using Microsoft.Win32.SafeHandles;

namespace DeviceReadout.Windows;

// This boundary is the Windows battery device protocol, not the SDK collection interface.
internal enum BatteryIoControl : uint { QueryTag = 0x294040, QueryInformation = 0x294044, QueryStatus = 0x29404c }
internal readonly record struct WindowsDeviceInterfaceChange(string Path, bool Removed);
internal interface IWindowsBatteryPlatform
{
    IDisposable? ObserveInterfaces(Action<WindowsDeviceInterfaceChange> changed, Action<Exception> fail) => null;
    IReadOnlyList<string> Enumerate(CancellationToken token);
    IWindowsBatteryDevice Open(string path);
    IWindowsBatteryDevice? OpenStatus(string path) => null;
}
internal interface IWindowsBatteryDevice : IDisposable
{
    byte[] Query(BatteryIoControl control, byte[] input, int outputSize, CancellationToken token);
}

[SupportedOSPlatform("windows")]
internal sealed class WindowsBatteryPlatform : IWindowsBatteryPlatform
{
    internal static readonly Guid InterfaceClass = new("72631e54-78a4-11d0-bcf7-00aa00b7b32a");
    private readonly WindowsDeviceInterfaces interfaces = new();
    public IDisposable? ObserveInterfaces(Action<WindowsDeviceInterfaceChange> changed, Action<Exception> fail)
        => interfaces.Subscribe(InterfaceClass, changed, fail);
    public IReadOnlyList<string> Enumerate(CancellationToken token)
    {
        var batteryClass = InterfaceClass;
        using var devices = BatteryNative.SetupDiGetClassDevs(ref batteryClass, null, IntPtr.Zero, 0x12);
        if (devices.IsInvalid) throw new Win32Exception(Marshal.GetLastPInvokeError());
        var paths = new List<string>();
        for (uint index = 0; ; index++) {
            token.ThrowIfCancellationRequested();
            var data = new BatteryNative.InterfaceData {Size = (uint)Marshal.SizeOf<BatteryNative.InterfaceData>()};
            if (!BatteryNative.SetupDiEnumDeviceInterfaces(devices, IntPtr.Zero, ref batteryClass, index, ref data)) {
                var error = Marshal.GetLastPInvokeError();
                if (error == 259) return paths;
                throw new Win32Exception(error);
            }
            _ = BatteryNative.SetupDiGetDeviceInterfaceDetail(devices, ref data, IntPtr.Zero, 0, out var required, IntPtr.Zero);
            var sizingError = Marshal.GetLastPInvokeError();
            if (sizingError != 122) throw new Win32Exception(sizingError);
            if (required is < 6 or > 65536) throw new DeviceReadoutException(ErrorCode.ReadFailed, "Invalid battery device path size.");
            var buffer = Marshal.AllocHGlobal((int)required);
            try {
                Marshal.Copy(new byte[required], 0, buffer, (int)required);
                Marshal.WriteInt32(buffer, IntPtr.Size == 8 ? 8 : 6);
                if (!BatteryNative.SetupDiGetDeviceInterfaceDetail(devices, ref data, buffer, required, out _, IntPtr.Zero))
                    throw new Win32Exception(Marshal.GetLastPInvokeError());
                var path = Marshal.PtrToStringUni(buffer + 4, ((int)required - 4) / 2)!;
                var terminator = path.IndexOf('\0');
                if (terminator <= 0) throw new DeviceReadoutException(ErrorCode.ReadFailed, "Invalid battery device path.");
                paths.Add(path[..terminator]);
            } finally {Marshal.FreeHGlobal(buffer);}
        }
    }

    public IWindowsBatteryDevice Open(string path)
    {
        // The three query IOCTLs require only FILE_READ_ACCESS. No set-information operation is exposed.
        var handle = BatteryNative.CreateFile(path, 0x80000000, 3, IntPtr.Zero, 3, 0x80, IntPtr.Zero);
        if (handle.IsInvalid) {var error = Marshal.GetLastPInvokeError();handle.Dispose();throw new Win32Exception(error);}
        return new Device(handle);
    }
    public IWindowsBatteryDevice OpenStatus(string path) => new WindowsBatteryStatusDevice(WindowsBatteryStatusIo.Open(path));
    private sealed class Device(SafeFileHandle handle) : IWindowsBatteryDevice
    {
        public byte[] Query(BatteryIoControl control, byte[] input, int outputSize, CancellationToken token)
        {
            token.ThrowIfCancellationRequested();
            var output = new byte[outputSize];
            if (!BatteryNative.DeviceIoControl(handle, (uint)control, input, input.Length, output, output.Length, out var written, IntPtr.Zero))
                throw new Win32Exception(Marshal.GetLastPInvokeError());
            token.ThrowIfCancellationRequested();
            if (written > outputSize) throw new DeviceReadoutException(ErrorCode.ReadFailed, "Invalid battery response length.");
            return output[..(int)written];
        }
        public void Dispose() => handle.Dispose();
    }
}

[SupportedOSPlatform("windows")]
internal static class BatteryNative
{
    [StructLayout(LayoutKind.Sequential)] internal struct InterfaceData {public uint Size;public Guid InterfaceClassGuid;public uint Flags;public UIntPtr Reserved;}
    internal sealed class DeviceInfoHandle : SafeHandleZeroOrMinusOneIsInvalid
    {
        public DeviceInfoHandle() : base(true) { }
        protected override bool ReleaseHandle() => SetupDiDestroyDeviceInfoList(handle);
    }
    [DllImport("setupapi.dll", EntryPoint = "SetupDiGetClassDevsW", CharSet = CharSet.Unicode, SetLastError = true)]
    internal static extern DeviceInfoHandle SetupDiGetClassDevs(ref Guid guid, string? enumerator, IntPtr parent, uint flags);
    [DllImport("setupapi.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool SetupDiEnumDeviceInterfaces(DeviceInfoHandle devices, IntPtr device, ref Guid guid, uint index, ref InterfaceData data);
    [DllImport("setupapi.dll", EntryPoint = "SetupDiGetDeviceInterfaceDetailW", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool SetupDiGetDeviceInterfaceDetail(DeviceInfoHandle devices, ref InterfaceData data, IntPtr detail, uint size, out uint required, IntPtr deviceInfo);
    [DllImport("setupapi.dll")] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetupDiDestroyDeviceInfoList(IntPtr devices);
    [DllImport("kernel32.dll", EntryPoint = "CreateFileW", CharSet = CharSet.Unicode, SetLastError = true)]
    internal static extern SafeFileHandle CreateFile(string path, uint access, uint sharing, IntPtr security, uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool DeviceIoControl(SafeFileHandle device, uint control, byte[] input, int inputSize, [Out] byte[] output, int outputSize, out uint written, IntPtr overlapped);
}
