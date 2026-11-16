using System.Buffers.Binary;
using System.ComponentModel;
using System.Runtime.Versioning;
using System.Runtime.InteropServices;
using System.Text;
using DeviceReadout;
using DeviceReadout.Windows;

[SupportedOSPlatform("windows")]
internal static partial class WindowsBatteryTests
{
    internal static IEnumerable<(string Name, Func<Task> Run)> Cases() => [
        ("Windows battery fields retain native units, signed power and per-device targets", ReadsFields),
        ("Windows battery partial availability distinguishes unknown, relative units and real zero", PartialAvailability),
        ("Windows battery removal and tag changes never rebind old targets or erase readable peers", TargetLifetimes),
        ("Windows battery polling preserves duplicates and blocked native reads preserve host deadlines", SchedulingAndCleanup),
        ("Windows battery truncated protocol replies fail without retiring healthy targets", InvalidReplies),
        ("Windows battery failed inventories retain positively observed removal and generation changes", FailedInventoryRemoval),
        ("Windows power notifications refresh the selected battery without substituting aggregate capacity", PowerNotifications),
        ("Windows battery interface removal retires rapid path and tag reuse until rediscovery", InterfaceRemoval),
        ("real Windows battery discovery owns one native interface notification until context closure", NativeInterfaceLifetime),
        ("Windows battery native interface payloads retire idle handles and reject malformed notifications", InterfaceProtocol),
        ("Windows battery removals invalidate in-flight reads and racing discovery generations", InterfaceRaces),
        ("Windows battery interface registration errors retain typed failures without hidden retries", InterfaceRegistrationFailures),
        ("Windows individual battery status waits preserve native transitions without blocking other reads", StatusEvents),
        ("Windows battery status failures are typed and removed generations cannot recover", StatusFailures),
        ("Windows battery overlapped status I/O keeps buffers alive through cancellation completion", StatusOverlapped),
        ("Windows battery status observation handles unknown capacity and unsupported drivers", StatusFallback),
        ("Windows status transport completes and cancels real kernel overlapped I/O without a UI loop", StatusNativeKernel),
        ("Windows battery status subscriptions keep independent lifetimes and context closure cancels every wait", StatusLifetimes),
        ("Windows battery status removal invalidates every observer across device path casing changes", StatusRemovedPeers)
    ];

    private static async Task InterfaceRegistrationFailures()
    {
        foreach (var (result, expected) in new[] {(0x33u, ErrorCode.PermissionDenied), (0xdu, ErrorCode.ReadFailed)}) {
            var cm = new ConfigurationFixture {RegisterResult = result};
            var platform = new BatteryPlatformFixture {Configuration = cm};platform.Slots["battery"] = new BatterySlotFixture();
            using var access = new DeviceAccess(new WindowsCollector(platform, aggregatePlatform: new WindowsAggregateBatteryTests.UnavailablePlatform()));
            await Error(expected, () => access.Batteries.List());await Error(expected, () => access.Batteries.List());
            Check(cm.Registers == 1 && cm.Active == 0 && cm.Unregisters == 0 && platform.ActiveHandles == 0, "failed registration is retained without retry or device acquisition");
        }
        var unsupported = new ConfigurationFixture {RegisterResult = 0x34};
        var fallback = new BatteryPlatformFixture {Configuration = unsupported};fallback.Slots["battery"] = new BatterySlotFixture();
        using var fallbackAccess = new DeviceAccess(new WindowsCollector(fallback, new WindowsPowerTests.PowerPlatformFixture(), new WindowsAggregateBatteryTests.UnavailablePlatform()));
        var target = (await fallbackAccess.Batteries.List())[0];
        await using (var stream = fallbackAccess.WithPollInterval(TimeSpan.FromMilliseconds(15)).Watch(target).GetAsyncEnumerator()) {
            Check(await stream.MoveNextAsync(), "initial state without native interface API");
            Check(await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)), "polling remains usable without native interface API");
        }
        Check(unsupported.Registers == 1 && unsupported.Active == 0, "unsupported registration is not retried per read");
    }

    private static async Task InterfaceRaces()
    {
        var platform = new BatteryPlatformFixture {EventsEnabled = true};var slot = new BatterySlotFixture();platform.Slots["battery"] = slot;
        using var access = new DeviceAccess(new WindowsCollector(platform, new WindowsPowerTests.PowerPlatformFixture(), new WindowsAggregateBatteryTests.UnavailablePlatform()));
        var old = (await access.Batteries.List())[0];
        using var release = new ManualResetEventSlim();
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        slot.BeforeStatus = () => {started.TrySetResult();release.Wait();};
        var pending = access.Get(old);
        try {
            await started.Task.WaitAsync(TimeSpan.FromSeconds(1));
            platform.EmitInterface(new("battery", true));platform.EmitInterface(new("battery", false));
        } finally {release.Set();}
        await Error(ErrorCode.EntityRemoved, () => pending);slot.BeforeStatus = null;
        var current = (await access.Batteries.List())[0];
        Check((await access.Get(current)).Present == true, "new generation readable after native call returns");
        Check((await access.Capabilities.Get(old)).Readable == false, "old in-flight generation retired");
        slot.BeforeTag = () => {
            slot.BeforeTag = null;
            platform.EmitInterface(new("battery", true));platform.EmitInterface(new("battery", false));
        };
        Check((await access.Batteries.List()).Length == 0, "inventory excludes a tag read across interface removal");
        await Error(ErrorCode.EntityRemoved, () => access.Get(current));
        var next = (await access.Batteries.List())[0];Check((await access.Get(next)).Present == true, "next stable inventory recovers");
        platform.EmitInterface(new("battery", true));
        Check((await access.Batteries.List()).Length == 0, "positive removal overrides a stale path/tag inventory until native arrival");
        await Error(ErrorCode.EntityRemoved, () => access.Get(next));
        platform.EmitInterface(new("battery", false));
        Check((await access.Batteries.List()).Length == 1, "a later native arrival permits rediscovery");
        access.Dispose();await platform.ObserverStopped.Task.WaitAsync(TimeSpan.FromSeconds(1));
        Check(platform.ActiveHandles == 0, "racing operations and context closure release native resources");
    }

    private static async Task InterfaceProtocol()
    {
        var cm = new ConfigurationFixture();var platform = new BatteryPlatformFixture {Configuration = cm};
        platform.Slots["battery"] = new BatterySlotFixture();
        using var access = new DeviceAccess(new WindowsCollector(platform, new WindowsPowerTests.PowerPlatformFixture(), new WindowsAggregateBatteryTests.UnavailablePlatform()));
        var old = (await access.Batteries.List())[0];
        var payload = InterfacePayload("BATTERY");
        cm.Emit(0, payload);cm.Emit(99, []);cm.Emit(1, InterfacePayload("battery", Guid.Empty));
        Check((await access.Get(old)).Present == true, "arrival, unrelated actions and other classes do not retire a pack");
        cm.Emit(1, payload);cm.Emit(0, payload);
        await Error(ErrorCode.EntityRemoved, () => access.Get(old));
        var fresh = (await access.Batteries.List())[0];Check((await access.Get(fresh)).Present == true, "idle get-only targets use removal history");
        await using (var stream = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(fresh).GetAsyncEnumerator()) {
            Check(await stream.MoveNextAsync(), "initial state before malformed native event");
            cm.Emit(1, payload[..25]);
            await Error(ErrorCode.ReadFailed, async () => {await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));});
        }
        await Error(ErrorCode.ReadFailed, () => access.Get(fresh));
        await Error(ErrorCode.ReadFailed, () => access.Batteries.List());
        access.Dispose();await platform.ObserverStopped.Task.WaitAsync(TimeSpan.FromSeconds(1));
        Check(cm.Active == 0 && cm.Registers == 1 && cm.Unregisters == 1 && !cm.UnregisteredInCallback, "native observer fails closed and unregisters outside its callback");
        cm.Emit(1, []); // A late native callback can still hold its old numeric context.
    }
    private static byte[] InterfacePayload(string path, Guid? interfaceClass = null)
    {
        var name = Encoding.Unicode.GetBytes(path + "\0");var bytes = new byte[24 + name.Length];
        (interfaceClass ?? new Guid("72631e54-78a4-11d0-bcf7-00aa00b7b32a")).TryWriteBytes(bytes.AsSpan(8));
        name.CopyTo(bytes, 24);return bytes;
    }
    private sealed class ConfigurationFixture : IConfigurationNotifications
    {
        private DeviceInterfaceCallback? callback;
        private nint context;
        private bool inCallback;
        internal int Registers, Unregisters, Active;
        internal uint RegisterResult;
        internal bool UnregisteredInCallback;
        public uint Register(byte[] filter, nint context, DeviceInterfaceCallback callback, out nint registration)
        {
            Check(filter.Length == 416 && U32(filter) == 416 && U32(filter, 4) == 0 && U32(filter, 8) == 0 && U32(filter, 12) == 0, "CM_NOTIFY_FILTER layout");
            Check(new Guid(filter.AsSpan(16, 16)) == new Guid("72631e54-78a4-11d0-bcf7-00aa00b7b32a"), "battery interface filter");
            this.context = context;this.callback = callback;Registers++;
            if (RegisterResult != 0) {registration = 0;return RegisterResult;}
            Active++;registration = 42;return 0;
        }
        public uint Unregister(nint registration) {Check(registration == 42, "native notification handle");UnregisteredInCallback |= inCallback;Unregisters++;Active--;return 0;}
        internal void Emit(uint action, byte[] bytes)
        {
            var pointer = Marshal.AllocHGlobal(Math.Max(bytes.Length, 1));
            try {
                Marshal.Copy(bytes, 0, pointer, bytes.Length);inCallback = true;
                Check(callback!(42, context, action, pointer, (uint)bytes.Length) == 0, "callback permits native operation and never throws");
            } finally {inCallback = false;Marshal.FreeHGlobal(pointer);}
        }
    }

    private static async Task NativeInterfaceLifetime()
    {
        var platform = new NativeBatteryProbe();using var access = new DeviceAccess(new WindowsCollector(platform, aggregatePlatform: new WindowsAggregateBatteryTests.UnavailablePlatform()));
        Check(platform.Active == 0, "native interface creation is inert");
        _ = await access.Batteries.List();_ = await access.Batteries.List();
        Check(platform.Active == 1, "one actual native registration persists across discovery");
        access.Dispose();await platform.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(platform.Active == 0 && platform.ReleaseFailure is null, "native CM registration unregistered successfully");
        Console.WriteLine("Native battery interface notification: registered before discovery and unregistered on context closure.");
    }
    private sealed class NativeBatteryProbe : IWindowsBatteryPlatform
    {
        private readonly IWindowsBatteryPlatform native = new WindowsBatteryPlatform();
        internal int Active;
        internal Exception? ReleaseFailure;
        internal readonly TaskCompletionSource Stopped = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public IReadOnlyList<string> Enumerate(CancellationToken token) => native.Enumerate(token);
        public IWindowsBatteryDevice Open(string path) => native.Open(path);
        public IDisposable? ObserveInterfaces(Action<WindowsDeviceInterfaceChange> changed, Action<Exception> fail)
        {
            var registration = native.ObserveInterfaces(changed, fail);if (registration is null) return null;
            Active++;return new Notification(() => {
                try {registration.Dispose();} catch (Exception error) {ReleaseFailure = error;throw;}
                finally {Active--;Stopped.TrySetResult();}
            });
        }
        private sealed class Notification(Action stop) : IDisposable {public void Dispose() => stop();}
    }

    private static async Task InterfaceRemoval()
    {
        var platform = new BatteryPlatformFixture {EventsEnabled = true};
        platform.Slots["battery-a"] = new BatterySlotFixture();platform.Slots["battery-b"] = new BatterySlotFixture();
        using var access = new DeviceAccess(new WindowsCollector(platform, new WindowsPowerTests.PowerPlatformFixture(), new WindowsAggregateBatteryTests.UnavailablePlatform()));
        Check(platform.Registrations == 0, "construction does not register native interfaces");
        var targets = await access.Batteries.List();var old = targets[0];
        Check(platform.Registrations == 1, "registration precedes discovery");
        var stream = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(old).GetAsyncEnumerator();
        try {
            Check(await stream.MoveNextAsync(), "initial observed pack");
            platform.EmitInterface(new("BATTERY-A", true));platform.EmitInterface(new("battery-a", false));
            await Error(ErrorCode.EntityRemoved, async () => {await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));});
            await Error(ErrorCode.EntityRemoved, () => access.Get(old));
            Check((await access.Get(targets[1])).Present == true, "unrelated pack remains usable");
            var fresh = await access.Batteries.List();Check(fresh.Length == 2, "rediscovery sees reconnected pack");
            foreach (var target in fresh) Check((await access.Get(target)).Present == true, "fresh generations readable");
            await Error(ErrorCode.EntityRemoved, () => access.Get(old));
            Check(platform.Registrations == 1, "one context-owned observer across reads and watches");
        } finally {await stream.DisposeAsync();}
        Check(!platform.ObserverStopped.Task.IsCompleted, "closing a watch preserves context identity tracking");
        access.Dispose();await platform.ObserverStopped.Task.WaitAsync(TimeSpan.FromSeconds(1));
        Check(platform.ActiveHandles == 0 && platform.Threads.Distinct().Count() == 1, "device and observer cleanup share collection worker");
    }

    private static async Task PowerNotifications()
    {
        var platform = new BatteryPlatformFixture();var slot = new BatterySlotFixture();platform.Slots["battery"] = slot;
        var power = new WindowsPowerTests.PowerPlatformFixture();
        using var access = new DeviceAccess(new WindowsCollector(platform, power, new WindowsAggregateBatteryTests.UnavailablePlatform()));var target = (await access.Batteries.List())[0];
        var stream = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(target).GetAsyncEnumerator();
        try {
            Check(await stream.MoveNextAsync() && stream.Current.Level == 0.5, "initial selected battery");
            Check(power.Active == 2, "capacity and power source notifications");
            slot.Status = Words(4, 12000, 12800, 6400);
            power.Emit(WindowsPowerSettings.BatteryPercentage, 88);
            Check(await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)) && stream.Current.Level == 0.6, "read the pack, not aggregate 88 percent");
            power.Emit(WindowsPowerSettings.Source, 1);
            Check(await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)) && stream.Current.Level == 0.6, "equal battery event retained");
            slot.TagError = 1167;power.Emit(WindowsPowerSettings.BatteryPercentage, 70);
            await Error(ErrorCode.EntityRemoved, async () => {await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));});
            await TestCompletion.Until(() => Volatile.Read(ref power.Active) == 0, "removed battery notifications released");
            Check(power.Active == 0, "removal releases both notifications");
            slot.TagError = null;await Error(ErrorCode.EntityRemoved, () => access.Get(target));
            Check(power.Reads == 0, "individual battery data never comes from aggregate power status");
        } finally {await stream.DisposeAsync();}
    }

    private static async Task ReadsFields()
    {
        var platform = new BatteryPlatformFixture();platform.Slots["battery-a"] = new BatterySlotFixture();
        var callerThread = Environment.CurrentManagedThreadId;
        using var access = new DeviceAccess(new WindowsCollector(platform, aggregatePlatform: new WindowsAggregateBatteryTests.UnavailablePlatform()));
        Check(platform.Calls == 0, "inert construction");
        var targets = await access.Batteries.List();Check(targets.Length == 1, "one inserted pack");
        var snapshot = await access.Get(targets[0]);
        Check(snapshot.Present == true && snapshot.Level == 0.5 && snapshot.Charging == true && snapshot.State == BatteryState.Charging, "charging state");
        Check(snapshot.VoltageMillivolts == 12800 && snapshot.ChargeRateMilliwatts == 6400 && snapshot.CurrentMicroamps == 500000, "native power and derived current units");
        Check(snapshot.RemainingEnergyMilliwattHours == 10000 && snapshot.FullChargeEnergyMilliwattHours == 20000 && snapshot.DesignEnergyMilliwattHours == 25000, "native energy units");
        Check(snapshot.TimeToEmpty == TimeSpan.FromSeconds(600) && Math.Abs(snapshot.TemperatureCelsius!.Value - 29.95) < 1e-8, "time and temperature units");
        Check(snapshot.Technology == "LION" && snapshot.CycleCount == 42, "chemistry and cycles");
        Check(snapshot.TimeToFull is null && snapshot.AverageCurrentMicroamps is null && snapshot.ChargeCounterMicroampHours is null && snapshot.Health is null, "no fabricated unsupported values");
        Check(snapshot.CollectedAt > DateTimeOffset.UtcNow.AddSeconds(-5), "completion timestamp");
        Check(platform.ActiveHandles == 0 && platform.Threads.All(thread => thread != callerThread), "native cleanup and collection lane");
    }

    private static void Check(bool condition, string message) {if (!condition) throw new Exception(message);}

    private static async Task PartialAvailability()
    {
        var platform = new BatteryPlatformFixture();
        var slot = new BatterySlotFixture {Information = BatterySlotFixture.Info(0xc0000000, 100, 100, 0),
            Status = Words(2, 0, 0, unchecked((uint)-10)), Time = Words(uint.MaxValue)};
        slot.InformationErrors[2] = 1;platform.Slots["relative-pack"] = slot;
        using var access = new DeviceAccess(new WindowsCollector(platform, aggregatePlatform: new WindowsAggregateBatteryTests.UnavailablePlatform()));var target = (await access.Batteries.List())[0];
        var relative = await access.Get(target);
        Check(relative.Level == 0 && relative.Charging == false && relative.State == BatteryState.Discharging && relative.VoltageMillivolts == 0, "valid zero and false");
        Check(relative.RemainingEnergyMilliwattHours is null && relative.FullChargeEnergyMilliwattHours is null && relative.DesignEnergyMilliwattHours is null && relative.ChargeRateMilliwatts is null && relative.CurrentMicroamps is null, "relative units are not physical energy or power");
        Check(relative.CycleCount is null && relative.TemperatureCelsius is null && relative.TimeToEmpty is null, "unavailable optional fields");
        slot.Information = BatterySlotFixture.Info(0x80000000, 0, 0, 1);slot.Status = Words(8, 0, 0, 0);slot.Time = Words(0);
        var zero = await access.Get(target);
        Check(zero.Level is null && zero.RemainingEnergyMilliwattHours == 0 && zero.FullChargeEnergyMilliwattHours == 0 && zero.DesignEnergyMilliwattHours == 0, "zero capacity is not unknown or a divisor");
        Check(zero.ChargeRateMilliwatts == 0 && zero.CurrentMicroamps is null && zero.TimeToEmpty == TimeSpan.Zero && zero.CycleCount == 1, "zero rate, voltage and time");
        Check(zero.Health is null && zero.State == BatteryState.Idle, "critical drain is not a health diagnosis");
        slot.Status = Words(0x14, uint.MaxValue, uint.MaxValue, 0x80000000);
        var unknown = await access.Get(target);
        Check(unknown.State is null && unknown.Charging is null && unknown.Level is null && unknown.RemainingEnergyMilliwattHours is null && unknown.VoltageMillivolts is null && unknown.ChargeRateMilliwatts is null, "unknown flags and sentinels");
        slot.InformationErrors[0] = 5;slot.Status = Words(2, 100, 12000, unchecked((uint)-1200));
        var partial = await access.Get(target);
        Check(partial.State == BatteryState.Discharging && partial.VoltageMillivolts == 12000 && partial.ChargeRateMilliwatts is null && partial.Technology is null, "status survives denied metadata without guessing units");
        slot.InformationErrors[3] = 1;slot.StatusError = 5;
        await Error(ErrorCode.PermissionDenied, () => access.Get(target));
        Check(platform.ActiveHandles == 0, "all optional and failing reads release native handles");
    }

    private static async Task Error(ErrorCode code, Func<Task> action)
    {
        try {await action();throw new Exception($"Expected {code}");}
        catch (DeviceReadoutException error) when (error.Code == code) { }
    }

    private static async Task TargetLifetimes()
    {
        var platform = new BatteryPlatformFixture();var slot = new BatterySlotFixture();platform.Slots["battery-a"] = slot;
        using var access = new DeviceAccess(new WindowsCollector(platform, aggregatePlatform: new WindowsAggregateBatteryTests.UnavailablePlatform()));var old = (await access.Batteries.List())[0];
        slot.StatusError = 433;
        await Error(ErrorCode.EntityRemoved, () => access.Get(old));slot.StatusError = null;
        await Error(ErrorCode.EntityRemoved, () => access.Get(old));
        var replacement = (await access.Batteries.List())[0];Check((await access.Get(replacement)).Level == 0.5, "fresh target after reported removal");
        platform.Slots["battery-b"] = new BatterySlotFixture {TagError = 5};
        await Error(ErrorCode.PermissionDenied, () => access.Batteries.List());
        Check((await access.Get(replacement)).Present == true, "another inaccessible slot cannot block selected pack");
        platform.Slots["battery-b"].TagError = null;platform.Slots["empty-slot"] = new BatterySlotFixture {Tag = 0};
        Check((await access.Batteries.List()).Length == 2, "equal tags in separate slots remain separate targets");
        using var removalDeadline = new CancellationTokenSource();
        await using var stream = access.WithPollInterval(TimeSpan.FromMilliseconds(15)).Watch(replacement, removalDeadline.Token).GetAsyncEnumerator();
        Check(await stream.MoveNextAsync(), "first selected battery snapshot");
        await Task.Delay(75); // A slow consumer may already have valid pre-removal snapshots queued.
        slot.Tag = 8;
        removalDeadline.CancelAfter(TimeSpan.FromSeconds(1));
        await Error(ErrorCode.EntityRemoved, async () => {
            while (await stream.MoveNextAsync()) Check(stream.Current.Level == 0.5, "queued pre-removal state");
        });
        Check((await access.Capabilities.Get(replacement)).Readable == false, "retired capability");
        slot.Tag = 7;_ = await access.Batteries.List();
        await Error(ErrorCode.EntityRemoved, () => access.Get(replacement));
        slot.Tag = 0;Check((await access.Batteries.List()).Length == 1, "absent slot is not a present=false placeholder");
        Check(platform.ActiveHandles == 0, "removed devices and failed discovery release handles");
    }

    private static async Task SchedulingAndCleanup()
    {
        var platform = new BatteryPlatformFixture();var slot = new BatterySlotFixture();platform.Slots["battery"] = slot;
        using var access = new DeviceAccess(new WindowsCollector(platform, new WindowsPowerTests.PowerPlatformFixture(), new WindowsAggregateBatteryTests.UnavailablePlatform()));var target = (await access.Batteries.List())[0];
        await using (var stream = access.WithPollInterval(TimeSpan.FromMilliseconds(15)).Watch(target).GetAsyncEnumerator()) {
            Check(await stream.MoveNextAsync(), "initial battery state");var first = stream.Current;
            Check(await stream.MoveNextAsync(), "equal battery state");
            Check(first.Level == stream.Current.Level && first.CollectedAt < stream.Current.CollectedAt, "equal values retain distinct completion times");
        }
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        using var release = new ManualResetEventSlim();
        slot.BeforeStatus = () => {started.TrySetResult();release.Wait();};
        var timed = access.WithReadTimeout(TimeSpan.FromMilliseconds(80)).Get(target);
        var timedFailure = Error(ErrorCode.ReadTimeout, () => timed);
        try {
            await started.Task.WaitAsync(TimeSpan.FromSeconds(1));
            var ticks = 0;
            while (!timedFailure.IsCompleted) {await Task.Delay(5);ticks++;}
            await timedFailure;Check(ticks > 0, "host progresses while native status is blocked");
        } finally {release.Set();}
        slot.BeforeStatus = null;
        Check((await access.Get(target)).Present == true, "later read succeeds after timed-out native call releases");
        Check(platform.ActiveHandles == 0, "deadline and stream disposal release handles");
        using var cancelled = new CancellationTokenSource();cancelled.Cancel();
        try {await access.Get(target, cancelled.Token);throw new Exception("Expected cancellation");}
        catch (OperationCanceledException) { }
        Check(platform.ActiveHandles == 0, "pre-cancelled read owns no native handles");
    }

    private static async Task InvalidReplies()
    {
        var platform = new BatteryPlatformFixture();var slot = new BatterySlotFixture();platform.Slots["battery"] = slot;
        using var access = new DeviceAccess(new WindowsCollector(platform, aggregatePlatform: new WindowsAggregateBatteryTests.UnavailablePlatform()));var target = (await access.Batteries.List())[0];
        slot.Information = new byte[35];await Error(ErrorCode.ReadFailed, () => access.Get(target));
        slot.Information = BatterySlotFixture.Info(0x80000000, 25000, 20000, 42);slot.Status = new byte[15];
        await Error(ErrorCode.ReadFailed, () => access.Get(target));
        slot.Status = Words(2, 10000, 12800, unchecked((uint)-6400));
        var recovered = await access.Get(target);
        Check(recovered.State == BatteryState.Discharging && recovered.ChargeRateMilliwatts == -6400 && recovered.CurrentMicroamps == -500000, "transient failures do not replace a pack or invert discharge");
        slot.Status = Words(6, 20000, 12800, 0);var invalid = await access.Get(target);
        Check(invalid.State is null && invalid.Charging is null, "contradictory charge flags are unknown");
        slot.Status = Words(1, 20000, 12800, 0);Check((await access.Get(target)).State == BatteryState.Full, "full capacity without active charge or drain");
        slot.Status = Words(1, 10000, 12800, 0);Check((await access.Get(target)).State == BatteryState.NotCharging, "online but not charging");
        Check(platform.ActiveHandles == 0, "malformed responses release native handles");
    }

    private static async Task FailedInventoryRemoval()
    {
        for (var mode = 0; mode < 3; mode++) {
            var platform = new BatteryPlatformFixture();var slot = new BatterySlotFixture();platform.Slots["battery-a"] = slot;
            using var access = new DeviceAccess(new WindowsCollector(platform, aggregatePlatform: new WindowsAggregateBatteryTests.UnavailablePlatform()));var old = (await access.Batteries.List())[0];
            if (mode == 0) slot.Tag = 0;
            else if (mode == 1) platform.Slots.Remove("battery-a");
            else slot.Tag = 8;
            platform.Slots["battery-b"] = new BatterySlotFixture {TagError = 5};
            await Error(ErrorCode.PermissionDenied, () => access.Batteries.List());
            slot.Tag = 7;platform.Slots["battery-a"] = slot;platform.Slots["battery-b"].TagError = null;
            await Error(ErrorCode.EntityRemoved, () => access.Get(old));
            var fresh = await access.Batteries.List();Check(fresh.Length == 2, "fresh generation inventory");
            foreach (var target in fresh) Check((await access.Get(target)).Present == true, "fresh generation reads");
            Check(platform.ActiveHandles == 0, "failed inventory cleanup");
        }
    }

    private sealed class BatterySlotFixture
    {
        internal uint Tag = 7;
        internal byte[] Information = Info(0x80000000, 25000, 20000, 42);
        internal byte[] Status = Words(4, 10000, 12800, 6400);
        internal byte[] Temperature = Words(3031);
        internal byte[] Time = Words(600);
        internal readonly Dictionary<uint, int> InformationErrors = [];
        internal int? StatusError;
        internal int? TagError;
        internal Action? BeforeStatus;
        internal Action? BeforeTag;
        internal static byte[] Info(uint capabilities, uint design, uint full, uint cycles)
        {
            var bytes = Words(capabilities, 1, 0, design, full, 0, 0, 0, cycles);
            "LION"u8.CopyTo(bytes.AsSpan(8));return bytes;
        }
    }

    private sealed class BatteryPlatformFixture : IWindowsBatteryPlatform
    {
        internal readonly Dictionary<string, BatterySlotFixture> Slots = [];
        internal readonly List<int> Threads = [];
        internal int Calls, ActiveHandles;
        internal bool EventsEnabled;
        internal IConfigurationNotifications? Configuration;
        internal Func<IWindowsBatteryDevice>? StatusDevice;
        internal int Registrations;
        internal Action<WindowsDeviceInterfaceChange> EmitInterface = _ => { };
        internal readonly TaskCompletionSource ObserverStopped = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public IDisposable? ObserveInterfaces(Action<WindowsDeviceInterfaceChange> changed, Action<Exception> fail)
        {
            if (!EventsEnabled && Configuration is null) return null;
            Record();Registrations++;EmitInterface = changed;
            var native = Configuration is null ? null : new WindowsDeviceInterfaces(Configuration).Subscribe(WindowsBatteryPlatform.InterfaceClass, changed, fail);
            if (Configuration is not null && native is null) return null;
            return new Notification(() => {Record();try {native?.Dispose();} finally {ObserverStopped.TrySetResult();}});
        }
        public IReadOnlyList<string> Enumerate(CancellationToken token) {Record();if (EventsEnabled || Configuration is not null) Check(Registrations == 1, "observe before enumerate");token.ThrowIfCancellationRequested();return Slots.Keys.ToArray();}
        public IWindowsBatteryDevice Open(string path) {Record();ActiveHandles++;return new Device(this, Slots[path]);}
        public IWindowsBatteryDevice? OpenStatus(string path) {Check(Slots.ContainsKey(path), "selected status device path");return StatusDevice?.Invoke();}
        private void Record() {Calls++;Threads.Add(Environment.CurrentManagedThreadId);}
        private sealed class Notification(Action stop) : IDisposable {public void Dispose() => stop();}
        private sealed class Device(BatteryPlatformFixture owner, BatterySlotFixture slot) : IWindowsBatteryDevice
        {
            private bool disposed;
            public byte[] Query(BatteryIoControl control, byte[] input, int outputSize, CancellationToken token)
            {
                owner.Record();token.ThrowIfCancellationRequested();Check(!disposed, "query after native disposal");
                if ((uint)control == 0x294040) {
                    slot.BeforeTag?.Invoke();
                    if (slot.TagError is { } error) throw new Win32Exception(error);
                    Check(input.Length == 4 && U32(input) == 0 && outputSize == 4, "nonblocking tag query");return Words(slot.Tag);
                }
                Check(U32(input) == slot.Tag, "tag-pinned query");
                if ((uint)control == 0x29404c) {
                    slot.BeforeStatus?.Invoke();
                    if (slot.StatusError is { } error) throw new Win32Exception(error);
                    Check(input.Length == 20 && U32(input, 4) == 0 && outputSize == 16, "nonblocking status query");return slot.Status.ToArray();
                }
                Check((uint)control == 0x294044 && input.Length == 12 && U32(input, 8) == 0, "read-only information query at current drain");
                if (slot.InformationErrors.TryGetValue(U32(input, 4), out var informationError)) throw new Win32Exception(informationError);
                return U32(input, 4) switch {0 => slot.Information.ToArray(), 2 => slot.Temperature.ToArray(), 3 => slot.Time.ToArray(), _ => throw new Win32Exception(1)};
            }
            public void Dispose() {if (!disposed) {disposed = true;owner.ActiveHandles--;}}
        }
    }
    private static uint U32(byte[] bytes, int offset = 0) => BinaryPrimitives.ReadUInt32LittleEndian(bytes.AsSpan(offset));
    private static byte[] Words(params uint[] values)
    {
        var bytes = new byte[values.Length * 4];
        for (var index = 0; index < values.Length; index++) BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(index * 4), values[index]);
        return bytes;
    }
}
