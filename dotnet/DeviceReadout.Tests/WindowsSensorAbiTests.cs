using DeviceReadout;
using DeviceReadout.Windows;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;

[SupportedOSPlatform("windows")]
internal static class WindowsSensorAbiTests
{
    internal static IEnumerable<(string Name, Func<Task> Run)> Cases() => [
        ("Windows native sensor ABI decodes scalar readings and balances event and runtime ownership", ScalarAbi),
        ("Windows native sensor sampling requests coexist and restore the original driver interval", SamplingOwnership),
        ("Windows native sensor asynchronous discovery preserves deadlines and cancels owned operations", () => DiscoveryDeadline(false)),
        ("Windows native sensor capability deadlines cancel the underlying native enumeration", () => DiscoveryDeadline(true))
    ];
    private static async Task ScalarAbi()
    {
        foreach (var pressure in new[] {false, true}) {
            var runtime = new RuntimeFixture(pressure);
            using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
            if (pressure) {
                var sensor = (await access.Sensors.List(Entities.Pressure)).Single();
                Check((await access.Describe(sensor)).MinimumInterval == TimeSpan.FromMilliseconds(20), "pressure metadata uses native interval slot");
                Check(runtime.CurrentReads == 0 && runtime.Registrations == 0, "metadata does not measure");
                runtime.Value = 1013.25;Check((await access.Get(sensor)).Value == 101325, "native double hPa converts to Pa");
                await TestCompletion.Until(() => runtime.HandlerCount == 0, "one-shot native pressure handler removed");
                await using var watch = access.Watch(sensor).GetAsyncEnumerator();
                Check(await watch.MoveNextAsync() && watch.Current.Value == 101325, "native current pressure sample");
                runtime.Value = 1000;runtime.Fire();runtime.Fire();
                Check(await watch.MoveNextAsync() && watch.Current.Value == 100000, "native pressure event");
                Check(await watch.MoveNextAsync() && watch.Current.Value == 100000, "duplicate native pressure event");
            } else {
                var sensor = (await access.Sensors.List(Entities.Illuminance)).Single();
                Check((await access.Describe(sensor)).Name == "ABI light", "native device metadata name");
                Check(runtime.CurrentReads == 0 && runtime.Registrations == 0, "light metadata does not measure");
                runtime.Value = 250.5;Check((await access.Get(sensor)).Value == 250.5, "native float lux decoded");
                await TestCompletion.Until(() => runtime.HandlerCount == 0, "one-shot native light handler removed");
                await using var watch = access.Watch(sensor).GetAsyncEnumerator();
                Check(await watch.MoveNextAsync() && watch.Current.Value == 250.5, "native current light sample");
                runtime.Value = 0;runtime.Fire();runtime.Fire();
                Check(await watch.MoveNextAsync() && watch.Current.Value == 0, "zero lux retained");
                Check(await watch.MoveNextAsync() && watch.Current.Value == 0, "equal native event retained");
            }
            await TestCompletion.Until(() => runtime.HandlerCount == 0, "native sensor handlers removed before context close");
            access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
            Check(runtime.Registrations == 2 && runtime.Removals == 2 && runtime.Initializations == 1 && runtime.Uninitializations == 1,
                "get and watch have independent balanced native event leases");
            Check(runtime.IntervalWrites.Count == 0, "platform-default queries preserve driver default interval");
        }
    }

    private static async Task SamplingOwnership()
    {
        var runtime = new RuntimeFixture();
        using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
        var target = (await access.Sensors.List(Entities.Illuminance)).Single();
        await using var slow = access.WithSensorSamplingRate(SensorSamplingRate.AtHertz(25)).Watch(target).GetAsyncEnumerator();
        Check(await slow.MoveNextAsync() && runtime.Interval == 40, "25 Hz request uses 40 milliseconds");
        var fastAccess = access.WithSensorSamplingRate(SensorSamplingRate.AtHertz(100));
        Check(runtime.Interval == 40, "creating configuration does not change an existing native request");
        await using var fast = fastAccess.Watch(target).GetAsyncEnumerator();
        Check(await fast.MoveNextAsync() && runtime.Interval == 20 && runtime.HandlerCount == 2, "fastest request respects 20ms device minimum");
        Check((await access.Get(target)).Value == 250, "default one-shot coexists with configured watches");
        await TestCompletion.Until(() => runtime.HandlerCount == 2, "one-shot handler removed");
        Check(runtime.Interval == 20, "default one-shot cleanup preserves the faster watch");
        await fast.DisposeAsync();await TestCompletion.Until(() => runtime.HandlerCount == 1 && runtime.Interval == 40, "fast watch release restores surviving request");
        runtime.Value = 99;runtime.Fire();Check(await slow.MoveNextAsync() && slow.Current.Value == 99, "surviving watch still receives actual samples");
        await slow.DisposeAsync();await TestCompletion.Until(() => runtime.HandlerCount == 0 && runtime.Interval == 100, "last release restores original driver configuration");
        Check(runtime.IntervalWrites.SequenceEqual(new uint[] {40, 20, 40, 100}), "only requested interval transitions occur");
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
    }
    private static async Task DiscoveryDeadline(bool capabilities)
    {
        var runtime = new RuntimeFixture {HoldEnumeration = true};
        using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
        var ticks = 0;using var heartbeat = new Timer(_ => Interlocked.Increment(ref ticks), null, 0, 5);
        var bounded = access.WithReadTimeout(TimeSpan.FromMilliseconds(100));
        Task pending = capabilities ? bounded.Capabilities.Get(Entities.Illuminance) : bounded.Sensors.List(Entities.Illuminance);
        await runtime.EnumerationStarted.Task.WaitAsync(TimeSpan.FromSeconds(1));
        try {await pending;throw new Exception("Expected native discovery timeout.");}
        catch (DeviceReadoutException error) when (error.Code == ErrorCode.ReadTimeout) { }
        Check(Volatile.Read(ref ticks) > 2, "host progresses while native async discovery is pending");
        try {await TestCompletion.Until(() => runtime.CanceledOperations == 1 && runtime.ClosedOperations == 1, "timed-out native operation canceled and closed");}
        finally {runtime.HoldEnumeration = false;}
        Check(runtime.EnumerationResults == 0, "no late result is consumed after timeout");
        runtime.HoldEnumeration = false;
        Check((await access.Sensors.List(Entities.Illuminance)).Length == 1 && runtime.EnumerationResults == 1, "fresh enumeration recovers");
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
    }

    // Vtable shapes, types, slots and event IIDs are from Windows SDK 10.0.26100.0 headers.
    private sealed class RuntimeFixture : IWindowsSensorRuntime
    {
        private readonly Dictionary<nint, int> references = [];
        private readonly List<nint> allocations = [];
        private readonly List<Delegate> delegates = [];
        private readonly Dictionary<long, nint> handlers = [];
        private readonly object gate = new();
        private readonly bool pressure;
        private readonly nint factory, enumeration, collection, information, sensor, reading, args;
        private long nextToken;
        internal double Value = 250;
        internal uint Interval = 100;
        internal int Initializations, Uninitializations, Registrations, Removals, CurrentReads;
        internal volatile bool HoldEnumeration;
        internal int CanceledOperations, ClosedOperations, EnumerationResults;
        internal readonly TaskCompletionSource EnumerationStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly List<uint> IntervalWrites = [];
        internal readonly TaskCompletionSource Stopped = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal int HandlerCount {get {lock (gate) return handlers.Count;}}
        internal RuntimeFixture(bool pressure = false)
        {
            this.pressure = pressure;
            factory = Object(8);enumeration = Object(11);collection = Object(8);information = Object(8);
            sensor = Object(pressure ? 13 : 12);reading = Object(8);args = Object(7);
            Set(factory, pressure ? 7 : 6, new WinRtGetInterface((nint self, out nint value) => {value = Text("sensor selector");return 0;}));
            Set(factory, pressure ? 6 : 7, new SensorStringCall((nint self, nint id, out nint operation) => {operation = Operation(sensor);return 0;}));
            Set(enumeration, 10, new SensorStringCall((nint self, nint selector, out nint operation) => {operation = Operation(collection, isEnumeration: true);return 0;}));
            Set(collection, 7, new SensorGetUInt((nint self, out uint size) => {size = 1;return 0;}));
            Set(collection, 6, new SensorGetAt((nint self, uint index, out nint item) => {item = Take(information);return index == 0 ? 0 : unchecked((int)0x8000000b);}));
            Set(information, 6, new WinRtGetInterface((nint self, out nint id) => {id = Text("abi-sensor");return 0;}));
            Set(information, 7, new WinRtGetInterface((nint self, out nint name) => {name = Text(pressure ? "ABI pressure" : "ABI light");return 0;}));
            Set(sensor, 6, new WinRtGetInterface((nint self, out nint value) => {CurrentReads++;value = Take(reading);return 0;}));
            Set(sensor, pressure ? 8 : 7, new SensorGetUInt((nint self, out uint value) => {value = 20;return 0;}));
            Set(sensor, pressure ? 9 : 8, new SensorPutUInt((nint self, uint value) => {Interval = value;IntervalWrites.Add(value);return 0;}));
            Set(sensor, pressure ? 10 : 9, new SensorGetUInt((nint self, out uint value) => {value = Interval;return 0;}));
            Set(sensor, pressure ? 11 : 10, new WinRtAddReportEvent((nint self, nint handler, out long token) => {
                var iid = new Guid(pressure ? "e4caf459-d101-5ca5-a4ea-deb0917ae27e" : "1ecf183a-9f0a-5f73-9225-5a33eab5594f");
                Check(Marshal.QueryInterface(handler, in iid, out var supported) == 0, "typed native handler interface");Marshal.Release(supported);
                Marshal.AddRef(handler);lock (gate) {token = ++nextToken;handlers.Add(token, handler);Registrations++;}return 0;
            }));
            Set(sensor, pressure ? 12 : 11, new WinRtRemoveReportEvent((nint self, long token) => {
                lock (gate) {Check(handlers.Remove(token, out var handler), "matching native event token");Marshal.Release(handler);Removals++;}return 0;
            }));
            Set(args, 6, new WinRtGetInterface((nint self, out nint value) => {value = Take(reading);return 0;}));
            if (pressure) Set(reading, 7, new SensorGetDouble((nint self, out double value) => {value = Value;return 0;}));
            else Set(reading, 7, new SensorGetFloat((nint self, out float value) => {value = (float)Value;return 0;}));
        }
        private nint Operation(nint result, bool isEnumeration = false)
        {
            var operation = Object(9);var info = Object(11);
            Set(operation, 0, new Query((nint self, in Guid iid, out nint value) => {
                value = iid == new Guid("00000036-0000-0000-c000-000000000046") ? Take(info) : 0;
                return value == 0 ? unchecked((int)0x80004002) : 0;
            }));
            Set(operation, 8, new WinRtGetInterface((nint self, out nint value) => {if (isEnumeration) EnumerationResults++;value = Take(result);return 0;}));
            Set(info, 7, new WinRtGetInt32((nint self, out int value) => {
                value = isEnumeration && HoldEnumeration ? 0 : 1;if (value == 0) EnumerationStarted.TrySetResult();return 0;
            }));
            Set(info, 8, new WinRtGetInt32((nint self, out int value) => {value = 0;return 0;}));
            Set(info, 9, new WinRtNoArguments(_ => {Interlocked.Increment(ref CanceledOperations);return 0;}));
            Set(info, 10, new WinRtNoArguments(_ => {Interlocked.Increment(ref ClosedOperations);return 0;}));
            return Take(operation);
        }
        internal void Fire()
        {
            nint[] current;lock (gate) current = handlers.Values.ToArray();
            foreach (var handler in current) {
                var invoke = Marshal.GetDelegateForFunctionPointer<WinRtCellularEventInvoke>(Marshal.ReadIntPtr(Marshal.ReadIntPtr(handler), nint.Size * 3));
                Check(invoke(handler, sensor, args) == 0, "callback never unwinds into native caller");
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
        public int Initialize() {Initializations++;return 0;}
        public nint Factory(string name, Guid iid)
        {
            var expected = new Guid(name == "Windows.Devices.Enumeration.DeviceInformation" ? "c17f100e-3a46-4a78-8013-769dc9b97390"
                : pressure ? "8fc6b1e7-95ff-44ac-878e-d65c8308c34c" : "0ec0a650-ddc6-40ab-ace3-ec3359d42c51");
            Check(iid == expected, "native factory IID");return Take(name == "Windows.Devices.Enumeration.DeviceInformation" ? enumeration : factory);
        }
        public void Release(nint value) {lock (gate) {Check(references[value] > 0, "owned native reference");references[value]--;}}
        public void Uninitialize()
        {
            Uninitializations++;
            try {Check(references.Values.All(count => count == 0) && HandlerCount == 0, "every async result, sensor, reading, factory and event reference released");}
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
