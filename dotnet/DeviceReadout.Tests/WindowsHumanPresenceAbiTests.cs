using DeviceReadout;
using DeviceReadout.Windows;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;

[SupportedOSPlatform("windows")]
internal static class WindowsHumanPresenceAbiTests
{
    internal static IEnumerable<(string Name, Func<Task> Run)> Cases() => [
        ("Windows native sensor human presence distinguishes presence, absence and unknown without engagement inference", Presence),
        ("Windows native sensor human presence failures and app observers preserve permission and activity ownership", FailuresAndObservers),
        ("Windows native sensor human presence held reads preserve deadlines and caller cancellation without joining cleanup", HeldReads),
        ("Windows native sensor human presence late initial samples cannot follow newer native events", LateInitial),
        ("Windows native sensor human presence unavailable runtime interfaces produce typed errors and permit recovery", RuntimeAvailability)
    ];

    private static async Task Presence()
    {
        var runtime = new RuntimeFixture {Presence = 2};
        using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
        var target = (await access.Sensors.List(Entities.HumanPresence)).Single();
        var description = await access.Describe(target);
        Check(description.Kind == SensorKind.HumanPresence && description.Name == "ABI human presence"
            && description.MinimumInterval is null && description.MaximumRange is null, "Boolean presence metadata does not invent a numeric range or sampling interval");
        Check((await access.Capabilities.Get(target)).Readable == true && runtime.CurrentReads == 0 && runtime.Registrations == 0, "discovery, metadata and support checks do not collect presence");
        Check((await access.Get(target)).Value == false, "native NotPresent is a valid false value");
        await TestCompletion.Until(() => runtime.HandlerCount == 0, "one-shot presence session released");
        await using var watch = access.WithSensorSamplingRate(SensorSamplingRate.AtHertz(60)).Watch(target).GetAsyncEnumerator();
        Check(await watch.MoveNextAsync() && watch.Current.Value == false, "initial absence is returned immediately");
        runtime.Presence = 1;runtime.Fire();runtime.Fire();
        Check(await watch.MoveNextAsync() && watch.Current.Value == true, "native Present maps to true");
        Check(await watch.MoveNextAsync() && watch.Current.Value == true, "equal native presence events are preserved");
        foreach (var unknown in new[] {0, 3, -1, int.MaxValue}) {
            runtime.Presence = unknown;runtime.Fire();
            Check(await watch.MoveNextAsync() && watch.Current.Value is null, "unknown native presence is not inferred from engagement or distance");
        }
        runtime.Presence = 2;runtime.Fire();
        Check(await watch.MoveNextAsync() && watch.Current.Value == false, "a known value recovers without restarting the stream");
        await watch.DisposeAsync();access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.Removals == 2 && runtime.Registrations == 2 && runtime.IrrelevantReads == 0 && runtime.AsyncOpens == 0,
            "sessions balance without engagement, distance, asynchronous opening or settings APIs");
    }

    private static async Task FailuresAndObservers()
    {
        var runtime = new RuntimeFixture {Presence = 1, OpenStatus = unchecked((int)0x80070005)};
        using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
        var requests = 0;using var coordinator = access.Observers.OnPermissionRequest((_, _) => {requests++;return Task.CompletedTask;});
        var target = (await access.Sensors.List(Entities.HumanPresence)).Single();
        using var permissionFailure = access.Observers.FailureSource(target);
        await Error(() => access.Get(target), ErrorCode.PermissionDenied);
        Check(runtime.CurrentReads == 0 && runtime.Registrations == 0, "failed native opening does not measure or register");
        runtime.OpenStatus = 0;runtime.CurrentStatus = unchecked((int)0x80004005);
        await Error(() => access.Get(target), ErrorCode.ReadFailed);
        await TestCompletion.Until(() => runtime.HandlerCount == 0, "failed initial native reading releases the listener");
        runtime.CurrentStatus = 0;
        await using var watch = access.WithReadTimeout(TimeSpan.FromMilliseconds(150)).Watch(target).GetAsyncEnumerator();
        Check(await watch.MoveNextAsync() && watch.Current.Value == true, "native open and read failures permit a fresh request");
        foreach (var status in new[] {unchecked((int)0x80004005), unchecked((int)0x80070005)}) {
            runtime.PresenceStatus = status;runtime.Fire();
            Check(await watch.MoveNextAsync() && watch.Current.Value is null, "unreadable presence field stays null without terminating the stream");
        }
        runtime.PresenceStatus = 0;runtime.Presence = 2;runtime.Fire();
        Check(await watch.MoveNextAsync() && watch.Current.Value == false, "field recovery uses the next real sample");
        var pending = watch.MoveNextAsync().AsTask();var readings = runtime.CurrentReads;
        await Task.Delay(200);
        Check(!pending.IsCompleted && runtime.CurrentReads == readings, "event silence neither polls nor triggers another first-read deadline");
        access.Observers.SensorActivity(false);
        await TestCompletion.Until(() => runtime.HandlerCount == 0, "app inactivity releases the native subscription");
        await Task.Delay(200);
        Check(!pending.IsCompleted && runtime.CurrentReads == readings, "inactive app remains suspended without native reading");
        runtime.Presence = 1;access.Observers.SensorActivity(true);
        Check(await pending.WaitAsync(TimeSpan.FromSeconds(1)) && watch.Current.Value == true, "activity resumption reads fresh presence");
        var denied = watch.MoveNextAsync().AsTask();
        access.Observers.Permission(target, PermissionStatus.Denied);
        permissionFailure.Publish(new(ErrorCode.PermissionDenied, "App observer reports blocked presence collection."));
        await Error(async () => await denied.WaitAsync(TimeSpan.FromSeconds(1)), ErrorCode.PermissionDenied);
        await TestCompletion.Until(() => runtime.HandlerCount == 0, "observed permission loss closes the native session");
        readings = runtime.CurrentReads;
        await Error(() => access.Get(target), ErrorCode.PermissionDenied);
        Check(runtime.CurrentReads == readings && requests == 0, "blocked reads never request permission or query native presence");
        access.Observers.Permission(target, PermissionStatus.Granted);permissionFailure.Publish(null);
        Check((await access.Get(target)).Value == true, "app-observed permission recovery enables a fresh query");
        await watch.DisposeAsync();access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.Registrations == runtime.Removals && requests == 0 && runtime.IrrelevantReads == 0, "failure and observer lifetimes release all resources without UI coordination");
    }
    private static async Task HeldReads()
    {
        foreach (var point in new[] {HoldPoint.Open, HoldPoint.CurrentReading, HoldPoint.Presence})
        foreach (var stream in new[] {false, true})
        foreach (var cancel in new[] {false, true}) {
            var runtime = new RuntimeFixture {Presence = 1, Held = point};
            using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
            using var callerCancellation = new CancellationTokenSource();
            var target = (await access.Sensors.List(Entities.HumanPresence)).Single();
            var bounded = access.WithReadTimeout(cancel ? TimeSpan.FromSeconds(3) : TimeSpan.FromMilliseconds(150));
            var pulse = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            var ticks = 0;using var heartbeat = new Timer(_ => {Interlocked.Increment(ref ticks);pulse.TrySetResult();}, null, Timeout.Infinite, Timeout.Infinite);
            var caller = Environment.CurrentManagedThreadId;
            IAsyncEnumerator<HumanPresenceSnapshot>? watch = null;
            try {
                Task pending;
                if (stream) {watch = bounded.Watch(target).GetAsyncEnumerator(callerCancellation.Token);pending = watch.MoveNextAsync().AsTask();}
                else pending = bounded.Get(target, callerCancellation.Token);
                await runtime.Started.Task.WaitAsync(TimeSpan.FromSeconds(2));
                heartbeat.Change(0, 5);await pulse.Task.WaitAsync(TimeSpan.FromSeconds(1));
                if (cancel) {
                    callerCancellation.Cancel();
                    try {await pending.WaitAsync(TimeSpan.FromSeconds(1));throw new Exception("Expected caller cancellation.");}
                    catch (OperationCanceledException error) when (error.CancellationToken == callerCancellation.Token) { }
                } else await Error(() => pending.WaitAsync(TimeSpan.FromSeconds(1)), ErrorCode.ReadTimeout);
                Check(!runtime.Continue.IsSet && runtime.HeldThread != caller && Volatile.Read(ref ticks) > 0,
                    "native presence call remains held off the host while caller deadline/cancellation completes");
                var elapsed = System.Diagnostics.Stopwatch.StartNew();access.Dispose();
                if (watch is not null) await watch.DisposeAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
                Check(elapsed.Elapsed < TimeSpan.FromMilliseconds(500) && !runtime.Stopped.Task.IsCompleted, "context and stream disposal do not join the native call");
            } finally {runtime.Continue.Set();access.Dispose();}
            await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
            if (point == HoldPoint.Open) Check(runtime.CurrentReads == 0 && runtime.Registrations == 0, "late sensor opening cannot start another measurement or subscription");
            if (point == HoldPoint.CurrentReading) Check(runtime.PresenceReads == 0, "late native reading is released without querying presence");
            Check(runtime.Removals == runtime.Registrations && runtime.IrrelevantReads == 0, "late native completion releases all leases");
        }
    }
    private static async Task LateInitial()
    {
        var runtime = new RuntimeFixture {Presence = 1, Held = HoldPoint.Presence};
        using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
        var target = (await access.Sensors.List(Entities.HumanPresence)).Single();
        await using var watch = access.Watch(target).GetAsyncEnumerator();
        var first = watch.MoveNextAsync().AsTask();
        try {
            await runtime.Started.Task.WaitAsync(TimeSpan.FromSeconds(2));
            runtime.Held = HoldPoint.None;runtime.Presence = 2;runtime.Fire();
        } finally {runtime.Continue.Set();}
        Check(await first.WaitAsync(TimeSpan.FromSeconds(1)) && watch.Current.Value == false, "new absence event provides the first snapshot");
        var next = watch.MoveNextAsync().AsTask();await Task.Delay(80);
        Check(!next.IsCompleted, "old initial presence cannot follow the newer absence event");
        runtime.Presence = 1;runtime.Fire();runtime.Fire();
        Check(await next.WaitAsync(TimeSpan.FromSeconds(1)) && watch.Current.Value == true, "future presence event remains live");
        Check(await watch.MoveNextAsync() && watch.Current.Value == true, "initial-value suppression preserves duplicate native events");
        await watch.DisposeAsync();access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
    }
    private static async Task RuntimeAvailability()
    {
        var runtime = new RuntimeFixture {Presence = 1, DiscoveryAvailable = false};
        using var access = new DeviceAccess(new WindowsCollector(sensorPlatform: new WindowsSensorPlatform(runtime)));
        await Error(() => access.Sensors.List(Entities.HumanPresence), ErrorCode.UnsupportedEntity);
        runtime.DiscoveryAvailable = true;
        var target = (await access.Sensors.List(Entities.HumanPresence)).Single();
        runtime.OpenAvailable = false;
        await Error(() => access.Get(target), ErrorCode.UnsupportedEntity);
        await Error(() => access.Describe(target), ErrorCode.UnsupportedEntity);
        Check(runtime.CurrentReads == 0 && runtime.Registrations == 0, "missing opening interface is neither absence nor an empty measurement");
        runtime.OpenAvailable = true;
        Check((await access.Get(target)).Value == true, "an unavailable interface is not cached as a valid native factory");
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.Registrations == runtime.Removals, "runtime availability failures retain balanced resource ownership");
    }
    private static async Task Error(Func<Task> action, ErrorCode expected)
    {
        try {await action();throw new Exception($"Expected {expected}.");}
        catch (DeviceReadoutException error) when (error.Code == expected) { }
    }

    private enum HoldPoint { None, Open, CurrentReading, Presence }

    // Native declarations are independent Windows SDK 10.0.26100.0 vtables.
    private sealed class RuntimeFixture : IWindowsSensorRuntime
    {
        private readonly object gate = new();
        private readonly Dictionary<nint, int> references = [];
        private readonly List<nint> allocations = [];
        private readonly List<Delegate> delegates = [];
        private readonly Dictionary<long, nint> handlers = [];
        private readonly nint discoveryFactory, openFactory, enumeration, collection, information, sensor, reading, args;
        private long nextToken;
        internal int Presence, CurrentReads, Registrations, Removals, IrrelevantReads, AsyncOpens;
        internal int OpenStatus, CurrentStatus, PresenceStatus;
        internal bool DiscoveryAvailable = true, OpenAvailable = true;
        internal int HeldThread, PresenceReads;
        internal HoldPoint Held;
        internal readonly TaskCompletionSource Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly ManualResetEventSlim Continue = new(false);
        internal int HandlerCount {get {lock (gate) return handlers.Count;}}
        internal readonly TaskCompletionSource Stopped = new(TaskCreationOptions.RunContinuationsAsynchronously);

        internal RuntimeFixture()
        {
            discoveryFactory = Object(9);openFactory = Object(8);enumeration = Object(11);collection = Object(8);information = Object(8);
            sensor = Object(12);reading = Object(10);args = Object(7);
            Set(discoveryFactory, 6, new WinRtGetInterface((nint self, out nint value) => {value = Text("human presence selector");return 0;}));
            Set(discoveryFactory, 7, new SensorStringCall((nint self, nint id, out nint value) => {AsyncOpens++;value = 0;return unchecked((int)0x80004001);}));
            Set(openFactory, 6, new SensorStringCall((nint self, nint id, out nint value) => {value = Take(sensor);Hold(HoldPoint.Open);return OpenStatus;}));
            Set(enumeration, 10, new SensorStringCall((nint self, nint selector, out nint value) => {value = Operation(collection);return 0;}));
            Set(collection, 7, new SensorGetUInt((nint self, out uint size) => {size = 1;return 0;}));
            Set(collection, 6, new SensorGetAt((nint self, uint index, out nint item) => {item = Take(information);return index == 0 ? 0 : unchecked((int)0x8000000b);}));
            Set(information, 6, new WinRtGetInterface((nint self, out nint value) => {value = Text("abi-human-presence");return 0;}));
            Set(information, 7, new WinRtGetInterface((nint self, out nint value) => {value = Text("ABI human presence");return 0;}));
            Set(sensor, 6, new WinRtGetInterface((nint self, out nint value) => {value = Text("abi-human-presence");return 0;}));
            Set(sensor, 7, new WinRtGetInterface((nint self, out nint value) => {IrrelevantReads++;value = 0;return 0;}));
            Set(sensor, 8, new WinRtGetInterface((nint self, out nint value) => {IrrelevantReads++;value = 0;return 0;}));
            Set(sensor, 9, new WinRtGetInterface((nint self, out nint value) => {CurrentReads++;value = Take(reading);Hold(HoldPoint.CurrentReading);return CurrentStatus;}));
            Set(sensor, 10, new WinRtAddReportEvent((nint self, nint handler, out long token) => {
                var iid = new Guid("329678bc-3d7c-5ff3-87cb-4fc5e9fecf72");
                Check(Marshal.QueryInterface(handler, in iid, out var supported) == 0, "human presence event handler interface");Marshal.Release(supported);
                Marshal.AddRef(handler);lock (gate) {token = ++nextToken;handlers.Add(token, handler);Registrations++;}return 0;
            }));
            Set(sensor, 11, new WinRtRemoveReportEvent((nint self, long token) => {
                lock (gate) {Check(handlers.Remove(token, out var handler), "matching presence event token");Marshal.Release(handler);Removals++;}return 0;
            }));
            Set(reading, 7, new WinRtGetInt32((nint self, out int value) => {Interlocked.Increment(ref PresenceReads);value = Presence;Hold(HoldPoint.Presence);return PresenceStatus;}));
            Set(reading, 8, new WinRtGetInt32((nint self, out int value) => {IrrelevantReads++;value = 1;return 0;}));
            Set(reading, 9, new WinRtGetInterface((nint self, out nint value) => {IrrelevantReads++;value = 0;return 0;}));
            Set(args, 6, new WinRtGetInterface((nint self, out nint value) => {value = Take(reading);return 0;}));
        }
        private void Hold(HoldPoint point)
        {
            if (Held != point) return;
            HeldThread = Environment.CurrentManagedThreadId;Started.TrySetResult();
            Check(Continue.Wait(TimeSpan.FromSeconds(5)), "held presence call was released externally");
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
            nint[] current;
            lock (gate) {current = handlers.Values.ToArray();foreach (var handler in current) Marshal.AddRef(handler);}
            foreach (var handler in current) {
                try {
                    var invoke = Marshal.GetDelegateForFunctionPointer<WinRtCellularEventInvoke>(Marshal.ReadIntPtr(Marshal.ReadIntPtr(handler), nint.Size * 3));
                    Check(invoke(handler, sensor, args) == 0, "presence callback does not unwind into native caller");
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
            if (name == "Windows.Devices.Enumeration.DeviceInformation") {
                Check(iid == new Guid("c17f100e-3a46-4a78-8013-769dc9b97390"), "enumeration factory IID");return Take(enumeration);
            }
            Check(name == "Windows.Devices.Sensors.HumanPresenceSensor", "presence sensor runtime class");
            if (iid == new Guid("2ae89842-dba9-56b2-9f27-eac69d621004")) return DiscoveryAvailable ? Take(discoveryFactory) : 0;
            Check(iid == new Guid("5de35843-d260-5a87-995e-ace91326e1c4"), "synchronous opening uses the second statics interface");return OpenAvailable ? Take(openFactory) : 0;
        }
        public void Release(nint value) {lock (gate) {Check(references[value] > 0, "owned presence native reference");references[value]--;}}
        public void Uninitialize()
        {
            try {Check(references.Values.All(count => count == 0) && HandlerCount == 0, "all presence native references and event registrations released");}
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
