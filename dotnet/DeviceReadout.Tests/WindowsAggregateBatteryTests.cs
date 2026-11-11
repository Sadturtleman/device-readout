using System.Runtime.Versioning;
using System.Runtime.InteropServices;
using DeviceReadout;
using DeviceReadout.Windows;

[SupportedOSPlatform("windows")]
internal static class WindowsAggregateBatteryTests
{
    internal static IEnumerable<(string Name, Func<Task> Run)> Cases() => [
        ("Windows current battery exposes the OS aggregate with distinct capacities and signed power", AggregateFields),
        ("real Windows aggregate battery reads, registers events and releases its runtime on the worker", NativeAggregate),
        ("Windows aggregate WinRT nullable properties and report callbacks preserve values and release references", AggregateAbi),
        ("Windows aggregate remaining runtime preserves sentinels and does not become charging time", AggregateRuntime)
    ];
    private static async Task AggregateRuntime()
    {
        var report = new AggregateFixture();var power = new WindowsPowerTests.PowerPlatformFixture {State = new(0, 0, 2, 40, 600, 1500)};
        using var access = new DeviceAccess(new WindowsCollector(new EmptyDevices(), power, report));
        var target = (await access.Batteries.Current())!;
        var value = await access.Get(target);
        Check(value.TimeToEmpty == TimeSpan.FromSeconds(600) && value.TimeToFull is null, "native remaining seconds, not full-battery runtime as charging time");
        power.State = new(0, 0, 4, 0, 0, 1500);
        Check((await access.Get(target)).TimeToEmpty == TimeSpan.Zero, "zero remaining runtime is valid");
        power.State = new(0, 0, 2, 40, uint.MaxValue, 1500);
        Check((await access.Get(target)).TimeToEmpty is null, "unknown native seconds");
        power.State = new(255, 0, 255, 255, 600, uint.MaxValue);
        Check((await access.Get(target)).TimeToEmpty == TimeSpan.FromSeconds(600), "independently available runtime survives unknown power flags");
        power.State = new(1, 0, 8, 40, 600, 1500);
        Check((await access.Get(target)).TimeToEmpty is null, "external-power runtime has no discharge meaning");
        power.ReadFailure = new DeviceReadoutException(ErrorCode.PermissionDenied, "Optional native runtime query failed.");
        value = await access.Get(target);
        Check(value.TimeToEmpty is null && value.DesignEnergyMilliwattHours == 60000 && value.Present == true, "optional power-status failure preserves readable aggregate fields");
    }
    private static async Task AggregateAbi()
    {
        var runtime = new RuntimeFixture();
        using var access = new DeviceAccess(new WindowsCollector(new EmptyDevices(), new WindowsPowerTests.PowerPlatformFixture(), new WindowsAggregateBatteryPlatform(runtime)));
        var current = (await access.Batteries.Current())!;
        var first = await access.Get(current);
        Check(first.Present == true && first.Level == 0.4 && first.ChargeRateMilliwatts == -5000 && first.DesignEnergyMilliwattHours == 60000, "native nullable Int32 getters decoded");
        await using (var stream = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(current).GetAsyncEnumerator()) {
            Check(await stream.MoveNextAsync(), "native report watch initial state");
            runtime.Values[0] = 0;runtime.Values[3] = 0;runtime.Status = 2;
            runtime.Emit();runtime.Emit();
            for(var index = 0; index < 2; index++) {
                Check(await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)) && stream.Current.Level == 0 && stream.Current.ChargeRateMilliwatts == 0 && stream.Current.State == BatteryState.Idle, "equal report updates retain zero and idle status");
            }
        }
        Check(runtime.Handler == 0, "native event reference released");
        runtime.Values[2] = null;runtime.Failures[0] = unchecked((int)0x80004005);runtime.Status = 99;
        var partial = await access.Get(current);
        Check(partial.State is null && partial.Charging is null && partial.Present is null && partial.FullChargeEnergyMilliwattHours is null && partial.Level is null && partial.ChargeRateMilliwatts is null && partial.DesignEnergyMilliwattHours == 60000, "partial failures, native nullable values and unknown status");
        Array.Fill(runtime.Failures, unchecked((int)0x80070005));
        try {await access.Get(current);throw new Exception("Expected all-field failure");}
        catch (DeviceReadoutException error) when (error.Code == ErrorCode.PermissionDenied) { }
        Array.Clear(runtime.Failures);runtime.Status = 0;
        var absent = await access.Get(current);
        Check(absent.Present == false && absent.DesignEnergyMilliwattHours is null && absent.Level is null, "not-present status suppresses stale numeric fields");
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(1));
        Check(runtime.ReadThreads.Distinct().Count() == 1, "activation, native reads, reference release and uninitialization use one lane");
    }
    private sealed class RuntimeFixture : IWindowsBatteryRuntime
    {
        internal readonly int?[] Values = [-5000, 60000, 50000, 20000];
        internal readonly int[] Failures = new int[5];
        internal int Status = 1;
        internal nint Handler;
        internal readonly List<int> ReadThreads = [];
        internal readonly TaskCompletionSource Stopped = new(TaskCreationOptions.RunContinuationsAsynchronously);
        private readonly Dictionary<nint, int> references = [];
        private readonly List<nint> allocations = [];
        private readonly List<Delegate> methods = [];
        private nint factory, battery, report;
        private readonly nint[] boxed = new nint[4];
        private void Record() => ReadThreads.Add(Environment.CurrentManagedThreadId);
        public int Initialize() {Record();return 1;}
        public nint ActivateFactory()
        {
            Record();
            if (factory == 0) {
                factory = Object(7);battery = Object(10);report = Object(11);
                Set(factory, 6, new WinRtGetInterface((nint _, out nint value) => {Record();value = Retain(battery);return 0;}));
                Set(battery, 7, new WinRtGetInterface((nint _, out nint value) => {Record();value = Retain(report);return 0;}));
                Set(battery, 8, new WinRtAddReportEvent((nint _, nint handler, out long token) => {Record();Handler = handler;HandlerMethod<WindowsBatteryReportHandler.ReferenceDelegate>(1)(handler);token = 42;return 0;}));
                Set(battery, 9, new WinRtRemoveReportEvent((nint _, long token) => {Record();Check(token == 42, "event token");HandlerMethod<WindowsBatteryReportHandler.ReferenceDelegate>(2)(Handler);Handler = 0;return 0;}));
                for(var index = 0; index < 4; index++) {
                    var field = index;boxed[field] = Object(7);
                    Set(report, 6 + field, new WinRtGetInterface((nint _, out nint value) => {Record();value = Failures[field] < 0 || Values[field] is null ? 0 : Retain(boxed[field]);return Failures[field];}));
                    Set(boxed[field], 6, new WinRtGetInt32((nint _, out int value) => {Record();value = Values[field]!.Value;return 0;}));
                }
                Set(report, 10, new WinRtGetInt32((nint _, out int value) => {Record();value = Status;return Failures[4];}));
            }
            return Retain(factory);
        }
        private nint Object(int slots)
        {
            var instance = Marshal.AllocHGlobal(nint.Size);var table = Marshal.AllocHGlobal(slots * nint.Size);
            allocations.Add(instance);allocations.Add(table);Marshal.WriteIntPtr(instance, table);references.Add(instance, 0);return instance;
        }
        private void Set(nint instance, int slot, Delegate method) {methods.Add(method);Marshal.WriteIntPtr(Marshal.ReadIntPtr(instance), slot * nint.Size, Marshal.GetFunctionPointerForDelegate(method));}
        private nint Retain(nint instance) {references[instance]++;return instance;}
        public void Release(nint instance) {Record();Check(references[instance] > 0, "owned COM reference");references[instance]--;}
        private T HandlerMethod<T>(int slot) where T : Delegate => Marshal.GetDelegateForFunctionPointer<T>(Marshal.ReadIntPtr(Marshal.ReadIntPtr(Handler), slot * nint.Size));
        internal void Emit() {Check(Handler != 0 && HandlerMethod<WindowsBatteryReportHandler.InvokeDelegate>(3)(Handler, battery, 0) == 0, "native callback returns successfully");}
        public void Uninitialize()
        {
            Record();
            try {Check(references.Values.All(count => count == 0) && Handler == 0, "all COM references and event handlers released");}
            catch (Exception error) {Stopped.TrySetException(error);throw;}
            finally {foreach(var pointer in allocations) Marshal.FreeHGlobal(pointer);methods.Clear();}
            Stopped.TrySetResult();
        }
    }
    private static async Task NativeAggregate()
    {
        var runtime = new RuntimeProbe();var platform = new AggregateProbe(runtime);
        using var access = new DeviceAccess(new WindowsCollector(aggregatePlatform: platform));
        var current = await access.Batteries.Current();Check(current is not null, "real OS aggregate target");
        var snapshot = await access.Get(current!);
        Check(snapshot.Present.HasValue, "native aggregate reports presence even on a batteryless host");
        if (snapshot.Present == false) Check(snapshot.Level is null && snapshot.Charging is null && snapshot.ChargeRateMilliwatts is null, "no fabricated batteryless data");
        await using (var stream = access.Watch(current!).GetAsyncEnumerator()) {
            Check(await stream.MoveNextAsync(), "native aggregate initial watch state");
            Check(platform.Active == 1, "actual WinRT ReportUpdated registration");
        }
        Check(platform.Active == 0 && platform.ReleaseFailure is null, "native ReportUpdated handler removed successfully");
        Check(!runtime.Stopped.Task.IsCompleted, "closing one watch retains the context runtime");
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.Initializations == 1 && runtime.Uninitializations == 1 && runtime.Threads.Distinct().Count() == 1, "balanced WinRT lifecycle on one collection worker");
        Console.WriteLine($"Native aggregate battery: present={snapshot.Present}, level={snapshot.Level}, state={snapshot.State}; report event and runtime cleanup passed.");
    }
    private sealed class RuntimeProbe : IWindowsBatteryRuntime
    {
        private readonly IWindowsBatteryRuntime native = new WindowsAggregateBatteryPlatform.BatteryRuntime();
        internal readonly List<int> Threads = [];
        internal int Initializations, Uninitializations;
        internal readonly TaskCompletionSource Stopped = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public int Initialize() {Threads.Add(Environment.CurrentManagedThreadId);Initializations++;return native.Initialize();}
        public nint ActivateFactory() {Threads.Add(Environment.CurrentManagedThreadId);return native.ActivateFactory();}
        public void Release(nint instance) {Threads.Add(Environment.CurrentManagedThreadId);native.Release(instance);}
        public void Uninitialize() {Threads.Add(Environment.CurrentManagedThreadId);native.Uninitialize();Uninitializations++;Stopped.TrySetResult();}
    }
    private sealed class AggregateProbe(IWindowsBatteryRuntime runtime) : IWindowsAggregateBatteryPlatform
    {
        private readonly IWindowsAggregateBatteryPlatform native = new WindowsAggregateBatteryPlatform(runtime);
        internal int Active;
        internal Exception? ReleaseFailure;
        public WindowsAggregateReport? Read() => native.Read();
        public IDisposable? Observe(Action changed, Action<Exception> fail)
        {
            var subscription = native.Observe(changed, fail);if (subscription is null) return null;
            Active++;return new Subscription(() => {
                try {subscription.Dispose();} catch (Exception error) {ReleaseFailure = error;throw;}
                finally {Active--;}
            });
        }
        public void Dispose() => native.Dispose();
        private sealed class Subscription(Action release) : IDisposable {public void Dispose() => release();}
    }
    internal sealed class UnavailablePlatform : IWindowsAggregateBatteryPlatform
    {public WindowsAggregateReport? Read() => null;}
    private sealed class EmptyDevices : IWindowsBatteryPlatform
    {
        public IReadOnlyList<string> Enumerate(CancellationToken token) => [];
        public IWindowsBatteryDevice Open(string path) => throw new Exception("Aggregate must not open an individual pack.");
    }
    private static async Task AggregateFields()
    {
        var platform = new AggregateFixture();
        var caller = Environment.CurrentManagedThreadId;
        using var access = new DeviceAccess(new WindowsCollector(new EmptyDevices(), new WindowsPowerTests.PowerPlatformFixture(), platform));
        Check(platform.Reads == 0, "inert aggregate construction");
        var current = await access.Batteries.Current();Check(current is not null, "OS aggregate is the default target");
        var snapshot = await access.Get(current!);
        Check(snapshot.Present == true && snapshot.State == BatteryState.Discharging && snapshot.Charging == false, "native aggregate status");
        Check(snapshot.Level == 0.4 && snapshot.ChargeRateMilliwatts == -5000, "native ratio and signed power");
        Check(snapshot.DesignEnergyMilliwattHours == 60000 && snapshot.FullChargeEnergyMilliwattHours == 50000 && snapshot.RemainingEnergyMilliwattHours == 20000, "design/full/remaining capacities are distinct");
        Check(snapshot.CurrentMicroamps is null && snapshot.VoltageMillivolts is null && snapshot.TimeToFull is null, "no synthetic current, voltage or charging time");
        var listed = await access.Batteries.List();
        Check(listed.Length == 1, "aggregate is discoverable without individual devices");
        Check(listed.Contains(current!), "current target compares equal to its discovered handle");
        var same = await access.WithPollInterval(TimeSpan.FromSeconds(2)).Batteries.Current();
        Check(current == same && new HashSet<Entity<BatterySnapshot>> {current!, same!}.Count == 1, "configuration views preserve handle equality and hashing");
        using var other = new DeviceAccess(new WindowsCollector(new EmptyDevices(), new WindowsPowerTests.PowerPlatformFixture(), new AggregateFixture()));
        Check(current != await other.Batteries.Current(), "matching native roles in independent contexts are distinct");
        Check(platform.Threads.All(thread => thread != caller) && platform.Threads.Distinct().Count() == 1, "aggregate reads use collection lane");
        access.Dispose();await platform.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(1));
    }
    private sealed class AggregateFixture : IWindowsAggregateBatteryPlatform
    {
        internal WindowsAggregateReport? Report = new(1, -5000, 60000, 50000, 20000);
        internal int Reads;
        internal readonly List<int> Threads = [];
        internal readonly TaskCompletionSource Stopped = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public WindowsAggregateReport? Read() {Reads++;Threads.Add(Environment.CurrentManagedThreadId);return Report;}
        public void Dispose() {Threads.Add(Environment.CurrentManagedThreadId);Stopped.TrySetResult();}
    }
    private static void Check(bool condition, string message) {if (!condition) throw new Exception(message);}
}
