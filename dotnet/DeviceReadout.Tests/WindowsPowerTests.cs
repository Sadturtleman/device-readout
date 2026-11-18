using System.Runtime.Versioning;
using System.Collections.Concurrent;
using DeviceReadout;
using DeviceReadout.Windows;

[SupportedOSPlatform("windows")]
internal static class WindowsPowerTests
{
    internal static IEnumerable<(string Name, Func<Task> Run)> Cases() => [
        ("Windows power reads leave an ambiguous DC source null without losing saver state", AmbiguousDirectSource),
        ("Windows power get and watch distinguish onboard-only capabilities from UPS and unknown flags", SourceCapabilities),
        ("Windows power events preserve payload values and equal samples on the collection worker", EventValues),
        ("real Windows power notifications deliver current settings without a UI message loop", NativeNotifications),
        ("Windows power watches retain polling fallback and release partial or failed subscriptions", SubscriptionLifecycle)
    ];

    private static async Task AmbiguousDirectSource()
    {
        var platform = new PowerPlatformFixture {State = new(0, 1), NotificationsAvailable = false};
        using var access = new DeviceAccess(new WindowsCollector(powerPlatform: platform));
        var snapshot = await access.Get(Entities.Power);
        Check(snapshot.PowerSource is null, "DC alone cannot distinguish an onboard battery from a UPS");
        Check(snapshot.PowerSaveMode == true, "unavailable source classification preserves saver state");
        await using var stream = access.WithPollInterval(TimeSpan.FromMilliseconds(15)).Watch(Entities.Power).GetAsyncEnumerator();
        for (var i = 0; i < 2; i++) {
            Check(await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)), "initial and polled snapshots");
            Check(stream.Current.PowerSource is null && stream.Current.PowerSaveMode == true,
                "watch applies the same source semantics as get");
        }
    }

    private static async Task EventValues()
    {
        var platform = new PowerPlatformFixture();
        var caller = Environment.CurrentManagedThreadId;
        using var access = new DeviceAccess(new WindowsCollector(powerPlatform: platform));
        Check(platform.Reads == 0 && platform.Active == 0, "inert creation");
        var stream = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(Entities.Power).GetAsyncEnumerator();
        try {
            Check(await stream.MoveNextAsync() && stream.Current.PowerSource == PowerSource.External, "initial power read");
            Check(platform.Active == 2, "power source and battery saver notifications");
            platform.State = new(0, 1);
            platform.Emit(WindowsPowerSettings.Source, 2);
            platform.Emit(WindowsPowerSettings.Source, 1);
            platform.Emit(WindowsPowerSettings.Source, 1);
            foreach (var expected in new[] {PowerSource.Ups, PowerSource.Battery, PowerSource.Battery}) {
                Check(await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)) && stream.Current.PowerSource == expected,
                    "captured native payload survives later OS state and duplicates");
            }
            platform.Emit(WindowsPowerSettings.Saving, 1);
            Check(await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)) && stream.Current.PowerSaveMode == true, "saver event");
            platform.Emit(WindowsPowerSettings.Saving, 7);
            Check(await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)) && stream.Current.PowerSaveMode is null, "unknown native saver state");
            platform.Emit(WindowsPowerSettings.Source, uint.MaxValue);
            Check(await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)) && stream.Current.PowerSource is null, "unknown native power source");
            Check((await access.Get(Entities.Power)).PowerSource is null, "event payload does not become a cached source for unrelated reads");
        } finally {await stream.DisposeAsync();}
        await TestCompletion.Until(() => Volatile.Read(ref platform.Active) == 0, "power notifications released");
        Check(platform.Active == 0, "notifications released with stream");
        Check(platform.NativeThreads.All(thread => thread == platform.NativeThreads[0] && thread != caller), "registration, reads and cleanup share collection lane");
        var reads = platform.Reads;platform.Emit(WindowsPowerSettings.Source, 1);
        await Task.Delay(20);Check(platform.Reads == reads, "late callback performs no collection");
    }

    private static async Task SourceCapabilities()
    {
        (string Name, WindowsPowerState State, PowerSource? Source, bool? Saver)[] cases = [
            ("onboard-only", new(0, 1, BatteryCapabilities: new(1, 0, 0)), PowerSource.Battery, true),
            ("UPS", new(0, 0, BatteryCapabilities: new(1, 1, 1)), null, false),
            ("mixed batteries", new(0, 1, BatteryCapabilities: new(1, 1, 0)), null, true),
            ("short-term batteries", new(0, 1, BatteryCapabilities: new(1, 0, 1)), null, true),
            ("no batteries", new(0, 0, BatteryCapabilities: new(0, 0, 0)), null, false),
            ("unknown battery presence", new(0, 1, BatteryCapabilities: new(255, 0, 0)), null, true),
            ("unknown UPS presence", new(0, 1, BatteryCapabilities: new(1, 255, 0)), null, true),
            ("unknown battery duration", new(0, 1, BatteryCapabilities: new(1, 0, 255)), null, true),
            ("external with UPS present", new(1, 0, BatteryCapabilities: new(1, 1, 1)), PowerSource.External, false),
            ("unknown line status", new(255, 1, BatteryCapabilities: new(1, 0, 0)), null, true),
            ("unknown saver flag", new(0, 7, BatteryCapabilities: new(1, 0, 0)), PowerSource.Battery, null)
        ];
        foreach (var item in cases) {
            var platform = new PowerPlatformFixture {State = item.State, NotificationsAvailable = false};
            using var access = new DeviceAccess(new WindowsCollector(powerPlatform: platform));
            var snapshot = await access.Get(Entities.Power);
            Check(snapshot.PowerSource == item.Source && snapshot.PowerSaveMode == item.Saver && snapshot.ThermalState is null,
                $"{item.Name}: independent nullable fields from get");
            await using var stream = access.WithPollInterval(TimeSpan.FromMilliseconds(15)).Watch(Entities.Power).GetAsyncEnumerator();
            DateTimeOffset? previous = null;
            for (var i = 0; i < 2; i++) {
                Check(await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)), $"{item.Name}: watch value");
                Check(stream.Current.PowerSource == item.Source && stream.Current.PowerSaveMode == item.Saver,
                    $"{item.Name}: identical get/watch semantics");
                Check(previous is null || stream.Current.CollectedAt > previous, $"{item.Name}: equal values are collected again");
                previous = stream.Current.CollectedAt;
            }
        }
    }

    private static async Task NativeNotifications()
    {
        var native = new NativePowerProbe();
        using var access = new DeviceAccess(new WindowsCollector(powerPlatform: native));
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(4));
        // Registration delivers a native current-value notification for each of the two settings,
        // in addition to the SDK's initial read. An hour-long polling interval cannot supply these.
        await using (var stream = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(Entities.Power, deadline.Token).GetAsyncEnumerator()) {
            var samples = 0;
            do {
                Check(await stream.MoveNextAsync(), "native current-setting callback");samples++;
                Check(stream.Current.CollectedAt > DateTimeOffset.UtcNow.AddSeconds(-4), "native snapshot timestamp");
            } while (samples < 3 || !native.Callbacks.ContainsKey(WindowsPowerSettings.Source) || !native.Callbacks.ContainsKey(WindowsPowerSettings.Saving));
        }
        await TestCompletion.Until(() => Volatile.Read(ref native.Active) == 0, "actual power notifications released");
        Check(native.Active == 0 && native.ReleaseFailures.IsEmpty, "both actual native registrations unregistered successfully");
        Console.WriteLine("Native power notifications: source and battery saver callbacks received and unregistered without a window.");
    }

    private sealed class NativePowerProbe : IWindowsPowerPlatform
    {
        private readonly WindowsPowerPlatform native = new();
        internal readonly ConcurrentDictionary<Guid, byte> Callbacks = new();
        internal readonly ConcurrentBag<Exception> ReleaseFailures = [];
        internal int Active;
        public WindowsPowerState Read() => native.Read();
        public IDisposable? Subscribe(Guid setting, Action<uint> changed, Action<Exception> fail)
        {
            var registration = native.Subscribe(setting, value => {Callbacks.TryAdd(setting, 0);changed(value);}, fail);
            if (registration is null) return null;
            Active++;
            return new Subscription(() => {
                try {registration.Dispose();} catch (Exception error) {ReleaseFailures.Add(error);throw;}
                finally {Active--;}
            });
        }
        private sealed class Subscription(Action release) : IDisposable {public void Dispose() => release();}
    }

    private static async Task SubscriptionLifecycle()
    {
        foreach (var available in new[] {false, true}) {
            var platform = new PowerPlatformFixture {NotificationsAvailable = available};
            using var access = new DeviceAccess(new WindowsCollector(powerPlatform: platform));
            await using (var stream = access.WithPollInterval(TimeSpan.FromMilliseconds(15)).Watch(Entities.Power).GetAsyncEnumerator()) {
                Check(await stream.MoveNextAsync(), "initial state with or without events");
                var first = stream.Current.CollectedAt;
                Check(await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)) && stream.Current.CollectedAt > first, "fallback/hybrid polling retains equal states");
                Check(platform.Active == (available ? 2 : 0), "optional native registrations");
            }
            await TestCompletion.Until(() => Volatile.Read(ref platform.Active) == 0, "polled power notifications released");
            Check(platform.Active == 0, "polled stream releases notifications");
        }
        var failed = new PowerPlatformFixture {RegistrationFailure = WindowsPowerSettings.Saving};
        using var failureAccess = new DeviceAccess(new WindowsCollector(powerPlatform: failed));
        await using (var stream = failureAccess.Watch(Entities.Power).GetAsyncEnumerator()) {
            try {await stream.MoveNextAsync();throw new Exception("Expected failed registration");}
            catch (DeviceReadoutException error) when (error.Code == ErrorCode.ReadFailed) { }
        }
        Check(failed.Active == 0, "second registration failure releases first registration");
        failed.RegistrationFailure = null;
        await using (var stream = failureAccess.Watch(Entities.Power).GetAsyncEnumerator()) {
            Check(await stream.MoveNextAsync(), "fresh stream after registration failure");
            failed.Fail(new DeviceReadoutException(ErrorCode.PermissionDenied, "Native notification failed."));
            try {await stream.MoveNextAsync();throw new Exception("Expected native callback failure");}
            catch (DeviceReadoutException error) when (error.Code == ErrorCode.PermissionDenied) { }
        }
        await TestCompletion.Until(() => Volatile.Read(ref failed.Active) == 0, "failed power notifications released");
        Check(failed.Active == 0, "native failure releases all registrations");
        Check((await failureAccess.Get(Entities.Power)).PowerSaveMode == false, "a failed subscription does not poison independent reads");
    }

    internal sealed class PowerPlatformFixture : IWindowsPowerPlatform
    {
        private readonly List<(Guid Setting, Action<uint> Changed)> listeners = [];
        private readonly List<Action<Exception>> failures = [];
        internal readonly List<int> NativeThreads = [];
        internal int Reads, Active;
        internal bool NotificationsAvailable = true;
        internal Guid? RegistrationFailure;
        internal WindowsPowerState State = new(1, 0);
        internal Exception? ReadFailure;
        public WindowsPowerState Read() {Record();Reads++;if (ReadFailure is not null) throw ReadFailure;return State;}
        public IDisposable? Subscribe(Guid setting, Action<uint> changed, Action<Exception> fail)
        {
            Record();
            if (RegistrationFailure == setting) throw new DeviceReadoutException(ErrorCode.ReadFailed, "Native registration failed.");
            if (!NotificationsAvailable) return null;
            Active++;listeners.Add((setting, changed));failures.Add(fail);
            return new Subscription(() => {Record();Active--;failures.Remove(fail);});
        }
        internal void Emit(Guid setting, uint value) {foreach(var listener in listeners.Where(item => item.Setting == setting)) listener.Changed(value);}
        internal void Fail(Exception error) {foreach(var fail in failures.ToArray()) fail(error);}
        private void Record() => NativeThreads.Add(Environment.CurrentManagedThreadId);
        private sealed class Subscription(Action release) : IDisposable {public void Dispose() => release();}
    }
    private static void Check(bool condition, string message) {if (!condition) throw new Exception(message);}
}
