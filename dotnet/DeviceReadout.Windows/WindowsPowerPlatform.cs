using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Collections.Concurrent;

namespace DeviceReadout.Windows;

internal readonly record struct WindowsPowerState(byte AcLineStatus, byte SystemStatusFlag,
    byte BatteryFlag = 255, byte BatteryLifePercent = 255, uint BatteryLifeTime = uint.MaxValue, uint BatteryFullLifeTime = uint.MaxValue,
    WindowsBatteryCapabilities? BatteryCapabilities = null);

internal readonly record struct WindowsBatteryCapabilities(byte SystemBatteriesPresent, byte UpsPresent, byte BatteriesAreShortTerm);

internal static class WindowsPowerSettings
{
    internal static readonly Guid Source = new("5D3E9A59-E9D5-4B00-A6BD-FF34FF516548");
    internal static readonly Guid Saving = new("E00958C0-C213-4ACE-AC77-FECCED2EEEA5");
    internal static readonly Guid BatteryPercentage = new("A7AD8041-B45A-4CAE-87A3-EECBB468A9E1");
}

internal interface IWindowsPowerPlatform
{
    WindowsPowerState Read();
    IDisposable? Subscribe(Guid setting, Action<uint> changed, Action<Exception> fail);
}

[SupportedOSPlatform("windows")]
internal sealed class WindowsPowerPlatform : IWindowsPowerPlatform
{
    public WindowsPowerState Read()
    {
        if (!Native.GetSystemPowerStatus(out var state))
            throw new DeviceReadoutException(ErrorCode.ReadFailed, $"GetSystemPowerStatus failed (Win32 {Marshal.GetLastPInvokeError()}).");
        WindowsBatteryCapabilities? batteries = null;
        if (state.AcLineStatus == 0 && GetPwrCapabilities(out var capabilities))
            batteries = new(capabilities.SystemBatteriesPresent, capabilities.UpsPresent, capabilities.BatteriesAreShortTerm);
        return new(state.AcLineStatus, state.SystemStatusFlag, state.BatteryFlag, state.BatteryLifePercent,
            state.BatteryLifeTime, state.BatteryFullLifeTime, batteries);
    }
    public IDisposable? Subscribe(Guid setting, Action<uint> changed, Action<Exception> fail)
        => Registration.Create(setting, changed, fail);

    private sealed class Registration(Guid setting, Action<uint> changed, Action<Exception> fail) : IDisposable
    {
        // One rooted callback and never-reused numeric contexts make late native callbacks harmless:
        // no unmanaged context points to a freed GCHandle or a collected delegate.
        private static readonly ConcurrentDictionary<nint, Registration> Active = new();
        private static readonly NotificationCallback Callback = Dispatch;
        private static long nextId;
        private Action<uint>? changed = changed;
        private Action<Exception>? fail = fail;
        private nint id, handle;
        private int closed;

        internal static Registration? Create(Guid setting, Action<uint> changed, Action<Exception> fail)
        {
            var registration = new Registration(setting, changed, fail) {id = checked((nint)Interlocked.Increment(ref nextId))};
            Active.TryAdd(registration.id, registration);
            try {
                var parameters = new NotificationParameters {Callback = Marshal.GetFunctionPointerForDelegate(Callback), Context = registration.id};
                var result = PowerSettingRegisterNotification(in setting, 2, ref parameters, out registration.handle);
                if (result == 0) return registration;
                registration.Detach();
                if (result is 50 or 120) return null;
                throw Failure("PowerSettingRegisterNotification", result);
            } catch {registration.Detach();throw;}
        }

        private static uint Dispatch(nint context, uint type, nint data)
        {
            if (type != 0x8013 || !Active.TryGetValue(context, out var registration)) return 0;
            try {
                if (Volatile.Read(ref registration.closed) != 0) return 0;
                if (data == 0) throw new DeviceReadoutException(ErrorCode.ReadFailed, "Power notification has no payload.");
                if (Marshal.PtrToStructure<Guid>(data) != registration.setting) return 0;
                if (Marshal.ReadInt32(data, 16) != sizeof(uint))
                    throw new DeviceReadoutException(ErrorCode.ReadFailed, "Power notification has an invalid DWORD payload.");
                Volatile.Read(ref registration.changed)?.Invoke(unchecked((uint)Marshal.ReadInt32(data, 20)));
            } catch (Exception error) {
                try {Volatile.Read(ref registration.fail)?.Invoke(error);} catch (Exception) { /* Never unwind into the OS callback. */ }
            }
            return 0;
        }
        private readonly Guid setting = setting;
        private void Detach()
        {
            Interlocked.Exchange(ref closed, 1);
            Active.TryRemove(id, out _);
            Interlocked.Exchange(ref changed, null);Interlocked.Exchange(ref fail, null);
        }
        public void Dispose()
        {
            if (Interlocked.Exchange(ref closed, 1) != 0) return;
            Detach();
            var native = Interlocked.Exchange(ref handle, 0);
            if (native == 0) return;
            var result = PowerSettingUnregisterNotification(native);
            if (result != 0) throw Failure("PowerSettingUnregisterNotification", result);
        }
    }

    private static DeviceReadoutException Failure(string api, uint error)
        => new(error == 5 ? ErrorCode.PermissionDenied : ErrorCode.ReadFailed, $"{api} failed (Win32 {error}).");
    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate uint NotificationCallback(nint context, uint type, nint setting);
    [StructLayout(LayoutKind.Sequential)]
    private struct NotificationParameters {internal nint Callback, Context;}
    // The Windows SDK fixes these fields within the 76-byte SYSTEM_POWER_CAPABILITIES layout.
    [StructLayout(LayoutKind.Explicit, Size = 76)]
    private struct SystemPowerCapabilities
    {
        [FieldOffset(12)] internal byte UpsPresent;
        [FieldOffset(30)] internal byte SystemBatteriesPresent;
        [FieldOffset(31)] internal byte BatteriesAreShortTerm;
    }
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [DllImport("powrprof.dll")]
    [return: MarshalAs(UnmanagedType.U1)]
    private static extern bool GetPwrCapabilities(out SystemPowerCapabilities capabilities);
    [DllImport("powrprof.dll")]
    private static extern uint PowerSettingRegisterNotification(in Guid setting, uint flags, ref NotificationParameters recipient, out nint registrationHandle);
    [DllImport("powrprof.dll")]
    private static extern uint PowerSettingUnregisterNotification(nint registrationHandle);
}
