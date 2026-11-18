using System.Diagnostics;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;
using DeviceReadout;
using DeviceReadout.Windows;

internal static partial class WindowsNetworkTests
{
    private static readonly string[] NotificationScenarios = [
        "native-events", "late-callbacks", "unsupported", "partial-support", "denied-registration",
        "failed-output", "null-handle", "rollback-cleanup-recovery", "persistent-cleanup-failure",
        "invalid-callback", "held-registration", "held-unregister", "unregister-recovery", "unregister-persistent"
    ];
    private static IEnumerable<(string Name, Func<Task> Run)> NotificationNativeCases()
        => NotificationScenarios.Select(name => ($"Windows network native notifications: {name}", (Func<Task>)(() => RunNotificationNativeParent(name))));

    private static async Task RunNotificationNativeParent(string scenario)
    {
        var start = new ProcessStartInfo(Environment.ProcessPath!) {
            UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true
        };
        if (string.Equals(Path.GetFileNameWithoutExtension(Environment.ProcessPath), "dotnet", StringComparison.OrdinalIgnoreCase))
            start.ArgumentList.Add(Assembly.GetExecutingAssembly().Location);
        foreach (var argument in new[] {"--network-notification-child", NetworkProbePath("device_readout_network_fixture.dll"), scenario}) start.ArgumentList.Add(argument);
        using var child = Process.Start(start) ?? throw new Exception("Could not start the owned notification test child.");
        var output = child.StandardOutput.ReadToEndAsync();var error = child.StandardError.ReadToEndAsync();
        try {
            await child.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(20));
            var stdout = await output;var stderr = await error;
            Check(child.ExitCode == 0, $"Native notification {scenario} failed: {stdout} {stderr}");
            Check(stdout.Contains($"\"scenario\":\"{scenario}\""), "Notification child reports its scenario.");
            Console.WriteLine(stdout.Trim());
        } finally {if (!child.HasExited) {child.Kill(entireProcessTree: true);await child.WaitForExitAsync();}}
    }

    internal static async Task RunNotificationNativeChild(string path, string scenario)
    {
        Check(NotificationScenarios.Contains(scenario), "Known native notification scenario.");
        using var fixture = new NativeNotificationFixture(path);
        var failures = scenario is "rollback-cleanup-recovery" or "persistent-cleanup-failure";
        var native = new NotificationNativeApi(fixture) {FailRollback = failures, RecoverAfterUnregisterFailure = scenario == "unregister-recovery"};
        var platform = new NotificationPlatform(new WindowsNetworkPlatform(native));
        using var access = new DeviceAccess(new WindowsCollector(networkPlatform: platform, routePlatform: new RouteFixture {Data = RouteTable()}));
        IAsyncEnumerator<NetworkInterfaceSnapshot>? stream = null;
        try {
            if (scenario == "held-registration") {
                fixture.Configure(30);
                var pending = access.WithReadTimeout(TimeSpan.FromMilliseconds(250)).NetworkInterfaces.List();
                await TestCompletion.Until(() => fixture.Counter(1) == 1, "Native registration reached its hold");
                var held = await NotificationHeartbeat(fixture);
                await Error(ErrorCode.ReadTimeout, () => pending.WaitAsync(TimeSpan.FromSeconds(2)));
                access.Dispose();
                Check(fixture.Counter(1) == 1 && !platform.Stopped.Task.IsCompleted, "Public timeout and disposal precede native registration return.");
                fixture.Release();await platform.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(3));
                Check(fixture.Counter(4) == 0 && fixture.Counter(5) == 3 && fixture.Counter(6) == 3, "Late registration handles are all released on the worker.");
                Report(held.Progress, held.Worker, held.Caller);return;
            }
            fixture.Configure(scenario switch {
                "unsupported" => 40, "partial-support" => 41, "denied-registration" => 42,
                "failed-output" or "rollback-cleanup-recovery" or "persistent-cleanup-failure" => 43,
                "null-handle" => 44, _ => 0
            });
            if (scenario is "denied-registration" or "failed-output" or "null-handle" || failures) {
                await Error(scenario == "denied-registration" ? ErrorCode.PermissionDenied : ErrorCode.ReadFailed, () => access.NetworkInterfaces.List());
                var acquired = scenario == "denied-registration" ? 1u : scenario == "null-handle" ? 2u : 3u;
                Check(fixture.Counter(5) == acquired && fixture.Counter(6) == acquired, "Rollback attempts every native handle, including failure output.");
                Check(fixture.Counter(4) == (failures ? acquired : 0), "Only failed cleanup retains a native registration.");
                if (failures) {
                    await Emit(0, 0, 1, false);
                    await Error(ErrorCode.ReadFailed, () => access.NetworkInterfaces.List());
                    Check(fixture.Counter(5) == 3 && fixture.Counter(6) == 3, "A failed source cannot accumulate registrations or retry cleanup in a loop.");
                    if (scenario == "rollback-cleanup-recovery") fixture.Configure(0);
                }
                access.Dispose();await platform.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(3));
                Check(fixture.Counter(6) == (failures ? 6u : acquired), "Final owner cleanup retries only retained handles once.");
                Check(fixture.Counter(4) == (scenario == "persistent-cleanup-failure" ? 3u : 0), "Native cleanup result is reported honestly.");
                if (scenario == "persistent-cleanup-failure") await Emit(0, 0, 1, false);
                Report();return;
            }
            var target = (await access.NetworkInterfaces.List()).First();
            var registrations = scenario == "unsupported" ? 0u : scenario == "partial-support" ? 2u : 3u;
            Check(fixture.Counter(4) == registrations && fixture.Counter(5) == registrations, "Native source availability.");
            var interval = scenario is "unsupported" or "partial-support" ? TimeSpan.FromMilliseconds(30) : TimeSpan.FromHours(1);
            stream = access.WithPollInterval(interval).Watch(target).GetAsyncEnumerator();
            Check(await stream.MoveNextAsync(), "Initial native snapshot.");
            var initialName = stream.Current.Name;
            if (scenario is "unregister-recovery" or "unregister-persistent") {
                fixture.Configure(32);access.Dispose();
                await platform.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(3));
                var expectedCalls = scenario == "unregister-recovery" ? 4 : 6;
                Check(native.UnregisterCalls == expectedCalls && fixture.Counter(6) == expectedCalls, "Final cleanup retries only failed handles without canceling released siblings twice.");
                Check(fixture.Counter(4) == (scenario == "unregister-recovery" ? 0u : 3u), "Persistent OS refusal cannot be reported as successful resource release.");
                await Emit(0, 0, 1, scenario == "unregister-recovery");
                await Error(ErrorCode.EntityRemoved, () => access.Get(target));
                Report();return;
            }
            if (scenario == "held-unregister") {
                fixture.Configure(31);access.Dispose();
                await TestCompletion.Until(() => fixture.Counter(1) == 1, "Native unregister reached its hold");
                var held = await NotificationHeartbeat(fixture);
                await stream.DisposeAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(2));stream = null;
                await Error(ErrorCode.EntityRemoved, () => access.Get(target));
                Check(fixture.Counter(1) == 1 && !platform.Stopped.Task.IsCompleted, "Caller disposal does not join native unregister.");
                await Emit(0, 0, 1, false);
                fixture.Release();await platform.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(3));
                Check(fixture.Counter(4) == 0 && fixture.Counter(6) == 3, "All held native registrations eventually release.");
                Report(held.Progress, held.Worker, held.Caller);return;
            }
            if (scenario == "invalid-callback") {
                await Emit(0, 4, 1, false);
                await Error(ErrorCode.ReadFailed, () => stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(2)));
            } else if (scenario is "unsupported" or "partial-support") {
                Check(await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(2)) && stream.Current.Name == initialName, "Unsupported notifications retain equal polling snapshots.");
            } else if (scenario == "native-events") {
                await using var second = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(target).GetAsyncEnumerator();
                Check(await second.MoveNextAsync() && fixture.Counter(5) == 3, "Two watches share the context's three registrations.");
                foreach (var kind in new uint[] {0, 1, 2}) {
                    await Emit(kind, 0, 1, false);
                    Check(await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(2)) && stream.Current.Name == initialName, "C-thread callback yields a fresh snapshot before polling.");
                    Check(await second.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(2)), "Second watch receives the same native event.");
                }
            }
            await stream.DisposeAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(2));stream = null;
            Check(fixture.Counter(6) == 0, "Context retains its existing observation lifetime after watches end.");
            access.Dispose();await platform.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(3));
            Check(fixture.Counter(4) == 0 && fixture.Counter(6) == registrations, "Context closure releases each native source exactly once.");
            if (scenario == "late-callbacks") {
                foreach (var kind in new uint[] {0, 1, 2}) await Emit(kind, 0, 1, true);
                Check(fixture.Counter(7) == 3, "Retired callback tokens safely ignore late C-thread invocations.");
            }
            Report();
        } finally {
            fixture.Release();access.Dispose();
            if (stream is not null) await stream.DisposeAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(2));
            await platform.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(3));
            await TestCompletion.Until(() => fixture.Counter(8) == 0, "Owned C callback threads finished");
        }
        async Task Emit(uint kind, uint type, uint valid, bool late) {
            fixture.Emit(kind, type, valid, late);
            await TestCompletion.Until(() => fixture.Counter(8) == 0, "Native callback returned without waiting for unregister");
        }
        void Report(int? progress = null, uint? worker = null, uint? caller = null) => Console.WriteLine("NETWORK_NOTIFICATION_CHILD " + JsonSerializer.Serialize(new {
            scenario, passed = true, activeRegistrations = fixture.Counter(4), registrations = fixture.Counter(5),
            cancellations = fixture.Counter(6), callbacks = fixture.Counter(7), progress, worker, caller,
            completedBeforeNativeReturn = progress.HasValue
        }));
    }

    private static async Task<(int Progress, uint Worker, uint Caller)> NotificationHeartbeat(NativeNotificationFixture fixture)
    {
        var ticks = 0;using var heartbeat = new Timer(_ => Interlocked.Increment(ref ticks), null, 0, 5);
        await Task.Delay(50);var progress = Volatile.Read(ref ticks);
        var worker = fixture.Counter(2);var caller = fixture.Counter(3);
        Check(progress >= 2 && worker != caller && fixture.Counter(1) == 1, "Caller timers run while a different native thread remains held.");
        return (progress, worker, caller);
    }

    private sealed class NotificationPlatform(WindowsNetworkPlatform inner) : IWindowsNetworkPlatform
    {
        internal readonly TaskCompletionSource Stopped = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public System.Net.NetworkInformation.NetworkInterface[] Enumerate(CancellationToken token) => inner.Enumerate(token);
        public NetworkInterfaceSnapshot? Properties(string id, CancellationToken token) => inner.Properties(id, token);
        public IDisposable Observe(Action changed, Action<Exception> fail) => inner.Observe(changed, fail);
        public void Dispose() {try {inner.Dispose();} finally {Stopped.TrySetResult();}}
    }
    private sealed class NotificationNativeApi(NativeNotificationFixture fixture) : IWindowsNetworkNotifications
    {
        private readonly WindowsNetworkNotifications native = new();
        internal bool FailRollback;
        internal bool RecoverAfterUnregisterFailure;
        internal int UnregisterCalls;
        public uint Register(WindowsNetworkChangeKind kind, WindowsNetworkChangeCallback callback, nint context, out nint handle)
        {
            var result = native.Register(kind, callback, context, out handle);
            if (FailRollback && result != 0 && handle != 0) fixture.Configure(32);
            return result;
        }
        public uint Unregister(nint handle)
        {
            UnregisterCalls++;var result = native.Unregister(handle);
            if (RecoverAfterUnregisterFailure && result != 0) fixture.Configure(0);
            return result;
        }
    }
    private sealed class NativeNotificationFixture : IDisposable
    {
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void ConfigureCall(uint mode);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void ReleaseCall();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate uint CounterCall(uint field);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate uint EmitCall(uint kind, uint type, uint valid, uint late, uint burst, uint value);
        private readonly ConfigureCall configure;private readonly ReleaseCall release;private readonly CounterCall counter;private readonly EmitCall emit;
        internal NativeNotificationFixture(string path)
        {
            var library = NativeLibrary.Load(Path.GetFullPath(path));
            T Function<T>(string name) where T : Delegate => Marshal.GetDelegateForFunctionPointer<T>(NativeLibrary.GetExport(library, name));
            configure = Function<ConfigureCall>("readout_network_configure");release = Function<ReleaseCall>("readout_network_release");
            counter = Function<CounterCall>("readout_network_counter");emit = Function<EmitCall>("readout_network_emit");
            NativeLibrary.SetDllImportResolver(typeof(WindowsDeviceAccess).Assembly, (name, _, _) => name.Equals("iphlpapi.dll", StringComparison.OrdinalIgnoreCase) ? library : 0);
            // Cached P/Invoke and callback pointers keep this owned child's fixture loaded until process exit.
        }
        internal void Configure(uint mode) => configure(mode);
        internal void Release() => release();
        internal uint Counter(uint field) => counter(field);
        internal void Emit(uint kind, uint type, uint valid, bool late) => Check(emit(kind, type, valid, late ? 1u : 0u, 1, 0) == 0, "Owned native callback thread starts.");
        public void Dispose() => release();
    }
}
