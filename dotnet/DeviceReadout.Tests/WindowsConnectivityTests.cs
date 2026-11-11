using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using DeviceReadout;
using DeviceReadout.Windows;

[SupportedOSPlatform("windows")]
internal static partial class WindowsConnectivityTests
{
    internal static IEnumerable<(string Name, Func<Task> Run)> Cases() => [
        ("Windows preferred network path keeps connectivity and metering meanings distinct and polls fresh reports", PathFields),
        ("Windows network status notifications refresh before polling and stop with their owning subscriptions", PathEvents),
        ("Windows connectivity and cost failures preserve independent fields and whole-query errors stop observation", PathFailures),
        ("Windows connectivity uses polling for unavailable events and surfaces registration denial without leaking handlers", PathRegistrationFailures),
        ("Windows connectivity deadlines release the caller and discard late native profiles before field collection", PathDeadline),
        ("real Windows preferred path reads and native status registrations have worker-owned lifetimes", ActualPath),
        ("Windows network performance reads native nominal rates in bits per second and preserves zero and missing values", PerformanceFields),
        ("Windows path and performance watches receive their own typed snapshots from native changes and polling", PerformanceEvents),
        ("Windows performance fields preserve independent availability and release failed native reference values", PerformanceFailures),
        ("real Windows network performance reads and watches use native plans with balanced worker-owned lifetime", ActualPerformance),
        ("Windows performance get and event deadlines release callers and clean late native plans without reading rates", PerformanceDeadlines),
        ("Windows Wi-Fi discovers active typed targets and reads selected SSIDs and authentication without requesting UI", WifiFields),
        ("Windows Wi-Fi watches retain equal native updates and retire disconnected or replaced connection handles", WifiEvents),
        ("Windows Wi-Fi preserves independent fields and rejects incomplete inventories without retiring valid targets", WifiFailures),
        ("Windows Wi-Fi get and event deadlines discard late inventory work and release native references on the worker", WifiDeadlines),
        ("Windows Wi-Fi reads leave permission coordination to application observers", WifiObservers),
        ("real Windows Wi-Fi inventory and preferred target reads use worker-owned WinRT lifetimes", ActualWifi),
        ("Windows Wi-Fi reads signed RSSI for the selected adapter and retains fresh native and polled values", WifiRssi),
        ("Windows Wi-Fi RSSI failures preserve independent fields and release failed or malformed native output", WifiRssiFailures),
        ("Windows Wi-Fi native disconnection and mid-read replacement permanently retire selected handles", WifiRssiRemoval),
        ("Windows WLAN open query and close waits respect caller deadlines and complete late cleanup on the worker", WifiRssiDeadlines),
        ("real Windows WLAN reports a missing selected interface and closes its native session on the worker", ActualWlanRemoval),
        ("Windows cellular discovery uses distinct accounts and retires observed removals on its worker", CellularAccounts),
        ("Windows cellular fields preserve account identity and current data technology without guessing unsupported values", CellularFields),
        ("Windows cellular current selects the preferred associated data path and watches fresh account states", CellularCurrent),
        ("Windows cellular failures preserve independent fields and handle generations while releasing native outputs", CellularFailures),
        ("Windows cellular inventory account and field waits respect deadlines and complete worker-owned cleanup", CellularDeadlines),
        ("Windows cellular permission work is explicit and completes through application observer state", CellularObservers),
        ("real Windows cellular inventory and current use read-only native APIs with worker-owned cleanup", ActualCellular),
        ("Windows cellular observed removal persists between reads and rejects rapid reuse and in-flight snapshots", CellularRemovalHistory),
        ("Windows cellular contexts share one native watcher and retain observation after the creating context closes", CellularSharedWatcher),
        ("real Windows cellular watcher registers starts and stops once across two independent SDK contexts", ActualCellularWatcher),
        ("Windows cellular watcher failures release partial registration and preserve explicit error and polling policies", CellularWatcherFailures),
        ("Windows cellular inventories preserve removal evidence across stale failed and racing native results", CellularInventoryObservationRaces),
        ("Windows cellular watcher registration start and stop waits preserve host progress and late cleanup", CellularWatcherDeadlines),
        ("Windows cellular late callbacks cannot leak removal or failure into a newer native source", CellularLateSourceCallbacks),
        ("Windows cellular unsupported event operations retain readable accounts and polling without activation loops", CellularWatcherPollingFallback)
    ];
    private static async Task PathFields()
    {
        var runtime = new ConnectivityFixture();var caller = Environment.CurrentManagedThreadId;
        using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime));
        Check(runtime.Initializations == 0 && runtime.Reads == 0, "construction has no native work");
        var value = await access.Get(Entities.NetworkPath);
        Check(value.ConnectionState == ConnectionState.Connected && value.InternetValidated == true && value.Metered == false, "InternetAccess and unrestricted usage");
        foreach (var level in new[] {1, 2}) {
            runtime.Level = level;runtime.Cost = 2;
            value = await access.Get(Entities.NetworkPath);
            Check(value.ConnectionState == ConnectionState.Connected && value.InternetValidated == false && value.Metered == true, "local/limited access is connected, not internet-validated");
            Check(value.CaptivePortal is null && value.Constrained is null && value.Expensive is null && value.SaveData is null, "limited access and cost do not invent portal, data-saving or expense policies");
        }
        runtime.Level = 0;runtime.Cost = 3;value = await access.Get(Entities.NetworkPath);
        Check(value.ConnectionState == ConnectionState.Disconnected && value.InternetValidated == false && value.Metered == true, "known disconnected and variable cost");
        runtime.Level = 99;runtime.Cost = 99;value = await access.Get(Entities.NetworkPath);
        Check(value.ConnectionState is null && value.InternetValidated is null && value.Metered is null, "unknown native enums remain null");
        runtime.Cost = 0;Check((await access.Get(Entities.NetworkPath)).Metered is null, "native unknown cost remains null");
        runtime.NoProfile = true;value = await access.Get(Entities.NetworkPath);
        Check(value.ConnectionState == ConnectionState.Disconnected && value.InternetValidated == false && value.Metered is null, "absent preferred profile has no current default path");
        runtime.NoProfile = false;runtime.Level = 3;runtime.Cost = 1;
        var readsBeforeWatch = runtime.Reads;
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(2));
        await using (var stream = access.WithPollInterval(TimeSpan.FromMilliseconds(25)).Watch(Entities.NetworkPath, deadline.Token).GetAsyncEnumerator()) {
            for (var index = 0; index < 2; index++) Check(await stream.MoveNextAsync() && stream.Current.ConnectionState == ConnectionState.Connected, "initial and equal polled states are retained");
        }
        Check((await access.Capabilities.Get(Entities.NetworkPath)).Readable == true, "path is readable");
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.Reads >= readsBeforeWatch + 2 && runtime.References.Values.All(count => count == 0), "fresh watch reports and balanced reference lifetime");
        Check(runtime.Initializations == 1 && runtime.Uninitializations == 1 && runtime.Threads.Distinct().Count() == 1
            && !runtime.Threads.Contains(caller), "native initialization, reads and disposal stay on one worker");
    }
    private static async Task PathEvents()
    {
        var runtime = new ConnectivityFixture();var caller = Environment.CurrentManagedThreadId;
        using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime));
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        var slow = access.WithPollInterval(TimeSpan.FromHours(1));
        await using var first = slow.Watch(Entities.NetworkPath, deadline.Token).GetAsyncEnumerator();
        await using var second = slow.Watch(Entities.NetworkPath, deadline.Token).GetAsyncEnumerator();
        Check(await first.MoveNextAsync() && await second.MoveNextAsync(), "both initial reads");
        Check(runtime.Registrations == 2, "each active watch registers a native change source");
        runtime.Cost = 2;runtime.Level = 2;runtime.Fire();
        Check(await first.MoveNextAsync() && first.Current.Metered == true && first.Current.InternetValidated == false, "notification refreshes the first stream before the poll");
        Check(await second.MoveNextAsync() && second.Current.Metered == true, "notification refreshes the second stream");
        runtime.Fire();Check(await first.MoveNextAsync() && await second.MoveNextAsync(), "equal native notifications are retained");
        var lateHandler = runtime.RetainFirstHandler();
        await first.DisposeAsync();
        Check(runtime.Removals == 1 && runtime.HandlerCount == 1, "one closure leaves the other subscription active");
        var reads = runtime.Reads;
        ConnectivityFixture.Invoke(lateHandler);Marshal.Release(lateHandler);
        await Task.Delay(25);Check(runtime.Reads == reads, "callback retained past removal schedules no new read");
        runtime.NoProfile = true;runtime.Fire();
        Check(await second.MoveNextAsync() && second.Current.ConnectionState == ConnectionState.Disconnected, "remaining stream follows disappearance of the preferred path");
        await second.DisposeAsync();
        Check(runtime.Removals == 2 && runtime.HandlerCount == 0, "all watch registrations released");
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.References.Values.All(count => count == 0) && runtime.Threads.Distinct().Count() == 1 && !runtime.Threads.Contains(caller), "native register/read/remove/release stay on the worker");
    }
    private static async Task PathFailures()
    {
        var runtime = new ConnectivityFixture();
        using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime));
        runtime.LevelResult = unchecked((int)0x80070005);
        var value = await access.Get(Entities.NetworkPath);
        Check(value.ConnectionState is null && value.InternetValidated is null && value.Metered == false, "failed connectivity does not erase readable cost");
        runtime.LevelResult = 0;runtime.CostResult = unchecked((int)0x80070005);
        value = await access.Get(Entities.NetworkPath);
        Check(value.ConnectionState == ConnectionState.Connected && value.InternetValidated == true && value.Metered is null, "failed cost query does not erase readable connectivity");
        runtime.CostResult = 0;runtime.CostTypeResult = unchecked((int)0x80004005);
        Check((await access.Get(Entities.NetworkPath)).Metered is null, "failed nested cost getter is field-local");
        runtime.LevelResult = unchecked((int)0x80070005);
        await Error(ErrorCode.PermissionDenied, () => access.Get(Entities.NetworkPath));
        runtime.LevelResult = unchecked((int)0x80004005);
        await Error(ErrorCode.ReadFailed, () => access.Get(Entities.NetworkPath));
        runtime.LevelResult = runtime.CostTypeResult = 0;runtime.NoCost = true;
        Check((await access.Get(Entities.NetworkPath)).Metered is null, "absent cost object means unknown, not free");
        runtime.NoCost = false;
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        await using (var stream = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(Entities.NetworkPath, deadline.Token).GetAsyncEnumerator()) {
            Check(await stream.MoveNextAsync(), "initial value before native failure");
            runtime.ProfileResult = unchecked((int)0x80070005);runtime.Fire();
            await Error(ErrorCode.PermissionDenied, async () => {await stream.MoveNextAsync();});
        }
        Check(runtime.HandlerCount == 0 && runtime.Registrations == runtime.Removals, "whole-query error releases native observation");
        runtime.ProfileResult = 0;
        Check((await access.Get(Entities.NetworkPath)).InternetValidated == true, "new explicit read can recover");
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.References.Values.All(count => count == 0), "partial/whole native failures release nonnull out-interfaces");
    }
    private static async Task PathRegistrationFailures()
    {
        var runtime = new ConnectivityFixture {AddResult = unchecked((int)0x80004001)};
        using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime));
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        await using (var stream = access.WithPollInterval(TimeSpan.FromMilliseconds(25)).Watch(Entities.NetworkPath, deadline.Token).GetAsyncEnumerator()) {
            Check(await stream.MoveNextAsync() && await stream.MoveNextAsync(), "unimplemented event source keeps initial collection and serial polling");
        }
        Check(runtime.Registrations == 1 && runtime.Removals == 0 && runtime.HandlerCount == 0, "fallback creates no native event subscription");
        runtime.AddResult = unchecked((int)0x80070005);runtime.RetainFailedHandler = true;
        await using (var stream = access.Watch(Entities.NetworkPath, deadline.Token).GetAsyncEnumerator()) {
            await Error(ErrorCode.PermissionDenied, async () => {await stream.MoveNextAsync();});
        }
        Check(runtime.FailedHandler != 0 && Marshal.Release(runtime.FailedHandler) == 0, "failed registration released the SDK owner reference");
        var attempts = runtime.Registrations;await Task.Delay(25);
        Check(runtime.Registrations == attempts && runtime.Removals == 0, "registration denial is not retried or converted to silent polling");
        runtime.AddResult = 0;runtime.RetainFailedHandler = false;
        Check((await access.Get(Entities.NetworkPath)).ConnectionState == ConnectionState.Connected, "separate explicit get remains available");
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.References.Values.All(count => count == 0), "factory and field interfaces released after registration failure");
    }
    private static async Task PathDeadline()
    {
        var runtime = new ConnectivityFixture();runtime.ContinueRead.Reset();
        using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime));
        var pending = access.WithReadTimeout(TimeSpan.FromMilliseconds(100)).Get(Entities.NetworkPath);
        try {
            await runtime.ReadStarted.Task.WaitAsync(TimeSpan.FromSeconds(2));
            await Task.Delay(10);Check(!pending.IsCompleted, "host continuation runs while native profile query is blocked");
            await Error(ErrorCode.ReadTimeout, () => pending.WaitAsync(TimeSpan.FromSeconds(2)));
            access.Dispose();Check(!runtime.Stopped.Task.IsCompleted, "context closure does not join or uninitialize borrowed native work");
        } finally {runtime.ContinueRead.Set();access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));}
        Check(runtime.LevelReads == 0 && runtime.Uninitializations == 1 && runtime.References.Values.All(count => count == 0), "late profile is released without further field reads");
        runtime.ContinueRead.Dispose();
    }
    private static async Task ActualPath()
    {
        var runtime = new NativeConnectivityProbe();var caller = Environment.CurrentManagedThreadId;
        using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime));
        var value = await access.Get(Entities.NetworkPath);
        Check(value.ConnectionState is not null && value.InternetValidated is not null, "native preferred-path connectivity is readable on this host");
        Check(value.CaptivePortal is null && value.Constrained is null && value.Transports is null, "native level does not invent unavailable path meanings");
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        await using (var stream = access.WithPollInterval(TimeSpan.FromMilliseconds(25)).Watch(Entities.NetworkPath, deadline.Token).GetAsyncEnumerator()) {
            Check(await stream.MoveNextAsync(), "actual initial path snapshot");
            Check(runtime.Active == 1 && runtime.Registrations == 1, "actual native status registration succeeded");
            Check(await stream.MoveNextAsync(), "actual serial poll remains active");
        }
        Check(runtime.Active == 0 && runtime.Removals == 1 && runtime.RemovalResult == 0, "actual native status handler removed successfully");
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.Initializations == 1 && runtime.Uninitializations == 1 && runtime.FactoryReleases == 1, "native factory and runtime lifetime balanced");
        Check(runtime.Threads.Distinct().Count() == 1 && !runtime.Threads.Contains(caller), "actual read/register/remove/release happen on one worker");
        Console.WriteLine($"Native Windows preferred path: state={value.ConnectionState}, validated={value.InternetValidated}, metered={value.Metered}; native status registration/removal and WinRT cleanup verified.");
    }
    // Forward native ABI calls without replacing their result, recording actual registrations and releases.
    private sealed class NativeConnectivityProbe(WindowsCellularWatcher? cellularSource = null) : IWindowsConnectivityRuntime
    {
        private readonly WindowsConnectivity.ConnectivityRuntime native = new();
        private readonly List<Delegate> delegates = [];
        private nint factory, proxy, table, cellularFactory;
        internal readonly List<int> Threads = [];
        internal readonly TaskCompletionSource Stopped = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal int Initializations, Uninitializations, FactoryReleases, Registrations, Removals, Active, RemovalResult;
        internal int CellularFactoryReleases;
        internal int CellularSubscriptions, CellularUnsubscriptions;
        public IDisposable? ObserveCellularAccounts(Action<WindowsCellularAccountChange> changed, Action<Exception> fail)
        {
            Record();var subscription = cellularSource is null ? native.ObserveCellularAccounts(changed, fail) : cellularSource.Subscribe(changed, fail);
            if (subscription is null) return null;
            CellularSubscriptions++;return new NativeCellularLease(() => {Record();subscription.Dispose();CellularUnsubscriptions++;});
        }
        private sealed class NativeCellularLease(Action dispose) : IDisposable {public void Dispose() => dispose();}
        private void Record() => Threads.Add(Environment.CurrentManagedThreadId);
        private static T Method<T>(nint self, int slot) where T : Delegate
            => Marshal.GetDelegateForFunctionPointer<T>(Marshal.ReadIntPtr(Marshal.ReadIntPtr(self), slot * nint.Size));
        private void Set(int slot, Delegate callback) {delegates.Add(callback);Marshal.WriteIntPtr(table, slot * nint.Size, Marshal.GetFunctionPointerForDelegate(callback));}
        public int Initialize() {Record();Initializations++;return native.Initialize();}
        public nint ActivateCellularFactory() {Record();cellularFactory = native.ActivateCellularFactory();return cellularFactory;}
        public nint ActivateFactory()
        {
            Record();factory = native.ActivateFactory();if (factory == 0) return 0;
            proxy = Marshal.AllocHGlobal(nint.Size);table = Marshal.AllocHGlobal(14 * nint.Size);Marshal.WriteIntPtr(proxy, table);
            for (var slot = 0; slot < 14; slot++) Marshal.WriteIntPtr(table, slot * nint.Size, 0);
            Set(6, new WinRtGetInterface((nint self, out nint value) => {Record();return Method<WinRtGetInterface>(factory, 6)(factory, out value);}));
            Set(7, new WinRtGetInterface((nint self, out nint value) => {Record();return Method<WinRtGetInterface>(factory, 7)(factory, out value);}));
            Set(12, new WinRtAddReportEvent((nint self, nint handler, out long token) => {
                Record();Registrations++;var result = Method<WinRtAddReportEvent>(factory, 12)(factory, handler, out token);if (result >= 0) Active++;return result;
            }));
            Set(13, new WinRtRemoveReportEvent((nint self, long token) => {
                Record();Removals++;RemovalResult = Method<WinRtRemoveReportEvent>(factory, 13)(factory, token);if (RemovalResult >= 0) Active--;return RemovalResult;
            }));
            return proxy;
        }
        public void Release(nint value)
        {
            Record();
            if (value == cellularFactory && value != 0) {CellularFactoryReleases++;cellularFactory = 0;}
            if (value != proxy) {native.Release(value);return;}
            FactoryReleases++;try {native.Release(factory);} finally {Marshal.FreeHGlobal(proxy);Marshal.FreeHGlobal(table);proxy = table = factory = 0;}
        }
        public void Uninitialize() {Record();Uninitializations++;native.Uninitialize();Stopped.TrySetResult();}
    }
    private sealed partial class ConnectivityFixture : IWindowsConnectivityRuntime
    {
        private readonly List<Delegate> delegates = [];
        private readonly List<nint> allocations = [];
        private readonly nint factory, profile, cost, plan, inbound, outbound;
        private readonly Dictionary<long, nint> handlers = [];
        private readonly object gate = new();
        private long nextToken;
        internal readonly Dictionary<nint, int> References = [];
        internal readonly List<int> Threads = [];
        internal readonly TaskCompletionSource Stopped = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource ReadStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly ManualResetEventSlim ContinueRead = new(true);
        internal int Initializations, Uninitializations, Reads, Registrations, Removals, LevelReads;
        internal int Level = 3, Cost = 1;
        internal int LevelResult, CostResult, CostTypeResult, ProfileResult, AddResult;
        internal bool NoProfile, NoCost, RetainFailedHandler;
        internal nint FailedHandler;
        internal bool NoPlan;
        internal ulong? InboundRate = 1234567890123, OutboundRate = 32000000;
        internal int PlanReads, InboundReads, OutboundReads;
        internal int PlanResult, InboundResult, OutboundResult, InboundValueResult, OutboundValueResult;
        internal TaskCompletionSource PlanStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly ManualResetEventSlim ContinuePlan = new(true);
        internal void PausePlan() {PlanStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);ContinuePlan.Reset();}
        internal ConnectivityFixture()
        {
            factory = Interface(14);profile = Interface(15);cost = Interface(10);
            plan = Interface(12);inbound = Interface(7);outbound = Interface(7);
            Set(factory, 7, new WinRtGetInterface((nint self, out nint value) => {
                Record();Reads++;value = NoProfile ? 0 : Take(profile);ReadStarted.TrySetResult();
                return ContinueRead.Wait(TimeSpan.FromSeconds(3)) ? ProfileResult : unchecked((int)0x80004005);
            }));
            Set(profile, 7, new WinRtGetInt32((nint self, out int value) => {Record();LevelReads++;value = Level;return LevelResult;}));
            Set(profile, 9, new WinRtGetInterface((nint self, out nint value) => {Record();value = NoCost ? 0 : Take(cost);return CostResult;}));
            Set(cost, 6, new WinRtGetInt32((nint self, out int value) => {Record();value = Cost;return CostTypeResult;}));
            Set(profile, 10, new WinRtGetInterface((nint self, out nint value) => {
                Record();PlanReads++;value = NoPlan ? 0 : Take(plan);PlanStarted.TrySetResult();
                return ContinuePlan.Wait(TimeSpan.FromSeconds(3)) ? PlanResult : unchecked((int)0x80004005);
            }));
            Set(plan, 8, new WinRtGetInterface((nint self, out nint value) => {Record();value = InboundRate.HasValue ? Take(inbound) : 0;return InboundResult;}));
            Set(plan, 9, new WinRtGetInterface((nint self, out nint value) => {Record();value = OutboundRate.HasValue ? Take(outbound) : 0;return OutboundResult;}));
            Set(inbound, 6, new WinRtGetUInt64((nint self, out ulong value) => {Record();InboundReads++;value = InboundRate ?? 0;return InboundValueResult;}));
            Set(outbound, 6, new WinRtGetUInt64((nint self, out ulong value) => {Record();OutboundReads++;value = OutboundRate ?? 0;return OutboundValueResult;}));
            Set(factory, 12, new WinRtAddReportEvent((nint self, nint handler, out long token) => {
                Record();Registrations++;token = 0;
                if (AddResult < 0) {if (RetainFailedHandler) {Marshal.AddRef(handler);FailedHandler = handler;}return AddResult;}
                lock (gate) {token = ++nextToken;Marshal.AddRef(handler);handlers.Add(token, handler);}return 0;
            }));
            Set(factory, 13, new WinRtRemoveReportEvent((nint self, long token) => {
                Record();Removals++;nint handler;lock (gate) {if (!handlers.Remove(token, out handler)) return unchecked((int)0x80070057);}
                Marshal.Release(handler);return 0;
            }));
        }
        internal int HandlerCount {get {lock (gate) return handlers.Count;}}
        internal nint RetainFirstHandler() {lock (gate) {var handler = handlers.Values.First();Marshal.AddRef(handler);return handler;}}
        internal void Fire()
        {
            nint[] current;lock (gate) {current = handlers.Values.ToArray();foreach(var handler in current) Marshal.AddRef(handler);}
            foreach (var handler in current) {try {Invoke(handler);} finally {Marshal.Release(handler);}}
        }
        internal static void Invoke(nint handler) => Marshal.GetDelegateForFunctionPointer<WinRtNetworkStatusInvoke>(Marshal.ReadIntPtr(Marshal.ReadIntPtr(handler), 3 * nint.Size))(handler, 0);
        private nint Allocate(int size) {var memory = Marshal.AllocHGlobal(size);Marshal.Copy(new byte[size], 0, memory, size);allocations.Add(memory);return memory;}
        private nint Interface(int slots) {var value = Allocate(nint.Size);Marshal.WriteIntPtr(value, Allocate(slots * nint.Size));References[value] = 0;return value;}
        private void Set(nint value, int slot, Delegate callback) {delegates.Add(callback);Marshal.WriteIntPtr(Marshal.ReadIntPtr(value), slot * nint.Size, Marshal.GetFunctionPointerForDelegate(callback));}
        private nint Take(nint value) {References[value]++;return value;}
        private void Record() => Threads.Add(Environment.CurrentManagedThreadId);
        public int Initialize() {Record();Initializations++;return 0;}
        public nint ActivateFactory() {Record();return Take(factory);}
        public void Release(nint value) {Record();if (--References[value] < 0) throw new Exception("Connectivity interface released twice.");}
        public void Uninitialize() {Record();Uninitializations++;foreach(var value in allocations) Marshal.FreeHGlobal(value);allocations.Clear();Stopped.TrySetResult();}
    }
    private static async Task Error(ErrorCode code, Func<Task> action)
    {
        try {await action();} catch (DeviceReadoutException error) when (error.Code == code) {return;}
        throw new Exception($"Expected {code}.");
    }
    private static void Check(bool condition, string message) {if (!condition) throw new Exception(message);}
}
