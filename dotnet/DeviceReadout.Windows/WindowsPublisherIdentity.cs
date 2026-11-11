using System.Runtime.InteropServices;
using System.Runtime.Versioning;

namespace DeviceReadout.Windows;

internal interface IWindowsIdentityRuntime
{
    int Initialize();
    nint ActivateFactory();
    void Release(nint instance);
    void Uninitialize();
}
[UnmanagedFunctionPointer(CallingConvention.StdCall)]
internal delegate int WinRtGetUInt32(nint instance, out uint value);

[SupportedOSPlatform("windows")]
internal sealed class WindowsPublisherIdentity(IWindowsIdentityRuntime? runtime = null) : IDisposable
{
    private readonly IWindowsIdentityRuntime runtime = runtime ?? new IdentityRuntime();
    private nint factory;
    private bool initialized, unavailable, closed;
    internal EntityCapabilities Capabilities => new(!unavailable && !closed, !unavailable && !closed);
    private void EnsureFactory()
    {
        if (closed) throw new DeviceReadoutException(ErrorCode.EntityRemoved, "Identity context is closed.");
        if (unavailable) throw new DeviceReadoutException(ErrorCode.UnsupportedEntity, "Windows publisher identity is unavailable.");
        if (factory != 0) return;
        if (!initialized) {Check(runtime.Initialize(), "RoInitialize");initialized = true;}
        factory = runtime.ActivateFactory();
        if (factory == 0) {unavailable = true;throw new DeviceReadoutException(ErrorCode.UnsupportedEntity, "Windows publisher identity is unavailable.");}
    }
    internal WindowsPublisherIdentitySnapshot Read(CancellationToken token)
    {
        token.ThrowIfCancellationRequested();EnsureFactory();token.ThrowIfCancellationRequested();
        nint info = 0;
        try {
            Check(Method<WinRtGetInterface>(factory, 6)(factory, out info), "GetSystemIdForPublisher");
            token.ThrowIfCancellationRequested();
            if (info == 0) throw new DeviceReadoutException(ErrorCode.ReadFailed, "SystemIdentification returned no result.");
            string? id = null;WindowsIdentitySource? source = null;
            var successes = 0;DeviceReadoutException? failure = null;
            try {id = ReadId(info, token);successes++;}
            catch (DeviceReadoutException error) {failure = error;}
            token.ThrowIfCancellationRequested();
            try {
                Check(Method<WinRtGetInt32>(info, 7)(info, out var value), "SystemIdentificationInfo.Source");
                source = value switch {1 => WindowsIdentitySource.Tpm, 2 => WindowsIdentitySource.Uefi, 3 => WindowsIdentitySource.Registry, _ => null};
                successes++;
            } catch (DeviceReadoutException error) {if (failure is null || error.Code == ErrorCode.PermissionDenied) failure = error;}
            token.ThrowIfCancellationRequested();
            if (successes == 0) throw failure!;
            return new WindowsPublisherIdentitySnapshot {PublisherId = id, Source = source};
        } finally {if (info != 0) runtime.Release(info);}
    }
    private string? ReadId(nint info, CancellationToken token)
    {
        nint buffer = 0, access = 0;
        try {
            Check(Method<WinRtGetInterface>(info, 6)(info, out buffer), "SystemIdentificationInfo.Id");
            if (buffer == 0) return null;
            Check(Method<WinRtGetUInt32>(buffer, 7)(buffer, out var length), "IBuffer.Length");
            Check(Method<WinRtGetUInt32>(buffer, 6)(buffer, out var capacity), "IBuffer.Capacity");
            if (length > capacity || length > 65536) throw new DeviceReadoutException(ErrorCode.ReadFailed, "Invalid system identity buffer length.");
            if (length == 0) return null;
            var iid = new Guid("905a0fef-bc53-11df-8c49-001e4fc686da");
            Check(Marshal.QueryInterface(buffer, in iid, out access), "IBufferByteAccess.QueryInterface");
            if (access == 0) throw new DeviceReadoutException(ErrorCode.ReadFailed, "System identity byte access is unavailable.");
            Check(Method<WinRtGetInterface>(access, 3)(access, out var data), "IBufferByteAccess.Buffer");
            if (data == 0) throw new DeviceReadoutException(ErrorCode.ReadFailed, "System identity buffer is unavailable.");
            token.ThrowIfCancellationRequested();var bytes = new byte[length];Marshal.Copy(data, bytes, 0, bytes.Length);
            token.ThrowIfCancellationRequested();return Convert.ToHexStringLower(bytes);
        } finally {try {if (access != 0) runtime.Release(access);} finally {if (buffer != 0) runtime.Release(buffer);}}
    }
    private static T Method<T>(nint instance, int slot) where T : Delegate
        => Marshal.GetDelegateForFunctionPointer<T>(Marshal.ReadIntPtr(Marshal.ReadIntPtr(instance), slot * nint.Size));
    private static void Check(int result, string operation)
    {
        if (result < 0) throw new DeviceReadoutException(result == unchecked((int)0x80070005) ? ErrorCode.PermissionDenied : ErrorCode.ReadFailed,
            $"{operation} failed (HRESULT 0x{result:X8}).");
    }
    public void Dispose()
    {
        if (closed) return;closed = true;
        try {if (factory != 0) runtime.Release(factory);}
        finally {factory = 0;if (initialized) {initialized = false;runtime.Uninitialize();}}
    }
    internal sealed class IdentityRuntime : IWindowsIdentityRuntime
    {
        public int Initialize() => RoInitialize(1);
        public void Uninitialize() => RoUninitialize();
        public void Release(nint instance) => Marshal.Release(instance);
        public nint ActivateFactory()
        {
            const string name = "Windows.System.Profile.SystemIdentification";
            Check(WindowsCreateString(name, name.Length, out var className), "WindowsCreateString");
            try {
                var iid = new Guid("5581f42a-d3df-4d93-a37d-c41a616c6d01");
                var hr = RoGetActivationFactory(className, in iid, out var factory);
                if (hr < 0) {
                    if (factory != 0) Release(factory);
                    if (hr is unchecked((int)0x80040154) or unchecked((int)0x80004002)) return 0;
                    Check(hr, "RoGetActivationFactory");
                }
                return factory;
            } finally {WindowsDeleteString(className);}
        }
        [DllImport("combase.dll")] private static extern int RoInitialize(uint type);
        [DllImport("combase.dll")] private static extern void RoUninitialize();
        [DllImport("combase.dll")] private static extern int RoGetActivationFactory(nint name, in Guid iid, out nint factory);
        [DllImport("combase.dll", CharSet = CharSet.Unicode)] private static extern int WindowsCreateString(string source, int length, out nint value);
        [DllImport("combase.dll")] private static extern int WindowsDeleteString(nint value);
    }
}
