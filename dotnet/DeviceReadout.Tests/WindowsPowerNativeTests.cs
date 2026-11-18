using System.Diagnostics;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Text.Json;
using DeviceReadout;
using DeviceReadout.Windows;

[SupportedOSPlatform("windows")]
internal static class WindowsPowerNativeTests
{
    [Flags] private enum Behavior : uint {Normal = 0, StatusFailure = 1, CapabilityFailure = 2, HoldStatus = 4, HoldCapabilities = 8}
    private sealed record FieldCase(string Name, uint Status, uint Capabilities, Behavior Behavior, PowerSource? Source, bool? Saver);
    private static readonly FieldCase[] FieldCases = [
        new("onboard", 0x100, 1, Behavior.Normal, PowerSource.Battery, true),
        new("ups", 0x100, 0x10101, Behavior.Normal, null, true),
        new("mixed", 0x100, 0x101, Behavior.Normal, null, true),
        new("short-term", 0x100, 0x10001, Behavior.Normal, null, true),
        new("absent", 0x100, 0, Behavior.Normal, null, true),
        new("unknown-battery", 0x100, 0xff, Behavior.Normal, null, true),
        new("unknown-ups", 0x100, 0xff01, Behavior.Normal, null, true),
        new("unknown-duration", 0x100, 0xff0001, Behavior.Normal, null, true),
        // A query in either of these cases would block: capabilities are irrelevant to their source.
        new("external", 1, 1, Behavior.HoldCapabilities, PowerSource.External, false),
        new("unknown-line", 0x1ff, 1, Behavior.HoldCapabilities, null, true),
        new("unknown-saver", 0x700, 1, Behavior.Normal, PowerSource.Battery, null),
        new("optional-failure", 0x100, 1, Behavior.CapabilityFailure, null, true)
    ];
    private static readonly string[] HeldScenarios = [
        "status-timeout", "capability-timeout", "capability-cancel", "context-dispose",
        "watch-initial-timeout", "watch-poll-timeout", "watch-cancel", "watch-dispose"
    ];

    internal static async Task RunParent(string fixturePath)
    {
        fixturePath = Path.GetFullPath(fixturePath);
        Check(File.Exists(fixturePath), "native power fixture exists");
        var scenarios = FieldCases.Select(item => item.Name).Concat(["status-failure", "capability-recovery", "system-capabilities"]).Concat(HeldScenarios).ToArray();
        foreach (var scenario in scenarios) {
            var start = new ProcessStartInfo(Environment.ProcessPath!) {
                UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true
            };
            if (string.Equals(Path.GetFileNameWithoutExtension(Environment.ProcessPath), "dotnet", StringComparison.OrdinalIgnoreCase))
                start.ArgumentList.Add(Assembly.GetExecutingAssembly().Location);
            foreach (var argument in new[] {"--power-native-child", fixturePath, scenario}) start.ArgumentList.Add(argument);
            using var child = Process.Start(start) ?? throw new Exception("Could not start the owned power fixture child.");
            var output = child.StandardOutput.ReadToEndAsync();
            var error = child.StandardError.ReadToEndAsync();
            try {
                await child.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(25));
                var stdout = await output;
                var stderr = await error;
                Check(child.ExitCode == 0, $"Power fixture {scenario} exited {child.ExitCode}: {stdout} {stderr}");
                Check(stdout.Contains($"\"scenario\":\"{scenario}\""), "child identifies its completed scenario");
                Console.WriteLine(stdout.Trim());
            } finally {
                if (!child.HasExited) {child.Kill(entireProcessTree: true);await child.WaitForExitAsync();}
            }
        }
        // SDK assembly imports in this parent were never redirected.
        using var parentAccess = WindowsDeviceAccess.Create();
        var parent = await parentAccess.Get(Entities.Power);
        Console.WriteLine("POWER_NATIVE_PARENT " + JsonSerializer.Serialize(new {source = parent.PowerSource?.ToString(), saver = parent.PowerSaveMode}));
        Console.WriteLine($"{scenarios.Length}/{scenarios.Length} Windows power native scenarios passed.");
    }

    internal static async Task RunChild(string fixturePath, string scenario)
    {
        var item = FieldCases.SingleOrDefault(item => item.Name == scenario);
        if (item is null) {
            if (scenario == "status-failure") {await StatusFailure(fixturePath);return;}
            if (scenario == "capability-recovery") {await CapabilityRecovery(fixturePath);return;}
            if (scenario == "system-capabilities") {await SystemCapabilities(fixturePath);return;}
            if (HeldScenarios.Contains(scenario)) {await HeldNativeCall(fixturePath, scenario);return;}
            throw new ArgumentException("Unknown power fixture scenario.");
        }
        using var fixture = new Fixture(fixturePath);
        fixture.Configure(item.Status, item.Capabilities, item.Behavior);
        var caller = GetCurrentThreadId();
        using var access = WindowsDeviceAccess.Create();
        Check(fixture.Count(Counter.Status) == 0 && fixture.Count(Counter.Capabilities) == 0, "inert SDK creation");
        var snapshot = await access.Get(Entities.Power);
        Check(snapshot.PowerSource == item.Source && snapshot.PowerSaveMode == item.Saver && snapshot.ThermalState is null,
            "native status/capability ABI produces the expected public snapshot");
        await using (var stream = access.WithPollInterval(TimeSpan.FromMilliseconds(20)).Watch(Entities.Power).GetAsyncEnumerator()) {
            DateTimeOffset? previous = null;
            for (var i = 0; i < 2; i++) {
                Check(await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(2)), "native initial/polled snapshot");
                Check(stream.Current.PowerSource == item.Source && stream.Current.PowerSaveMode == item.Saver,
                    "native get/watch field parity");
                Check(previous is null || stream.Current.CollectedAt > previous, "native duplicate samples have fresh timestamps");
                previous = stream.Current.CollectedAt;
            }
        }
        _ = await access.Get(Entities.Power); // A fresh read also waits behind any already-owned collection work.
        Check(fixture.Count(Counter.Status) >= 4, "native status executed for get and watch");
        Check((item.Status & 0xff) == 0 ? fixture.Count(Counter.Capabilities) >= 4 : fixture.Count(Counter.Capabilities) == 0,
            "native capabilities are queried only for offline status");
        Check(fixture.Count(Counter.Registrations) == 2, "unsupported native registration uses polling fallback");
        Check(fixture.Count(Counter.WorkerThread) != caller && fixture.Count(Counter.DifferentThread) == 0,
            "all native queries and registration attempts remain on one noncaller worker");
        Check(fixture.Count(Counter.Active) == 0, "native calls returned before child completion");
        Console.WriteLine("POWER_NATIVE_CHILD " + JsonSerializer.Serialize(new {
            scenario, statusCalls = fixture.Count(Counter.Status), capabilityCalls = fixture.Count(Counter.Capabilities),
            workerThread = fixture.Count(Counter.WorkerThread), callerThread = caller,
            source = snapshot.PowerSource?.ToString(), saver = snapshot.PowerSaveMode
        }));
    }

    private static async Task StatusFailure(string fixturePath)
    {
        using var fixture = new Fixture(fixturePath);
        fixture.Configure(0x100, 1, Behavior.StatusFailure);
        using var access = WindowsDeviceAccess.Create();
        var error = await ReadError(ErrorCode.ReadFailed, () => access.Get(Entities.Power));
        Check(error.Message.Contains("Win32 31"), "required status failure preserves the native error code");
        Check(fixture.Count(Counter.Capabilities) == 0, "failed required status does not query optional capabilities");
        await using (var stream = access.Watch(Entities.Power).GetAsyncEnumerator())
            await ReadError(ErrorCode.ReadFailed, () => stream.MoveNextAsync().AsTask());
        fixture.Configure(0x100, 1, Behavior.Normal);
        Check((await access.Get(Entities.Power)).PowerSource == PowerSource.Battery, "fresh reads recover after required native failure");
        Console.WriteLine("POWER_NATIVE_CHILD " + JsonSerializer.Serialize(new {scenario = "status-failure", nativeError = 31, recovered = true}));
    }

    private static async Task CapabilityRecovery(string fixturePath)
    {
        using var fixture = new Fixture(fixturePath);
        fixture.Configure(0x100, 1, Behavior.Normal);
        using var access = WindowsDeviceAccess.Create();
        await using var stream = access.WithPollInterval(TimeSpan.FromMilliseconds(20)).Watch(Entities.Power).GetAsyncEnumerator();
        await UntilSource(PowerSource.Battery);
        fixture.Configure(0x100, 1, Behavior.CapabilityFailure);
        await UntilSource(null);
        fixture.Configure(0x100, 1, Behavior.Normal);
        await UntilSource(PowerSource.Battery);
        Console.WriteLine("POWER_NATIVE_CHILD " + JsonSerializer.Serialize(new {scenario = "capability-recovery", streamRetained = true, saverRetained = true}));

        async Task UntilSource(PowerSource? expected)
        {
            var deadline = Stopwatch.StartNew();
            do {
                Check(await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(2)), "native recovery stream remains open");
                Check(stream.Current.PowerSaveMode == true, "optional native failure preserves saver state");
                if (stream.Current.PowerSource == expected) return;
            } while (deadline.Elapsed < TimeSpan.FromSeconds(2));
            throw new TimeoutException("Native source did not reach its expected state.");
        }
    }

    private static async Task<DeviceReadoutException> ReadError(ErrorCode expected, Func<Task> operation)
    {
        try {await operation().WaitAsync(TimeSpan.FromSeconds(2));}
        catch (DeviceReadoutException error) when (error.Code == expected) {return error;}
        throw new Exception($"Expected {expected}.");
    }

    private static async Task SystemCapabilities(string fixturePath)
    {
        var referencePath = Path.Combine(Path.GetDirectoryName(Path.GetFullPath(fixturePath))!, "device_readout_memory_probe.dll");
        var referenceLibrary = NativeLibrary.Load(referencePath);
        var reference = Marshal.GetDelegateForFunctionPointer<NativeValue>(NativeLibrary.GetExport(referenceLibrary, "readout_probe_battery_class"));
        var before = reference();
        Check(before != uint.MaxValue, "independent Windows SDK capability query succeeded");
        // Only the coarse AC-line response is controlled. SDK PowrProf imports use the real system DLL.
        using var fixture = new Fixture(fixturePath, redirectCapabilities: false);
        fixture.Configure(0x100, before == 1 ? 0u : 1u, Behavior.Normal);
        using var access = WindowsDeviceAccess.Create();
        var snapshot = await access.Get(Entities.Power);
        Check(reference() == before, "system capability reference stayed stable across the public read");
        PowerSource? expected = before == 1 ? PowerSource.Battery : null;
        Check(snapshot.PowerSource == expected && snapshot.PowerSaveMode == true,
            "real system capability collection agrees with the independent Windows SDK reference");
        Check(fixture.Count(Counter.Status) == 1 && fixture.Count(Counter.Capabilities) == 0,
            "only status was replaced; the capability fixture was not invoked");
        Console.WriteLine("POWER_NATIVE_CHILD " + JsonSerializer.Serialize(new {
            scenario = "system-capabilities", capabilityReference = before, source = snapshot.PowerSource?.ToString(),
            nativeSystemCapabilities = true, controlledAcLineStatus = 0
        }));
        // Both native libraries remain owned by this child until its process exits.
    }

    private static async Task HeldNativeCall(string fixturePath, string scenario)
    {
        using var fixture = new Fixture(fixturePath);
        using var access = WindowsDeviceAccess.Create();
        using var caller = new CancellationTokenSource();
        var hostThread = GetCurrentThreadId();
        var ticks = 0;
        using var heartbeat = new Timer(_ => Interlocked.Increment(ref ticks), null, 0, 5);
        var isWatch = scenario.StartsWith("watch-", StringComparison.Ordinal);
        var startsWithValue = isWatch && scenario != "watch-initial-timeout";
        var hold = scenario == "status-timeout" ? Behavior.HoldStatus : Behavior.HoldCapabilities;
        var configured = access.WithReadTimeout(TimeSpan.FromMilliseconds(250)).WithPollInterval(TimeSpan.FromMilliseconds(40));
        IAsyncEnumerator<PowerSnapshot>? stream = null;
        Task? pending = null;
        var progressDuringHold = 0;
        var contextClosed = false;
        try {
            fixture.Configure(0x100, 1, startsWithValue ? Behavior.Normal : hold);
            if (isWatch) {
                stream = configured.Watch(Entities.Power, caller.Token).GetAsyncEnumerator();
                if (startsWithValue) {
                    Check(await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(2)), "initial native snapshot before hold");
                    Check(stream.Current.PowerSource == PowerSource.Battery, "initial native onboard source");
                    fixture.Configure(0x100, 1, hold);
                }
                if (scenario != "watch-dispose") pending = Drain();
            } else pending = configured.Get(Entities.Power, caller.Token);

            await TestCompletion.Until(() => fixture.Count(Counter.Blocked) == 1, "native power call entered its controlled hold");
            var before = Volatile.Read(ref ticks);
            await Task.Delay(40);
            progressDuringHold = Volatile.Read(ref ticks) - before;
            Check(progressDuringHold >= 2 && fixture.Count(Counter.Blocked) == 1, "host timer continues while the native call remains held");
            Check(fixture.Count(Counter.WorkerThread) != hostThread && fixture.Count(Counter.DifferentThread) == 0,
                "held native status and capability work stays off the caller");
            if (scenario.EndsWith("timeout", StringComparison.Ordinal)) {
                await ReadError(ErrorCode.ReadTimeout, () => pending!);
            } else if (scenario.EndsWith("cancel", StringComparison.Ordinal)) {
                caller.Cancel();
                await Canceled(pending!);
            } else if (scenario == "context-dispose") {
                access.Dispose();contextClosed = true;
                await Canceled(pending!);
                await ReadError(ErrorCode.EntityRemoved, () => access.Get(Entities.Power));
            } else {
                await stream!.DisposeAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(2));
            }
            Check(fixture.Count(Counter.Blocked) == 1 && fixture.Count(Counter.Active) == 1,
                "public deadline/cancellation/disposal completes before native return");
        } finally {
            fixture.Release();
            if (pending is not null) {
                try {await pending.WaitAsync(TimeSpan.FromSeconds(2));}
                catch (OperationCanceledException) { }
                catch (DeviceReadoutException) { }
            }
            if (stream is not null) await stream.DisposeAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(2));
            await TestCompletion.Until(() => fixture.Count(Counter.Active) == 0, "released native power call returned");
        }
        if (!contextClosed) {
            fixture.Configure(0x100, 1, Behavior.Normal);
            Check((await access.Get(Entities.Power)).PowerSource == PowerSource.Battery, "context recovers after the held native call returns");
        }
        Console.WriteLine("POWER_NATIVE_CHILD " + JsonSerializer.Serialize(new {
            scenario, progressDuringHold, completedBeforeNativeReturn = true, nativeCallsRemaining = fixture.Count(Counter.Active),
            workerThread = fixture.Count(Counter.WorkerThread), callerThread = hostThread, recovered = !contextClosed
        }));

        async Task Drain()
        {
            while (await stream!.MoveNextAsync()) { }
            throw new Exception("Expected watch error or cancellation instead of normal completion.");
        }
    }

    private static async Task Canceled(Task pending)
    {
        try {await pending.WaitAsync(TimeSpan.FromSeconds(2));}
        catch (OperationCanceledException) {return;}
        throw new Exception("Expected cancellation.");
    }

    private enum Counter : uint {Status, Capabilities, Active, Blocked, WorkerThread, DifferentThread, Registrations}

    private sealed class Fixture : IDisposable
    {
        private readonly ConfigureCall configure;
        private readonly ReleaseCall release;
        private readonly CounterCall count;
        internal Fixture(string path, bool redirectCapabilities = true)
        {
            var library = NativeLibrary.Load(Path.GetFullPath(path));
            configure = Marshal.GetDelegateForFunctionPointer<ConfigureCall>(NativeLibrary.GetExport(library, "readout_power_fixture_configure"));
            release = Marshal.GetDelegateForFunctionPointer<ReleaseCall>(NativeLibrary.GetExport(library, "readout_power_fixture_release"));
            count = Marshal.GetDelegateForFunctionPointer<CounterCall>(NativeLibrary.GetExport(library, "readout_power_fixture_counter"));
            NativeLibrary.SetDllImportResolver(typeof(WindowsDeviceAccess).Assembly, (name, _, _) =>
                name.Equals("kernel32.dll", StringComparison.OrdinalIgnoreCase) ||
                (redirectCapabilities && name.Equals("powrprof.dll", StringComparison.OrdinalIgnoreCase)) ? library : 0);
            // Imported function pointers can remain cached. This owned child retains the DLL until process exit.
        }
        internal void Configure(uint status, uint capabilities, Behavior flags) => configure(status, capabilities, (uint)flags);
        internal uint Count(Counter which) => count((uint)which);
        internal void Release() => release();
        public void Dispose() => Release();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void ConfigureCall(uint status, uint capabilities, uint flags);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void ReleaseCall();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate uint CounterCall(uint which);
    }

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate uint NativeValue();
    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
    private static void Check(bool condition, string message) {if (!condition) throw new Exception(message);}
}
