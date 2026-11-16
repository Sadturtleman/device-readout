using DeviceReadout;
using DeviceReadout.Windows;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;

[SupportedOSPlatform("windows")]
internal static class WindowsAltimeterAbiTests
{
    internal static IEnumerable<(string Name, Func<Task> Run)> Cases() => [
        ("Windows native sensor relative altitude preserves native signed meters and default target identity", Readings),
        ("Windows native sensor relative altitude default replacement retires handles without substituting another sensor", DefaultIdentity),
        ("Windows native sensor relative altitude held discovery and reads preserve host deadlines and late ownership", HeldCalls),
        ("Windows native sensor relative altitude failures and shared sampling recover without changing the native baseline", Recovery)
    ];

    private static async Task Readings()
    {
        var runtime = new RuntimeFixture {Altitude = 7.5};
        using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
        var target = (await access.Sensors.List(Entities.RelativeAltitude)).Single();
        Check(await access.Current(Entities.RelativeAltitude) == target, "default altimeter resolves to the discovered typed handle");
        var description = await access.Describe(target);
        Check(description.Kind == SensorKind.RelativeAltitude && description.MinimumInterval == TimeSpan.FromMilliseconds(20)
            && description.Name is null && description.MaximumRange is null, "native metadata supplies only available fields");
        Check((await access.Capabilities.Get(target)).Readable == true && runtime.CurrentReads == 0 && runtime.Registrations == 0 && runtime.Interval == 100,
            "discovery, current selection, metadata and support remain passive");
        Check((await access.Get(target)).Value == 7.5, "native relative altitude is not rebased to zero by the SDK");
        await TestCompletion.Until(() => runtime.HandlerCount == 0, "one-shot altitude listener released");
        await using var watch = access.WithSensorSamplingRate(SensorSamplingRate.AtHertz(60)).Watch(target).GetAsyncEnumerator();
        Check(await watch.MoveNextAsync() && watch.Current.Value == 7.5 && runtime.Interval == 20, "initial sample and native minimum interval");
        foreach (var value in new[] {-2.25, 0, 0, double.NaN, double.PositiveInfinity, 11.75}) {
            runtime.Altitude = value;runtime.Fire();
            Check(await watch.MoveNextAsync() && watch.Current.Value == (double.IsFinite(value) ? value : null), "signed meters, zero, duplicate and invalid values retain their meanings");
        }
        await watch.DisposeAsync();
        await TestCompletion.Until(() => runtime.HandlerCount == 0 && runtime.Interval == 100, "last altitude subscriber restores the previous driver interval");
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.Registrations == 2 && runtime.Removals == 2, "altimeter native leases balance");
    }

    private static async Task DefaultIdentity()
    {
        var runtime = new RuntimeFixture {Available = false, Altitude = 3};
        using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
        Check((await access.Sensors.List(Entities.RelativeAltitude)).Length == 0 && await access.Current(Entities.RelativeAltitude) is null, "missing default hardware yields an empty inventory and no current target");
        runtime.Available = true;
        var original = (await access.Sensors.List(Entities.RelativeAltitude)).Single();
        runtime.DeviceId = null;
        await Error(() => access.Sensors.List(Entities.RelativeAltitude), ErrorCode.ReadFailed);
        runtime.DeviceId = "abi-altimeter-a";
        Check((await access.Get(original)).Value == 3, "malformed native identity does not erase a previously known target");
        await TestCompletion.Until(() => runtime.HandlerCount == 0, "initial one-shot session closed");
        runtime.DeviceId = "abi-altimeter-b";var reads = runtime.CurrentReads;
        await Error(() => access.Get(original), ErrorCode.EntityRemoved);
        Check(runtime.CurrentReads == reads, "a changed default device is rejected before measuring it under the old handle");
        var replacement = (await access.Sensors.List(Entities.RelativeAltitude)).Single();
        Check(replacement != original && await access.Current(Entities.RelativeAltitude) == replacement, "new default has its own typed identity");
        await Error(() => access.Describe(original), ErrorCode.EntityRemoved);
        await using var watch = access.Watch(replacement).GetAsyncEnumerator();
        Check(await watch.MoveNextAsync() && watch.Current.Value == 3, "replacement can be observed independently");
        var pending = watch.MoveNextAsync().AsTask();runtime.Available = false;
        Check((await access.Sensors.List(Entities.RelativeAltitude)).Length == 0, "observed disappearance updates the inventory");
        await Error(async () => await pending.WaitAsync(TimeSpan.FromSeconds(1)), ErrorCode.EntityRemoved);
        await TestCompletion.Until(() => runtime.HandlerCount == 0 && runtime.Interval == 100, "removal closes the old stream and restores driver settings");
        runtime.Available = true;
        var returned = await access.Current(Entities.RelativeAltitude);
        Check(returned is not null && returned != replacement, "same device ID after observed removal receives a new generation");
        await Error(() => access.Get(replacement), ErrorCode.EntityRemoved);
        Check((await access.Get(returned!)).Value == 3, "reappeared default requires its fresh handle");
        await watch.DisposeAsync();access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.Registrations == runtime.Removals, "replacement and removal preserve native ownership");
    }
    private static async Task HeldCalls()
    {
        foreach (var scenario in new[] {
            ("list", HoldPoint.Default), ("list", HoldPoint.Identity),
            ("get", HoldPoint.Default), ("get", HoldPoint.Identity), ("get", HoldPoint.CurrentReading), ("get", HoldPoint.Value),
            ("describe", HoldPoint.Default), ("describe", HoldPoint.Identity), ("describe", HoldPoint.MinimumInterval)
        }) {
            var runtime = new RuntimeFixture {Altitude = 4};
            using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
            var target = scenario.Item1 == "list" ? null : (await access.Sensors.List(Entities.RelativeAltitude)).Single();
            var identityReads = runtime.IdentityReads;runtime.Held = scenario.Item2;
            var pulse = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            using var heartbeat = new Timer(_ => pulse.TrySetResult(), null, Timeout.Infinite, Timeout.Infinite);
            var caller = Environment.CurrentManagedThreadId;
            try {
                var bounded = access.WithReadTimeout(TimeSpan.FromMilliseconds(150));
                Task pending = scenario.Item1 switch {"list" => bounded.Sensors.List(Entities.RelativeAltitude), "get" => bounded.Get(target!), _ => bounded.Describe(target!)};
                await runtime.Started.Task.WaitAsync(TimeSpan.FromSeconds(2));
                heartbeat.Change(0, Timeout.Infinite);await pulse.Task.WaitAsync(TimeSpan.FromSeconds(1));
                await Error(() => pending.WaitAsync(TimeSpan.FromSeconds(1)), ErrorCode.ReadTimeout);
                Check(!runtime.Continue.IsSet && runtime.HeldThread != caller, "native altimeter call stays held off the host after the caller deadline");
                var elapsed = System.Diagnostics.Stopwatch.StartNew();access.Dispose();
                Check(elapsed.Elapsed < TimeSpan.FromMilliseconds(500) && !runtime.Stopped.Task.IsCompleted, "context disposal does not join a held altimeter call");
            } finally {runtime.Continue.Set();access.Dispose();}
            await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
            if (scenario.Item2 == HoldPoint.Default) Check(runtime.IdentityReads == identityReads, "late default pointer is released before reading its identity");
            if (scenario.Item2 == HoldPoint.CurrentReading) Check(runtime.ValueReads == 0, "late current reading is released without another property query");
            Check(runtime.Removals == runtime.Registrations && runtime.Interval == 100, "late native completion releases references and restores the report interval");
        }
    }
    private static async Task Recovery()
    {
        var runtime = new RuntimeFixture {Altitude = 7, DefaultStatus = unchecked((int)0x80070005)};
        using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
        var requests = 0;using var coordinator = access.Observers.OnPermissionRequest((_, _) => {requests++;return Task.CompletedTask;});
        await Error(() => access.Sensors.List(Entities.RelativeAltitude), ErrorCode.PermissionDenied);
        runtime.DefaultStatus = 0;
        var target = (await access.Sensors.List(Entities.RelativeAltitude)).Single();
        runtime.MinimumStatus = unchecked((int)0x80004005);
        Check((await access.Describe(target)).MinimumInterval is null, "unreadable interval metadata does not become a numeric value");
        runtime.MinimumStatus = 0;
        await using var slow = access.WithSensorSamplingRate(SensorSamplingRate.AtHertz(20)).Watch(target).GetAsyncEnumerator();
        await using var fast = access.WithSensorSamplingRate(SensorSamplingRate.AtHertz(60)).Watch(target).GetAsyncEnumerator();
        Check(await slow.MoveNextAsync() && slow.Current.Value == 7 && runtime.Interval == 50, "first subscriber uses its own interval request");
        Check(await fast.MoveNextAsync() && fast.Current.Value == 7 && runtime.Interval == 20, "shared sensor uses fastest request within its minimum");
        runtime.ValueStatus = unchecked((int)0x80004005);runtime.Fire();
        Check(await slow.MoveNextAsync() && slow.Current.Value is null && await fast.MoveNextAsync() && fast.Current.Value is null, "property failure remains nullable for each subscriber");
        runtime.ValueStatus = 0;runtime.Altitude = -2;runtime.Fire();
        Check(await slow.MoveNextAsync() && slow.Current.Value == -2 && await fast.MoveNextAsync() && fast.Current.Value == -2, "both subscribers recover on the next valid native sample");
        await fast.DisposeAsync();
        await TestCompletion.Until(() => runtime.HandlerCount == 1 && runtime.Interval == 50, "closing the fastest subscriber retains the slower request");
        var next = slow.MoveNextAsync().AsTask();access.Observers.SensorActivity(false);
        await TestCompletion.Until(() => runtime.HandlerCount == 0 && runtime.Interval == 100, "inactivity restores the original driver configuration");
        Check(!next.IsCompleted, "inactivity keeps the consumer awaiting a fresh session");
        runtime.Altitude = 25;access.Observers.SensorActivity(true);
        Check(await next.WaitAsync(TimeSpan.FromSeconds(1)) && slow.Current.Value == 25 && runtime.Interval == 50,
            "resumption preserves the new native reference value without SDK rebasing");
        await slow.DisposeAsync();access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.Interval == 100 && runtime.Registrations == runtime.Removals && requests == 0, "sampling leases and app-owned access remain balanced");
    }
    private static async Task Error(Func<Task> action, ErrorCode expected)
    {
        try {await action();throw new Exception($"Expected {expected}.");}
        catch (DeviceReadoutException error) when (error.Code == expected) { }
    }

    private enum HoldPoint { None, Default, Identity, CurrentReading, Value, MinimumInterval }

    // Independent ABI from the Windows SDK 10.0.26100.0 Altimeter declarations.
    private sealed class RuntimeFixture : IWindowsSensorRuntime
    {
        private readonly object gate = new();
        private readonly Dictionary<nint, int> references = [];
        private readonly List<nint> allocations = [];
        private readonly List<Delegate> delegates = [];
        private readonly Dictionary<long, nint> handlers = [];
        private readonly nint factory, sensor, reading, args;
        private long nextToken;
        internal string? DeviceId = "abi-altimeter-a";
        internal double Altitude;
        internal bool Available = true;
        internal uint Interval = 100;
        internal int CurrentReads, Registrations, Removals;
        internal int DefaultStatus, ValueStatus, MinimumStatus;
        internal int IdentityReads, ValueReads, HeldThread;
        internal HoldPoint Held;
        internal readonly TaskCompletionSource Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly ManualResetEventSlim Continue = new(false);
        internal int HandlerCount {get {lock (gate) return handlers.Count;}}
        internal readonly TaskCompletionSource Stopped = new(TaskCreationOptions.RunContinuationsAsynchronously);

        internal RuntimeFixture()
        {
            factory = Object(7);sensor = Object(13);reading = Object(8);args = Object(7);
            Set(factory, 6, new WinRtGetInterface((nint self, out nint value) => {value = Available ? Take(sensor) : 0;Hold(HoldPoint.Default);return DefaultStatus;}));
            Set(sensor, 6, new WinRtGetInterface((nint self, out nint value) => {CurrentReads++;value = Take(reading);Hold(HoldPoint.CurrentReading);return 0;}));
            Set(sensor, 7, new WinRtGetInterface((nint self, out nint value) => {IdentityReads++;value = DeviceId is { } id ? Text(id) : 0;Hold(HoldPoint.Identity);return 0;}));
            Set(sensor, 8, new SensorGetUInt((nint self, out uint value) => {value = 20;Hold(HoldPoint.MinimumInterval);return MinimumStatus;}));
            Set(sensor, 9, new SensorPutUInt((nint self, uint value) => {Interval = value;return 0;}));
            Set(sensor, 10, new SensorGetUInt((nint self, out uint value) => {value = Interval;return 0;}));
            Set(sensor, 11, new WinRtAddReportEvent((nint self, nint handler, out long token) => {
                var iid = new Guid("d775d699-9d74-5473-9c1b-d51a89db6642");
                Check(Marshal.QueryInterface(handler, in iid, out var supported) == 0, "altimeter event handler interface");Marshal.Release(supported);
                Marshal.AddRef(handler);lock (gate) {token = ++nextToken;handlers.Add(token, handler);Registrations++;}return 0;
            }));
            Set(sensor, 12, new WinRtRemoveReportEvent((nint self, long token) => {
                lock (gate) {Check(handlers.Remove(token, out var handler), "matching altimeter event token");Marshal.Release(handler);Removals++;}return 0;
            }));
            Set(reading, 7, new SensorGetDouble((nint self, out double value) => {ValueReads++;value = Altitude;Hold(HoldPoint.Value);return ValueStatus;}));
            Set(args, 6, new WinRtGetInterface((nint self, out nint value) => {value = Take(reading);return 0;}));
        }
        private void Hold(HoldPoint point)
        {
            if (Held != point) return;
            HeldThread = Environment.CurrentManagedThreadId;Started.TrySetResult();
            Check(Continue.Wait(TimeSpan.FromSeconds(5)), "held altimeter call was released externally");
        }
        internal void Fire()
        {
            nint[] current;lock (gate) {current = handlers.Values.ToArray();foreach (var handler in current) Marshal.AddRef(handler);}
            foreach (var handler in current) {
                try {
                    var invoke = Marshal.GetDelegateForFunctionPointer<WinRtCellularEventInvoke>(Marshal.ReadIntPtr(Marshal.ReadIntPtr(handler), nint.Size * 3));
                    Check(invoke(handler, sensor, args) == 0, "altimeter event never unwinds into the native caller");
                } finally {Marshal.Release(handler);}
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
            Check(name == "Windows.Devices.Sensors.Altimeter" && iid == new Guid("9eb4d7c3-e5ac-47ce-8eef-d3718168c01f"), "altimeter uses only its own default factory");return Take(factory);
        }
        public void Release(nint value) {lock (gate) {Check(references[value] > 0, "owned altimeter native reference");references[value]--;}}
        public void Uninitialize()
        {
            try {Check(references.Values.All(count => count == 0) && HandlerCount == 0, "all altimeter references and event registrations released");}
            catch (Exception error) {Stopped.TrySetException(error);throw;}
            finally {foreach (var pointer in allocations) Marshal.FreeHGlobal(pointer);delegates.Clear();}
            Stopped.TrySetResult();
        }
        private static nint Text(string value) {Check(WindowsCreateString(value, value.Length, out var text) == 0, "fixture HSTRING");return text;}
        [DllImport("combase.dll", CharSet = CharSet.Unicode)] private static extern int WindowsCreateString(string source, int length, out nint value);
    }
    private static void Check(bool condition, string message) {if (!condition) throw new Exception(message);}
}
