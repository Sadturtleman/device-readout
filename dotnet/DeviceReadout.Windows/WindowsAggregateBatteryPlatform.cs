using System.Runtime.InteropServices;
using System.Runtime.Versioning;

namespace DeviceReadout.Windows;

internal interface IWindowsBatteryRuntime
{
    int Initialize();
    nint ActivateFactory();
    void Release(nint instance);
    void Uninitialize();
}
[UnmanagedFunctionPointer(CallingConvention.StdCall)]
internal delegate int WinRtGetInterface(nint instance, out nint value);
[UnmanagedFunctionPointer(CallingConvention.StdCall)]
internal delegate int WinRtGetInt32(nint instance, out int value);
[UnmanagedFunctionPointer(CallingConvention.StdCall)]
internal delegate int WinRtAddReportEvent(nint instance, nint handler, out long token);
[UnmanagedFunctionPointer(CallingConvention.StdCall)]
internal delegate int WinRtRemoveReportEvent(nint instance, long token);

[SupportedOSPlatform("windows")]
internal sealed class WindowsAggregateBatteryPlatform(IWindowsBatteryRuntime? runtime = null) : IWindowsAggregateBatteryPlatform
{
    private readonly IWindowsBatteryRuntime runtime = runtime ?? new BatteryRuntime();
    private nint battery;
    private bool initialized, unavailable, closed;

    private bool EnsureBattery()
    {
        if (closed) throw new DeviceReadoutException(ErrorCode.EntityRemoved, "Aggregate battery context is closed.");
        if (unavailable) return false;
        if (battery != 0) return true;
        if (!initialized) {Check(runtime.Initialize(), "RoInitialize");initialized = true;}
        var factory = runtime.ActivateFactory();
        if (factory == 0) {unavailable = true;return false;}
        try {battery = Interface(factory, 6, "IBatteryStatics.AggregateBattery");return true;}
        finally {runtime.Release(factory);}
    }
    public WindowsAggregateReport? Read()
    {
        if (!EnsureBattery()) return null;
        var report = Interface(battery, 7, "IBattery.GetReport");
        try {
            var successes = 0;var lastError = unchecked((int)0x80004005);var denied = false;
            int? Property(int slot, bool boxed)
            {
                nint reference = 0;
                try {
                    var instance = report;
                    if (boxed) {
                        var hr = Method<WinRtGetInterface>(report, slot)(report, out reference);
                        if (hr < 0) {lastError = hr;denied |= hr == unchecked((int)0x80070005);return null;}
                        if (reference == 0) {successes++;return null;}
                        instance = reference;slot = 6;
                    }
                    var status = Method<WinRtGetInt32>(instance, slot)(instance, out var value);
                    if (status < 0) {lastError = status;denied |= status == unchecked((int)0x80070005);return null;}
                    successes++;return value;
                } finally {if (reference != 0) runtime.Release(reference);}
            }
            var rate = Property(6, true);var design = Property(7, true);
            var full = Property(8, true);var remaining = Property(9, true);var state = Property(10, false);
            if (successes == 0) Check(denied ? unchecked((int)0x80070005) : lastError, "IBatteryReport properties");
            return new(state, rate, design, full, remaining);
        } finally {runtime.Release(report);}
    }
    public IDisposable? Observe(Action changed, Action<Exception> fail)
    {
        if (!EnsureBattery()) return null;
        var handler = new WindowsBatteryReportHandler(changed, fail);
        try {
            var hr = Method<WinRtAddReportEvent>(battery, 8)(battery, handler.Pointer, out var token);
            if (hr == unchecked((int)0x80004001)) {handler.ReleaseOwner();return null;}
            Check(hr, "IBattery.add_ReportUpdated");
            return new Subscription(() => {
                handler.Stop();
                try {Check(Method<WinRtRemoveReportEvent>(battery, 9)(battery, token), "IBattery.remove_ReportUpdated");}
                finally {handler.ReleaseOwner();}
            });
        } catch {handler.ReleaseOwner();throw;}
    }
    private sealed class Subscription(Action release) : IDisposable
    {
        private Action? release = release;
        public void Dispose() => Interlocked.Exchange(ref release, null)?.Invoke();
    }
    private nint Interface(nint instance, int slot, string operation)
    {
        var hr = Method<WinRtGetInterface>(instance, slot)(instance, out var value);
        if (hr < 0) {if (value != 0) runtime.Release(value);Check(hr, operation);}
        if (value == 0) throw new DeviceReadoutException(ErrorCode.ReadFailed, $"{operation} returned no interface.");
        return value;
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
        try {if (battery != 0) runtime.Release(battery);}
        finally {battery = 0;if (initialized) {initialized = false;runtime.Uninitialize();}}
    }

    internal sealed class BatteryRuntime : IWindowsBatteryRuntime
    {
        public int Initialize() => RoInitialize(1);
        public void Uninitialize() => RoUninitialize();
        public void Release(nint instance) => Marshal.Release(instance);
        public nint ActivateFactory()
        {
            const string name = "Windows.Devices.Power.Battery";
            Check(WindowsCreateString(name, name.Length, out var className), "WindowsCreateString");
            try {
                var iid = new Guid("79cd72b6-9e5e-4452-bea6-dfcd541e597f");
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
