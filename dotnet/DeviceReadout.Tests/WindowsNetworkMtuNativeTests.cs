using System.Diagnostics;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;
using DeviceReadout;
using DeviceReadout.Windows;

internal static partial class WindowsNetworkTests
{
    private static readonly string[] NativeMtuScenarios = [
        "values", "unsigned", "zero", "growth", "unrelated-invalid-address", "denied", "cycle", "absent",
        "oversize", "invalid-size", "invalid-identity", "short-node", "non-growing", "repeated-growth",
        "fallback", "watch-recovery", "get-timeout", "watch-initial-timeout", "watch-poll-timeout",
        "get-cancel", "watch-cancel", "context-dispose", "watch-dispose", "scoped-dns", "dns-cycle", "dns-family", "empty-dns", "dns-native-failure"
    ];
    private static IEnumerable<(string Name, Func<Task> Run)> MtuNativeCases()
        => NativeMtuScenarios.Select(name => ($"Windows network native MTU: {name}", (Func<Task>)(() => RunMtuNativeParent(name))));

    private static string NetworkProbePath(string name)
    {
        var root = new DirectoryInfo(AppContext.BaseDirectory);
        while (root is not null && !File.Exists(Path.Combine(root.FullName, "tools/windows-memory-probe/CMakeLists.txt"))) root = root.Parent;
        if (root is null) throw new Exception("Could not locate the native network test fixtures.");
        return Path.Combine(root.FullName, ".tools/windows-memory-probe/Release", name);
    }

    private static async Task RunMtuNativeParent(string scenario)
    {
        var start = new ProcessStartInfo(Environment.ProcessPath!) {
            UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true
        };
        if (string.Equals(Path.GetFileNameWithoutExtension(Environment.ProcessPath), "dotnet", StringComparison.OrdinalIgnoreCase))
            start.ArgumentList.Add(Assembly.GetExecutingAssembly().Location);
        foreach (var argument in new[] {"--network-mtu-child", NetworkProbePath("device_readout_network_fixture.dll"), scenario}) start.ArgumentList.Add(argument);
        using var child = Process.Start(start) ?? throw new Exception("Could not start the owned network test child.");
        var output = child.StandardOutput.ReadToEndAsync();var error = child.StandardError.ReadToEndAsync();
        try {
            await child.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(15));
            var stdout = await output;var stderr = await error;
            Check(child.ExitCode == 0, $"Native MTU {scenario} failed: {stdout} {stderr}");
            Check(stdout.Contains($"\"scenario\":\"{scenario}\""), "Child reports its completed scenario.");
            Console.WriteLine(stdout.Trim());
        } finally {if (!child.HasExited) {child.Kill(entireProcessTree: true);await child.WaitForExitAsync();}}
    }

    internal static async Task RunMtuNativeChild(string path, string scenario)
    {
        Check(NativeMtuScenarios.Contains(scenario), "Known native MTU scenario.");
        using var native = new NativeMtuFixture(path);
        var adapter = new AdapterFixture {NativeId = "network-fixture", Ipv4 = false, Ipv6 = false};
        var platform = new NetworkFixture {Adapters = [adapter], NativeMtu = new WindowsNetworkPlatform(propertiesPlatform: native)};
        using var access = new DeviceAccess(new WindowsCollector(networkPlatform: platform));
        var target = (await access.NetworkInterfaces.List()).Single();
        try {
            if (scenario.Contains("timeout") || scenario.EndsWith("cancel") || scenario.EndsWith("dispose")) {
                await HeldMtu(scenario, access, target, native);return;
            }
            if (scenario == "watch-recovery") {
                await using var stream = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(target).GetAsyncEnumerator();
                Check(await stream.MoveNextAsync() && stream.Current.MtuBytes == 1500, "Initial native MTU.");
                foreach (var mode in new uint[] {8, 0, 0}) {
                    native.Configure(mode);platform.Signal();
                    Check(await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(2)), "Same stream survives optional failure and equal-value recovery.");
                    Check(stream.Current.MtuBytes == (mode == 8 ? null : 1500UL) && stream.Current.Name == "Fixture Ethernet", "Only MTU becomes unavailable.");
                }
            } else {
                native.Configure(scenario switch {
                    "unsigned" => 14, "growth" => 12, "unrelated-invalid-address" => 3,
                    "denied" or "fallback" or "dns-native-failure" => 8, "cycle" => 9, "absent" => 10, "oversize" => 11, "invalid-size" => 13,
                    "scoped-dns" => 18, "dns-cycle" => 19, "dns-family" => 22, "empty-dns" => 23, _ => 0
                });
                native.Mutation = scenario;
                if (scenario == "fallback") {adapter.Ipv4 = true;adapter.Properties = new IpPropertiesFixture {Four = new Ipv4PropertiesFixture(-1)};}
                if (scenario == "dns-native-failure") adapter.Properties = new IpPropertiesFixture {Dns = new IpListFixture(System.Net.IPAddress.Parse("fec0::1"))};
                var snapshot = await access.Get(target);
                ulong? expected = scenario switch {
                    "values" or "growth" or "unrelated-invalid-address" or "scoped-dns" or "dns-cycle" or "dns-family" or "empty-dns" => 1500,
                    "unsigned" or "fallback" => uint.MaxValue, "zero" => 0, _ => null
                };
                Check(snapshot.MtuBytes == expected && snapshot.Name == "Fixture Ethernet" && snapshot.HardwareAddress == "00:11:22:33:44:55", "Native MTU value and independent fields.");
                if (scenario == "scoped-dns") Check(snapshot.DnsServers?.SequenceEqual(new[] {"fec0::1%7"}) == true, "Native site-local DNS retains its scope identifier.");
                if (scenario is "dns-cycle" or "dns-family" or "unrelated-invalid-address") Check(snapshot.DnsServers is null, "Malformed DNS is field-local.");
                if (scenario == "empty-dns") Check(snapshot.DnsServers?.Length == 0, "Known empty DNS is preserved.");
                if (scenario == "dns-native-failure") Check(snapshot.DnsServers is null, "A failed native DNS read cannot fall back to a scope-losing BCL address.");
                Check(native.Calls <= 3 && native.MaximumSize <= 8 * 1024 * 1024, "Native growth is bounded.");
                native.Mutation = "";native.Configure(0);
                Check((await access.Get(target)).MtuBytes == 1500, "Optional failure does not poison the context.");
            }
            Console.WriteLine("NETWORK_MTU_CHILD " + JsonSerializer.Serialize(new {scenario, passed = true, native.Calls, native.MaximumSize}));
        } finally {
            native.Release();access.Dispose();
            await platform.Disposed.Task.WaitAsync(TimeSpan.FromSeconds(2));
        }
    }

    private static async Task HeldMtu(string scenario, DeviceAccess access, Entity<NetworkInterfaceSnapshot> target, NativeMtuFixture native)
    {
        using var caller = new CancellationTokenSource();
        var ticks = 0;using var timer = new Timer(_ => Interlocked.Increment(ref ticks), null, 0, 5);
        var configured = access.WithReadTimeout(TimeSpan.FromMilliseconds(250)).WithPollInterval(TimeSpan.FromMilliseconds(40));
        var isWatch = scenario.StartsWith("watch-");
        var initial = isWatch && scenario != "watch-initial-timeout";
        IAsyncEnumerator<NetworkInterfaceSnapshot>? stream = null;Task? pending = null;
        var progress = 0;uint worker = 0, host = 0;
        try {
            native.Configure(initial ? 0u : 20u);
            if (isWatch) {
                stream = configured.Watch(target, caller.Token).GetAsyncEnumerator();
                if (initial) {Check(await stream.MoveNextAsync(), "Initial snapshot before the held poll.");native.Configure(20);}
                if (scenario != "watch-dispose") pending = Drain();
            } else pending = configured.Get(target, caller.Token);
            await TestCompletion.Until(() => native.Counter(1) == 1, "MTU native query reached its hold");
            var before = Volatile.Read(ref ticks);await Task.Delay(40);progress = Volatile.Read(ref ticks) - before;
            worker = native.Counter(2);host = native.Counter(3);
            Check(progress >= 2 && worker != host && native.Counter(1) == 1, "Caller progresses independently of the held native worker.");
            if (scenario.EndsWith("timeout")) await Error(ErrorCode.ReadTimeout, () => pending!.WaitAsync(TimeSpan.FromSeconds(2)));
            else if (scenario == "watch-dispose") await stream!.DisposeAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(2));
            else {
                if (scenario == "context-dispose") access.Dispose();else caller.Cancel();
                try {await pending!.WaitAsync(TimeSpan.FromSeconds(2));throw new Exception("Expected cancellation.");}
                catch (OperationCanceledException) { }
            }
            Check(native.Counter(1) == 1, "Public completion precedes native return.");
        } finally {
            native.Release();
            if (pending is not null) try {await pending.WaitAsync(TimeSpan.FromSeconds(2));} catch (OperationCanceledException) { } catch (DeviceReadoutException) { }
            if (stream is not null) await stream.DisposeAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(2));
            await TestCompletion.Until(() => native.Counter(1) == 0, "Held native query returns after release");
        }
        if (scenario != "context-dispose") {
            native.Configure(0);Check((await access.Get(target)).MtuBytes == 1500, "Public context recovers after native return.");
        }
        Console.WriteLine("NETWORK_MTU_CHILD " + JsonSerializer.Serialize(new {scenario, passed = true, completedBeforeNativeReturn = true, progress, worker, host}));
        async Task Drain() {while (await stream!.MoveNextAsync()) { }throw new Exception("Expected watch termination with an error.");}
    }

    private sealed class NativeMtuFixture : IWindowsNetworkPropertiesPlatform, IDisposable
    {
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] private delegate uint ReadCall(uint family, uint flags, nint reserved, nint buffer, ref uint size);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void ConfigureCall(uint mode);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void ReleaseCall();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate uint CounterCall(uint field);
        private readonly nint library;
        private readonly ReadCall read;private readonly ConfigureCall configure;private readonly ReleaseCall release;private readonly CounterCall counter;
        internal string Mutation = "";
        internal uint Calls, MaximumSize;
        internal NativeMtuFixture(string path)
        {
            library = NativeLibrary.Load(Path.GetFullPath(path));
            T Function<T>(string name) where T : Delegate => Marshal.GetDelegateForFunctionPointer<T>(NativeLibrary.GetExport(library, name));
            read = Function<ReadCall>("GetAdaptersAddresses");configure = Function<ConfigureCall>("readout_network_configure");
            release = Function<ReleaseCall>("readout_network_release");counter = Function<CounterCall>("readout_network_counter");
        }
        public uint Read(nint buffer, ref uint size)
        {
            Calls++;MaximumSize = Math.Max(MaximumSize, size);
            if (Mutation == "non-growing") return 111;
            if (Mutation == "repeated-growth") {size++;return 111;}
            var result = read(0, 2 | 4 | 128 | 256, 0, buffer, ref size);
            if (result == 0) {
                if (Mutation == "zero") Marshal.WriteInt32(buffer, 96, 0);
                if (Mutation == "short-node") Marshal.WriteInt32(buffer, 0, 99);
                if (Mutation == "invalid-identity") Marshal.WriteInt64(buffer, 16, long.MaxValue);
            }
            return result;
        }
        internal void Configure(uint mode) => configure(mode);
        internal void Release() => release();
        internal uint Counter(uint field) => counter(field);
        public void Dispose() {release();NativeLibrary.Free(library);}
    }
}
