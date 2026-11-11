using System.Runtime.InteropServices;
using System.Runtime.Versioning;

namespace DeviceReadout.Windows;

internal interface IWindowsConnectivityRuntime
{
    int Initialize();
    nint ActivateFactory();
    nint ActivateCellularFactory() => 0;
    IDisposable? ObserveCellularAccounts(Action<WindowsCellularAccountChange> changed, Action<Exception> fail) => null;
    nint CreateCellularWatcher() => 0;
    void Release(nint instance);
    void Uninitialize();
}
[UnmanagedFunctionPointer(CallingConvention.StdCall)]
internal delegate int WinRtNetworkStatusInvoke(nint self, nint sender);
[UnmanagedFunctionPointer(CallingConvention.StdCall)]
internal delegate int WinRtGetUInt64(nint self, out ulong value);
[UnmanagedFunctionPointer(CallingConvention.StdCall)]
internal delegate int WinRtCreateAccount(nint self, nint accountId, out nint value);

[SupportedOSPlatform("windows")]
internal sealed partial class WindowsConnectivity(IWindowsConnectivityRuntime? runtime = null, IWindowsWlanApi? wlanApi = null) : IDisposable
{
    private readonly IWindowsConnectivityRuntime runtime = runtime ?? new ConnectivityRuntime();
    private IWindowsWlanApi WlanApi => wlanApi ?? new WindowsWlanApi();
    private nint factory, cellularFactory;
    private bool initialized, unavailable, cellularUnavailable, closed;
    internal EntityCapabilities Capabilities => new(!unavailable && !closed, !unavailable && !closed);
    private void EnsureRuntime()
    {
        if (closed) throw new DeviceReadoutException(ErrorCode.EntityRemoved, "Connectivity context is closed.");
        if (!initialized) {Check(runtime.Initialize(), "RoInitialize");initialized = true;}
    }
    private void EnsureFactory()
    {
        EnsureRuntime();
        if (unavailable) throw new DeviceReadoutException(ErrorCode.UnsupportedEntity, "Windows connectivity is unavailable.");
        if (factory != 0) return;
        factory = runtime.ActivateFactory();
        if (factory == 0) {unavailable = true;throw new DeviceReadoutException(ErrorCode.UnsupportedEntity, "Windows connectivity is unavailable.");}
    }
    internal NetworkPathSnapshot Read(CancellationToken token)
    {
        token.ThrowIfCancellationRequested();EnsureFactory();token.ThrowIfCancellationRequested();
        nint profile = 0, cost = 0;
        try {
            Check(Method<WinRtGetInterface>(factory, 7)(factory, out profile), "GetInternetConnectionProfile");
            token.ThrowIfCancellationRequested();
            if (profile == 0) return new NetworkPathSnapshot {ConnectionState = ConnectionState.Disconnected, InternetValidated = false};
            int? level = null, costType = null;var successes = 0;DeviceReadoutException? failure = null;
            try {Check(Method<WinRtGetInt32>(profile, 7)(profile, out var value), "GetNetworkConnectivityLevel");level = value;successes++;}
            catch (DeviceReadoutException error) {failure = error;}
            token.ThrowIfCancellationRequested();
            try {
                Check(Method<WinRtGetInterface>(profile, 9)(profile, out cost), "GetConnectionCost");
                token.ThrowIfCancellationRequested();
                if (cost != 0) {Check(Method<WinRtGetInt32>(cost, 6)(cost, out var value), "NetworkCostType");costType = value;}
                successes++;
            } catch (DeviceReadoutException error) {if (failure is null || error.Code == ErrorCode.PermissionDenied) failure = error;}
            token.ThrowIfCancellationRequested();
            if (successes == 0) throw failure!;
            return new NetworkPathSnapshot {
                ConnectionState = level switch {0 => ConnectionState.Disconnected, 1 or 2 or 3 => ConnectionState.Connected, _ => null},
                InternetValidated = level switch {0 or 1 or 2 => false, 3 => true, _ => null},
                Metered = costType switch {1 => false, 2 or 3 => true, _ => null}
            };
        } finally {try {if (cost != 0) runtime.Release(cost);} finally {if (profile != 0) runtime.Release(profile);}}
    }
    internal NetworkPerformanceSnapshot ReadPerformance(CancellationToken token)
    {
        token.ThrowIfCancellationRequested();EnsureFactory();token.ThrowIfCancellationRequested();
        nint profile = 0, plan = 0;
        try {
            Check(Method<WinRtGetInterface>(factory, 7)(factory, out profile), "GetInternetConnectionProfile");
            token.ThrowIfCancellationRequested();
            if (profile == 0) return new NetworkPerformanceSnapshot();
            Check(Method<WinRtGetInterface>(profile, 10)(profile, out plan), "GetDataPlanStatus");
            token.ThrowIfCancellationRequested();
            if (plan == 0) return new NetworkPerformanceSnapshot();
            var successes = 0;DeviceReadoutException? failure = null;
            double? Rate(int slot)
            {
                nint reference = 0;
                try {
                    Check(Method<WinRtGetInterface>(plan, slot)(plan, out reference), "DataPlanStatus transfer rate");
                    token.ThrowIfCancellationRequested();
                    if (reference == 0) {successes++;return null;}
                    Check(Method<WinRtGetUInt64>(reference, 6)(reference, out var value), "Transfer rate IReference.Value");
                    token.ThrowIfCancellationRequested();successes++;return value;
                } catch (DeviceReadoutException error) {
                    if (failure is null || error.Code == ErrorCode.PermissionDenied) failure = error;
                    return null;
                } finally {if (reference != 0) runtime.Release(reference);}
            }
            var inbound = Rate(8);token.ThrowIfCancellationRequested();var outbound = Rate(9);
            token.ThrowIfCancellationRequested();
            if (successes == 0) throw failure!;
            return new NetworkPerformanceSnapshot {DownlinkBps = inbound, UplinkBps = outbound};
        } finally {try {if (plan != 0) runtime.Release(plan);} finally {if (profile != 0) runtime.Release(profile);}}
    }
    private static T Method<T>(nint instance, int slot) where T : Delegate
        => Marshal.GetDelegateForFunctionPointer<T>(Marshal.ReadIntPtr(Marshal.ReadIntPtr(instance), slot * nint.Size));
    internal ICollectorSubscription? Observe(Func<CancellationToken, DeviceSnapshot> read, Action<Func<CancellationToken, DeviceSnapshot>> changed, Action<Exception> fail, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();EnsureFactory();token.ThrowIfCancellationRequested();
        var handler = new WindowsNetworkStatusHandler(() => changed(read), fail);
        try {
            var hr = Method<WinRtAddReportEvent>(factory, 12)(factory, handler.Pointer, out var eventToken);
            if (hr == unchecked((int)0x80004001)) {handler.ReleaseOwner();return null;}
            Check(hr, "NetworkInformation.add_NetworkStatusChanged");
            return new Subscription(() => {
                handler.Stop();
                try {Check(Method<WinRtRemoveReportEvent>(factory, 13)(factory, eventToken), "NetworkInformation.remove_NetworkStatusChanged");}
                finally {handler.ReleaseOwner();}
            });
        } catch {handler.ReleaseOwner();throw;}
    }
    private sealed class Subscription(Action release) : ICollectorSubscription
    {
        private Action? release = release;
        public bool PollingRequired => true;
        public void Dispose() => Interlocked.Exchange(ref release, null)?.Invoke();
    }
    private static void Check(int result, string operation)
    {
        if (result < 0) throw new DeviceReadoutException(result == unchecked((int)0x80070005) ? ErrorCode.PermissionDenied : ErrorCode.ReadFailed,
            $"{operation} failed (HRESULT 0x{result:X8}).");
    }
    public void Dispose()
    {
        if (closed) return;closed = true;
        try {DisposeCellularObservation();}
        finally {
            try {if (factory != 0) runtime.Release(factory);}
            finally {
                factory = 0;
                try {if (cellularFactory != 0) runtime.Release(cellularFactory);}
                finally {cellularFactory = 0;if (initialized) {initialized = false;runtime.Uninitialize();}}
            }
        }
    }
    internal sealed class ConnectivityRuntime : IWindowsConnectivityRuntime
    {
        private static readonly WindowsCellularWatcher SharedCellularWatcher = new(new ConnectivityRuntime());
        public int Initialize() => RoInitialize(1);
        public void Uninitialize() => RoUninitialize();
        public void Release(nint instance) => Marshal.Release(instance);
        public nint ActivateFactory() => Activate("Windows.Networking.Connectivity.NetworkInformation", new("5074f851-950d-4165-9c15-365619481eea"));
        public nint ActivateCellularFactory() => Activate("Windows.Networking.NetworkOperators.MobileBroadbandAccount", new("aa7f4d24-afc1-4fc8-ae9a-a9175310faad"));
        public IDisposable? ObserveCellularAccounts(Action<WindowsCellularAccountChange> changed, Action<Exception> fail)
            => SharedCellularWatcher.Subscribe(changed, fail);
        public nint CreateCellularWatcher()
        {
            var activation = Activate("Windows.Networking.NetworkOperators.MobileBroadbandAccountWatcher", new("00000035-0000-0000-c000-000000000046"));
            if (activation == 0) return 0;
            nint instance = 0, watcher = 0;
            try {
                var activationResult = Method<WinRtGetInterface>(activation, 6)(activation, out instance);
                if (activationResult == unchecked((int)0x80004001)) return 0;
                Check(activationResult, "AccountWatcher.ActivateInstance");
                if (instance == 0) throw new DeviceReadoutException(ErrorCode.ReadFailed, "Missing native account watcher.");
                var iid = new Guid("6bf3335e-23b5-449f-928d-5e0d3e04471d");
                var queryResult = Marshal.QueryInterface(instance, in iid, out watcher);
                if (queryResult == unchecked((int)0x80004002)) return 0;
                Check(queryResult, "IMobileBroadbandAccountWatcher.QueryInterface");
                if (watcher == 0) throw new DeviceReadoutException(ErrorCode.ReadFailed, "Missing native account watcher interface.");
                var result = watcher;watcher = 0;return result;
            } finally {try {if (watcher != 0) Release(watcher);} finally {try {if (instance != 0) Release(instance);} finally {Release(activation);}}}
        }
        private nint Activate(string name, Guid iid)
        {
            Check(WindowsCreateString(name, name.Length, out var className), "WindowsCreateString");
            try {
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
