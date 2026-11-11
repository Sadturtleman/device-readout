using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using Microsoft.Win32.SafeHandles;

namespace DeviceReadout.Windows;

// Native OVERLAPPED I/O seam. Error values are Win32 codes, with zero indicating success.
internal interface IWindowsBatteryStatusIo : IDisposable
{
    int Submit(nint input, int inputSize, nint output, int outputSize, nint overlapped, out uint written);
    int Complete(nint overlapped, out uint written);
    int Cancel(nint overlapped);
}

internal sealed class WindowsBatteryStatusDevice(IWindowsBatteryStatusIo io) : IWindowsBatteryDevice
{
    public byte[] Query(BatteryIoControl control, byte[] input, int outputSize, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        if (control != BatteryIoControl.QueryStatus || input.Length != 20 || outputSize != 16)
            throw new DeviceReadoutException(ErrorCode.ReadFailed, "Invalid battery status request.");
        using var completed = new EventWaitHandle(false, EventResetMode.ManualReset);
        var structureSize = 3 * IntPtr.Size + 8;
        var storageSize = structureSize + input.Length + outputSize;
        var storage = Marshal.AllocHGlobal(storageSize);
        var pending = false;
        try {
            Marshal.Copy(new byte[storageSize], 0, storage, storageSize);
            Marshal.WriteIntPtr(storage, 2 * IntPtr.Size + 8, completed.SafeWaitHandle.DangerousGetHandle());
            var nativeInput = storage + structureSize;var nativeOutput = nativeInput + input.Length;
            Marshal.Copy(input, 0, nativeInput, input.Length);
            token.ThrowIfCancellationRequested();
            var error = io.Submit(nativeInput, input.Length, nativeOutput, outputSize, storage, out var written);
            pending = error == 997; // ERROR_IO_PENDING
            if (pending) {
                _ = WaitHandle.WaitAny([completed, token.WaitHandle]);
                if (token.IsCancellationRequested) _ = io.Cancel(storage);
                error = io.Complete(storage, out written);
                pending = false;
            }
            token.ThrowIfCancellationRequested();
            if (error != 0) throw new Win32Exception(error);
            if (written > outputSize) throw new DeviceReadoutException(ErrorCode.ReadFailed, "Invalid battery status response length.");
            var output = new byte[written];Marshal.Copy(nativeOutput, output, 0, output.Length);return output;
        } finally {
            // Cancellation requests do not transfer native buffer ownership back to the caller.
            // Finish on this dedicated lane, even when the caller has already stopped waiting.
            if (pending) {try {_ = io.Cancel(storage);} finally {_ = io.Complete(storage, out _);}}
            Marshal.FreeHGlobal(storage);
        }
    }
    public void Dispose() => io.Dispose();
}

[SupportedOSPlatform("windows")]
internal sealed class WindowsBatteryStatusIo(SafeFileHandle handle) : IWindowsBatteryStatusIo
{
    internal static IWindowsBatteryStatusIo Open(string path)
    {
        // Read-only access, independent overlapped handle; no device setting operation is exposed.
        var handle = BatteryNative.CreateFile(path, 0x80000000, 3, 0, 3, 0x40000080, 0);
        if (handle.IsInvalid) {var error = Marshal.GetLastPInvokeError();handle.Dispose();throw new Win32Exception(error);}
        return new WindowsBatteryStatusIo(handle);
    }
    public int Submit(nint input, int inputSize, nint output, int outputSize, nint overlapped, out uint written)
        => DeviceIoControl(handle, (uint)BatteryIoControl.QueryStatus, input, inputSize, output, outputSize, out written, overlapped) ? 0 : Marshal.GetLastPInvokeError();
    public int Complete(nint overlapped, out uint written)
        => GetOverlappedResult(handle, overlapped, out written, true) ? 0 : Marshal.GetLastPInvokeError();
    public int Cancel(nint overlapped) => CancelIoEx(handle, overlapped) ? 0 : Marshal.GetLastPInvokeError();
    public void Dispose() => handle.Dispose();
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DeviceIoControl(SafeFileHandle device, uint control, nint input, int inputSize, nint output, int outputSize, out uint written, nint overlapped);
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetOverlappedResult(SafeFileHandle device, nint overlapped, out uint written, [MarshalAs(UnmanagedType.Bool)] bool wait);
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CancelIoEx(SafeFileHandle device, nint overlapped);
}
