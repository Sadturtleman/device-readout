using DeviceReadout;
using DeviceReadout.Windows;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;

[SupportedOSPlatform("windows")]
internal static class WindowsProximityAbiTests
{
    internal static IEnumerable<(string Name, Func<Task> Run)> Cases() => [
        ("Windows native sensor proximity state preserves false and duplicate events without display control", Near),
        ("Windows native sensor proximity distance converts nullable unsigned millimeters and coexists with near state", Distance),
        ("Windows native sensor proximity held synchronous calls preserve deadlines and release late native references", HeldCalls),
        ("Windows native sensor proximity field failures stay nullable and preserve independent observations", FieldFailures)
    ];

    private static async Task Near()
    {
        var runtime = new RuntimeFixture();
        using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
        var target = (await access.Sensors.List(Entities.ProximityNear)).Single();
        var description = await access.Describe(target);
        Check(description.Kind == SensorKind.ProximityNear && description.Name == "ABI proximity" && description.MinimumInterval is null && description.MaximumRange is null,
            "proximity Boolean metadata does not claim a numeric range or report interval");
        Check((await access.Capabilities.Get(target)).Readable == true && runtime.CurrentReads == 0 && runtime.Registrations == 0, "native discovery and description stay passive");
        Check((await access.Get(target)).Value == false, "native false is a valid near-state sample");
        await TestCompletion.Until(() => runtime.HandlerCount == 0, "one-shot proximity listener released");
        await using var watch = access.WithSensorSamplingRate(SensorSamplingRate.AtHertz(60)).Watch(target).GetAsyncEnumerator();
        Check(await watch.MoveNextAsync() && watch.Current.Value == false, "initial false state is delivered");
        runtime.Detected = 1;runtime.Fire();runtime.Fire();
        Check(await watch.MoveNextAsync() && watch.Current.Value == true, "native near event");
        Check(await watch.MoveNextAsync() && watch.Current.Value == true, "equal proximity state events are retained");
        runtime.Detected = 0;runtime.Fire();
        Check(await watch.MoveNextAsync() && watch.Current.Value == false, "native far event");
        await watch.DisposeAsync();access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.Registrations == 2 && runtime.Removals == 2 && runtime.DisplayCalls == 0 && runtime.RangeReads == 0,
            "native leases balance without display control or irrelevant measurement metadata");
    }

    private static async Task Distance()
    {
        var runtime = new RuntimeFixture {Distance = 37, MaximumDistance = 250};
        using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
        var target = (await access.Sensors.List(Entities.ProximityDistance)).Single();
        var near = (await access.Sensors.List(Entities.ProximityNear)).Single();
        var description = await access.Describe(target);
        Check(description.Kind == SensorKind.ProximityDistance && description.MaximumRange == 0.25 && description.MinimumInterval is null,
            "distance metadata uses meters and no invented native sampling interval");
        Check(runtime.RangeReads == 1 && runtime.CurrentReads == 0 && runtime.Registrations == 0, "maximum range is passive metadata");
        Check((await access.Get(target)).Value == 0.037, "nullable unsigned native millimeters become meters");
        await TestCompletion.Until(() => runtime.HandlerCount == 0, "one-shot distance listener released");
        await using var distanceWatch = access.WithSensorSamplingRate(SensorSamplingRate.AtHertz(5)).Watch(target).GetAsyncEnumerator();
        await using var nearWatch = access.WithSensorSamplingRate(SensorSamplingRate.AtHertz(60)).Watch(near).GetAsyncEnumerator();
        Check(await distanceWatch.MoveNextAsync() && distanceWatch.Current.Value == 0.037, "initial selected distance");
        Check(await nearWatch.MoveNextAsync() && nearWatch.Current.Value == false && runtime.HandlerCount == 2, "near and distance sessions coexist without inferring near from distance");
        runtime.Distance = 0;runtime.Detected = 1;runtime.Fire();runtime.Fire();
        for (var i = 0; i < 2; i++) {
            Check(await distanceWatch.MoveNextAsync() && distanceWatch.Current.Value == 0, "zero and duplicate distances retained");
            Check(await nearWatch.MoveNextAsync() && nearWatch.Current.Value == true, "matching native near events retained");
        }
        runtime.Distance = null;runtime.Detected = 0;runtime.Fire();
        Check(await distanceWatch.MoveNextAsync() && distanceWatch.Current.Value is null, "missing native distance does not become zero");
        Check(await nearWatch.MoveNextAsync() && nearWatch.Current.Value == false, "near state remains independently readable");
        await nearWatch.DisposeAsync();
        await TestCompletion.Until(() => runtime.HandlerCount == 1, "closing near leaves distance subscribed");
        runtime.Distance = uint.MaxValue;runtime.Fire();
        Check(await distanceWatch.MoveNextAsync() && distanceWatch.Current.Value == 4294967.295, "unsigned values are not reinterpreted as negative signed distances");
        await distanceWatch.DisposeAsync();access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.Registrations == 3 && runtime.Removals == 3 && runtime.DisplayCalls == 0, "both native entity sessions release without display side effects");
    }

    private static async Task HeldCalls()
    {
        await Verify(Entities.ProximityNear, HoldPoint.Open);
        await Verify(Entities.ProximityDistance, HoldPoint.Open);
        await Verify(Entities.ProximityNear, HoldPoint.Near);
        await Verify(Entities.ProximityDistance, HoldPoint.DistanceProperty);
        await Verify(Entities.ProximityDistance, HoldPoint.DistanceValue);
        await Verify(Entities.ProximityDistance, HoldPoint.RangeProperty, metadata: true);
        await Verify(Entities.ProximityDistance, HoldPoint.RangeValue, metadata: true);
        static async Task Verify<T>(Entity<T> kind, HoldPoint point, bool metadata = false) where T : DeviceSnapshot
        {
            var runtime = new RuntimeFixture {Distance = 50, MaximumDistance = 200, Held = point};
            using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
            var target = (await access.Sensors.List(kind)).Single();
            var ticks = 0;using var heartbeat = new Timer(_ => Interlocked.Increment(ref ticks), null, 0, 5);
            var caller = Environment.CurrentManagedThreadId;
            try {
                var bounded = access.WithReadTimeout(TimeSpan.FromMilliseconds(150));
                Task pending = metadata ? bounded.Describe(target) : bounded.Get(target);
                await runtime.Started.Task.WaitAsync(TimeSpan.FromSeconds(2));
                try {await pending.WaitAsync(TimeSpan.FromSeconds(1));throw new Exception("Expected held proximity read timeout.");}
                catch (DeviceReadoutException error) when (error.Code == ErrorCode.ReadTimeout) { }
                Check(!runtime.Continue.IsSet && runtime.HeldThread != caller && Volatile.Read(ref ticks) > 2, "host continues and deadline completes while native proximity call stays on its worker");
                var elapsed = System.Diagnostics.Stopwatch.StartNew();access.Dispose();
                Check(elapsed.Elapsed < TimeSpan.FromMilliseconds(500) && !runtime.Stopped.Task.IsCompleted, "context disposal does not join held proximity calls");
            } finally {runtime.Continue.Set();access.Dispose();}
            await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
            if (point == HoldPoint.Open) Check(runtime.CurrentReads == 0 && runtime.Registrations == 0, "late native sensor is released before measurement or subscription");
            if (point == HoldPoint.DistanceProperty) Check(runtime.DistanceValueReads == 0, "late distance reference is released without querying its value");
            if (point == HoldPoint.RangeProperty) Check(runtime.RangeValueReads == 0, "late range reference is released without querying its value");
            Check(runtime.Removals == runtime.Registrations && runtime.DisplayCalls == 0, "late completion balances listeners and does not control the screen");
        }
    }

    private static async Task FieldFailures()
    {
        var runtime = new RuntimeFixture {Distance = 50, MaximumDistance = 200};
        using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
        var near = (await access.Sensors.List(Entities.ProximityNear)).Single();
        var distance = (await access.Sensors.List(Entities.ProximityDistance)).Single();
        await using var nearWatch = access.Watch(near).GetAsyncEnumerator();
        await using var distanceWatch = access.Watch(distance).GetAsyncEnumerator();
        Check(await nearWatch.MoveNextAsync() && nearWatch.Current.Value == false, "initial Boolean field");
        Check(await distanceWatch.MoveNextAsync() && distanceWatch.Current.Value == 0.05, "initial distance field");
        runtime.NearStatus = unchecked((int)0x80004005);runtime.Fire();
        Check(await nearWatch.MoveNextAsync() && nearWatch.Current.Value is null, "native Boolean getter failure is nullable");
        Check(await distanceWatch.MoveNextAsync() && distanceWatch.Current.Value == 0.05, "near getter failure does not erase readable distance");
        runtime.NearStatus = 0;runtime.Detected = 2;runtime.Fire();
        Check(await nearWatch.MoveNextAsync() && nearWatch.Current.Value is null, "invalid native Boolean is not silently interpreted as true");
        Check(await distanceWatch.MoveNextAsync() && distanceWatch.Current.Value == 0.05, "invalid Boolean does not affect distance");
        runtime.Detected = 0;
        foreach (var failValue in new[] {false, true}) {
            if (failValue) runtime.DistanceValueStatus = unchecked((int)0x80004005);else runtime.DistanceStatus = unchecked((int)0x80004005);
            runtime.Fire();
            Check(await distanceWatch.MoveNextAsync() && distanceWatch.Current.Value is null, "native nullable-reference or value failure is unavailable distance");
            Check(await nearWatch.MoveNextAsync() && nearWatch.Current.Value == false, "Boolean remains independent of failed distance properties");
            runtime.DistanceStatus = 0;runtime.DistanceValueStatus = 0;runtime.Fire();
            Check(await distanceWatch.MoveNextAsync() && distanceWatch.Current.Value == 0.05, "distance recovers on the next complete reading");
            Check(await nearWatch.MoveNextAsync() && nearWatch.Current.Value == false, "equal far event retained during recovery");
        }
        runtime.RangeStatus = unchecked((int)0x80004005);
        Check((await access.Describe(distance)).MaximumRange is null, "failed range property is null metadata");
        runtime.RangeStatus = 0;runtime.RangeValueStatus = unchecked((int)0x80004005);
        Check((await access.Describe(distance)).MaximumRange is null, "failed nullable range value is null metadata");
        runtime.RangeValueStatus = 0;runtime.MaximumDistance = null;
        Check((await access.Describe(distance)).MaximumRange is null, "missing native range is not zero");
        runtime.MaximumDistance = 200;
        Check((await access.Describe(distance)).MaximumRange == 0.2, "range metadata recovers");
        await nearWatch.DisposeAsync();await distanceWatch.DisposeAsync();access.Dispose();
        await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.Registrations == 2 && runtime.Removals == 2, "nullable fields do not restart or terminate either watch");
    }

    private enum HoldPoint { None, Open, Near, DistanceProperty, DistanceValue, RangeProperty, RangeValue }

    // Independent WinRT vtable fixture from Windows SDK 10.0.26100.0 declarations.
    private sealed class RuntimeFixture : IWindowsSensorRuntime
    {
        private readonly object gate = new();
        private readonly Dictionary<nint, int> references = [];
        private readonly List<nint> allocations = [];
        private readonly List<Delegate> delegates = [];
        private readonly Dictionary<long, nint> handlers = [];
        private readonly nint factory, enumeration, collection, information, sensor, reading, args;
        private long nextToken;
        internal byte Detected;
        internal uint? Distance, MaximumDistance;
        internal int NearStatus, DistanceStatus, DistanceValueStatus, RangeStatus, RangeValueStatus;
        internal HoldPoint Held;
        internal int HeldThread, DistanceValueReads, RangeValueReads;
        internal readonly TaskCompletionSource Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly ManualResetEventSlim Continue = new(false);
        internal int CurrentReads, Registrations, Removals, DisplayCalls, RangeReads;
        internal int HandlerCount {get {lock (gate) return handlers.Count;}}
        internal readonly TaskCompletionSource Stopped = new(TaskCreationOptions.RunContinuationsAsynchronously);

        internal RuntimeFixture()
        {
            factory = Object(8);enumeration = Object(11);collection = Object(8);information = Object(8);
            sensor = Object(13);reading = Object(9);args = Object(7);
            Set(factory, 6, new WinRtGetInterface((nint self, out nint value) => {value = Text("proximity selector");return 0;}));
            Set(factory, 7, new SensorStringCall((nint self, nint id, out nint value) => {value = Take(sensor);Hold(HoldPoint.Open);return 0;}));
            Set(enumeration, 10, new SensorStringCall((nint self, nint selector, out nint value) => {value = Operation(collection);return 0;}));
            Set(collection, 7, new SensorGetUInt((nint self, out uint size) => {size = 1;return 0;}));
            Set(collection, 6, new SensorGetAt((nint self, uint index, out nint item) => {item = Take(information);return index == 0 ? 0 : unchecked((int)0x8000000b);}));
            Set(information, 6, new WinRtGetInterface((nint self, out nint value) => {value = Text("abi-proximity");return 0;}));
            Set(information, 7, new WinRtGetInterface((nint self, out nint value) => {value = Text("ABI proximity");return 0;}));
            Set(sensor, 6, new WinRtGetInterface((nint self, out nint value) => {value = Text("abi-proximity");return 0;}));
            Set(sensor, 7, new WinRtGetInterface((nint self, out nint value) => {RangeReads++;value = MaximumDistance is { } distance ? Reference(distance, range: true) : 0;Hold(HoldPoint.RangeProperty);return RangeStatus;}));
            Set(sensor, 8, new WinRtGetInterface((nint self, out nint value) => {RangeReads++;value = 0;return 0;}));
            Set(sensor, 9, new WinRtGetInterface((nint self, out nint value) => {CurrentReads++;value = Take(reading);return 0;}));
            Set(sensor, 10, new WinRtAddReportEvent((nint self, nint handler, out long token) => {
                var iid = new Guid("9f7e222b-892a-5e68-b08a-10384b5f92b9");
                Check(Marshal.QueryInterface(handler, in iid, out var supported) == 0, "proximity event handler interface");Marshal.Release(supported);
                Marshal.AddRef(handler);lock (gate) {token = ++nextToken;handlers.Add(token, handler);Registrations++;}return 0;
            }));
            Set(sensor, 11, new WinRtRemoveReportEvent((nint self, long token) => {
                lock (gate) {Check(handlers.Remove(token, out var handler), "matching proximity token");Marshal.Release(handler);Removals++;}return 0;
            }));
            Set(sensor, 12, new WinRtGetInterface((nint self, out nint value) => {DisplayCalls++;value = 0;return unchecked((int)0x80004001);}));
            Set(reading, 7, new WinRtGetBoolean((nint self, out byte value) => {value = Detected;Hold(HoldPoint.Near);return NearStatus;}));
            Set(reading, 8, new WinRtGetInterface((nint self, out nint value) => {value = Distance is { } distance ? Reference(distance) : 0;Hold(HoldPoint.DistanceProperty);return DistanceStatus;}));
            Set(args, 6, new WinRtGetInterface((nint self, out nint value) => {value = Take(reading);return 0;}));
        }
        private void Hold(HoldPoint point)
        {
            if (Held != point) return;
            HeldThread = Environment.CurrentManagedThreadId;Started.TrySetResult();
            Check(Continue.Wait(TimeSpan.FromSeconds(5)), "held proximity call was externally released");
        }
        private nint Reference(uint number, bool range = false)
        {
            var reference = Object(7);
            Set(reference, 6, new SensorGetUInt((nint self, out uint value) => {
                if (range) RangeValueReads++;else DistanceValueReads++;
                value = number;Hold(range ? HoldPoint.RangeValue : HoldPoint.DistanceValue);return range ? RangeValueStatus : DistanceValueStatus;
            }));
            return Take(reference);
        }
        private nint Operation(nint result)
        {
            var operation = Object(9);var info = Object(11);
            Set(operation, 0, new Query((nint self, in Guid iid, out nint value) => {
                value = iid == new Guid("00000036-0000-0000-c000-000000000046") ? Take(info) : 0;
                return value == 0 ? unchecked((int)0x80004002) : 0;
            }));
            Set(operation, 8, new WinRtGetInterface((nint self, out nint value) => {value = Take(result);return 0;}));
            Set(info, 7, new WinRtGetInt32((nint self, out int value) => {value = 1;return 0;}));
            Set(info, 8, new WinRtGetInt32((nint self, out int value) => {value = 0;return 0;}));
            Set(info, 9, new WinRtNoArguments(_ => 0));Set(info, 10, new WinRtNoArguments(_ => 0));
            return Take(operation);
        }
        internal void Fire()
        {
            nint[] current;lock (gate) current = handlers.Values.ToArray();
            foreach (var handler in current) {
                var invoke = Marshal.GetDelegateForFunctionPointer<WinRtCellularEventInvoke>(Marshal.ReadIntPtr(Marshal.ReadIntPtr(handler), nint.Size * 3));
                Check(invoke(handler, sensor, args) == 0, "proximity callback never unwinds into native caller");
            }
        }
        private nint Object(int slots)
        {
            var instance = Marshal.AllocHGlobal(nint.Size);var table = Marshal.AllocHGlobal(slots * nint.Size);
            for (var slot = 0; slot < slots; slot++) Marshal.WriteIntPtr(table, slot * nint.Size, 0);
            Marshal.WriteIntPtr(instance, table);allocations.Add(instance);allocations.Add(table);references.Add(instance, 0);return instance;
        }
        private void Set(nint instance, int slot, Delegate callback) {delegates.Add(callback);Marshal.WriteIntPtr(Marshal.ReadIntPtr(instance), slot * nint.Size, Marshal.GetFunctionPointerForDelegate(callback));}
        private nint Take(nint value) {lock (gate) references[value]++;return value;}
        public int Initialize() => 0;
        public nint Factory(string name, Guid iid)
        {
            if (name == "Windows.Devices.Enumeration.DeviceInformation") {
                Check(iid == new Guid("c17f100e-3a46-4a78-8013-769dc9b97390"), "enumeration factory IID");return Take(enumeration);
            }
            Check(name == "Windows.Devices.Sensors.ProximitySensor" && iid == new Guid("29186649-6269-4e57-a5ad-82be80813392"), "proximity factory class and IID");return Take(factory);
        }
        public void Release(nint value) {lock (gate) {Check(references[value] > 0, "owned proximity native reference");references[value]--;}}
        public void Uninitialize()
        {
            try {Check(references.Values.All(count => count == 0) && HandlerCount == 0, "all proximity native references and event registrations released");}
            catch (Exception error) {Stopped.TrySetException(error);throw;}
            finally {foreach (var pointer in allocations) Marshal.FreeHGlobal(pointer);delegates.Clear();}
            Stopped.TrySetResult();
        }
        private static nint Text(string value) {Check(WindowsCreateString(value, value.Length, out var text) == 0, "fixture HSTRING");return text;}
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int Query(nint self, in Guid iid, out nint result);
        [DllImport("combase.dll", CharSet = CharSet.Unicode)] private static extern int WindowsCreateString(string source, int length, out nint value);
    }
    private static void Check(bool condition, string message) {if (!condition) throw new Exception(message);}
}
