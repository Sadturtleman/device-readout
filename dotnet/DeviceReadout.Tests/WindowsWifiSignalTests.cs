using System.Runtime.InteropServices;
using DeviceReadout;
using DeviceReadout.Windows;

internal static partial class WindowsConnectivityTests
{
    private static async Task WifiRssi()
    {
        var runtime = new ConnectivityFixture();runtime.EnableWifi();
        var first = runtime.AddWifi("First");var second = runtime.AddWifi("Second");
        var wlan = new WlanFixture();wlan.Signals[first.AdapterId] = -67;wlan.Signals[second.AdapterId] = -110;
        var caller = Environment.CurrentManagedThreadId;
        using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime, wlanApi: wlan));
        Check(wlan.Opens == 0, "context construction performs no WLAN work");
        var targets = await access.List(Entities.WifiConnection);_ = await access.Current(Entities.WifiConnection);
        Check(wlan.Opens == 0, "discovery/current do not collect per-connection signal strength");
        var snapshot = await access.Get(targets[0]);
        Check(snapshot is {Ssid: "First", Security: WifiSecurity.Psk, RssiDbm: -67}, "selected signed native RSSI joins the readable profile fields");
        Check((await access.Get(targets[1])).RssiDbm == -110, "other adapter is queried explicitly without clamping its value");
        wlan.Signals[first.AdapterId] = 0;
        Check((await access.Get(targets[0])).RssiDbm == 0, "successful native zero is retained");
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        await using (var stream = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(targets[0], deadline.Token).GetAsyncEnumerator()) {
            Check(await stream.MoveNextAsync() && stream.Current.RssiDbm == 0, "initial RSSI snapshot");
            wlan.Signals[first.AdapterId] = -73;runtime.Fire();
            Check(await stream.MoveNextAsync() && stream.Current.RssiDbm == -73, "native notification reads a fresh selected signal");
            runtime.Fire();Check(await stream.MoveNextAsync() && stream.Current.RssiDbm == -73, "equal native signal observations are retained");
        }
        await using (var stream = access.WithPollInterval(TimeSpan.FromMilliseconds(25)).Watch(targets[1], deadline.Token).GetAsyncEnumerator()) {
            Check(await stream.MoveNextAsync() && await stream.MoveNextAsync() && stream.Current.RssiDbm == -110, "signal polls remain active alongside native events");
        }
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(wlan.Opens == wlan.Closes && wlan.Queries == wlan.Frees && wlan.LiveHandles == 0 && wlan.LiveBuffers == 0,
            "each WLAN session and output buffer is released");
        Check(wlan.Threads.Distinct().Count() == 1 && !wlan.Threads.Contains(caller)
            && wlan.Threads.Distinct().Single() == runtime.Threads.Distinct().Single(), "WinRT and WLAN operations share the collection worker");
    }

    private static async Task WifiRssiFailures()
    {
        var runtime = new ConnectivityFixture();runtime.EnableWifi();var profile = runtime.AddWifi("Selected");
        var wlan = new WlanFixture();wlan.Signals[profile.AdapterId] = -64;
        using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime, wlanApi: wlan));
        var target = (await access.List(Entities.WifiConnection)).Single();
        foreach (var fault in new Action[] {
            () => wlan.OpenResult = 5, () => wlan.OpenResult = 50, () => wlan.OpenResult = 1062,
            () => wlan.NullClient = true, () => wlan.Version = 1,
            () => wlan.QueryResult = 5, () => wlan.QueryResult = 50, () => wlan.QueryResult = 31,
            () => wlan.NullData = true, () => wlan.DataSize = 0, () => wlan.DataSize = 3,
            () => wlan.DataSize = 8, () => wlan.DataSize = uint.MaxValue, () => wlan.CloseResult = 6
        }) {
            fault();var value = await access.Get(target);
            Check(value is {Ssid: "Selected", Security: WifiSecurity.Psk, RssiDbm: null}, "WLAN failure remains local to signal strength");
            Check(wlan.LiveHandles == 0 && wlan.LiveBuffers == 0, "failed or malformed native output is released immediately");
            wlan.OpenResult = wlan.QueryResult = wlan.CloseResult = 0;wlan.NullClient = wlan.NullData = false;wlan.Version = 2;wlan.DataSize = 4;
        }
        profile.SsidResult = profile.AuthResult = unchecked((int)0x80004005);
        Check((await access.Get(target)) is {Ssid: null, Security: null, RssiDbm: -64}, "RSSI can succeed independently of both WinRT fields");
        wlan.QueryResult = 5;
        await Error(ErrorCode.PermissionDenied, () => access.Get(target));
        wlan.QueryResult = 31;
        await Error(ErrorCode.ReadFailed, () => access.Get(target));
        profile.SsidResult = profile.AuthResult = 0;wlan.QueryResult = 0;
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        await using (var stream = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(target, deadline.Token).GetAsyncEnumerator()) {
            Check(await stream.MoveNextAsync() && stream.Current.RssiDbm == -64, "initial signal before partial failure");
            wlan.QueryResult = 5;runtime.Fire();
            Check(await stream.MoveNextAsync() && stream.Current is {Ssid: "Selected", RssiDbm: null}, "partial failure does not retain a stale signal or terminate readable profile state");
            wlan.QueryResult = 0;wlan.Signals[profile.AdapterId] = -82;runtime.Fire();
            Check(await stream.MoveNextAsync() && stream.Current.RssiDbm == -82, "next requested observation reads the recovered signal");
        }
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(wlan.LiveHandles == 0 && wlan.LiveBuffers == 0 && runtime.References.Values.All(count => count == 0), "native and WinRT resources balance after all field failures");
    }

    private static async Task WifiRssiRemoval()
    {
        var runtime = new ConnectivityFixture();runtime.EnableWifi();var profile = runtime.AddWifi("Selected");
        var wlan = new WlanFixture();wlan.Signals[profile.AdapterId] = -61;
        using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime, wlanApi: wlan));
        var first = (await access.List(Entities.WifiConnection)).Single();
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        await using (var stream = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(first, deadline.Token).GetAsyncEnumerator()) {
            Check(await stream.MoveNextAsync(), "initial connected signal");
            wlan.QueryResult = 5023;wlan.CloseResult = 6;runtime.Fire();
            await Error(ErrorCode.EntityRemoved, async () => {await stream.MoveNextAsync();});
        }
        Check(runtime.Registrations == runtime.Removals, "native disconnect stops status observation even if client close reports failure");
        wlan.QueryResult = wlan.CloseResult = 0;
        var calls = wlan.Queries;await Error(ErrorCode.EntityRemoved, () => access.Get(first));
        Check(wlan.Queries == calls, "retired handle performs no more native signal reads");
        var second = (await access.List(Entities.WifiConnection)).Single();
        Check(!second.Equals(first) && (await access.Get(second)).RssiDbm == -61, "reappearance with the same native identity requires a fresh target");
        wlan.QueryResult = 1168;await Error(ErrorCode.EntityRemoved, () => access.Get(second));
        wlan.QueryResult = 0;var third = (await access.List(Entities.WifiConnection)).Single();
        await Error(ErrorCode.EntityRemoved, () => access.Get(second));
        Check(!third.Equals(second), "native interface-not-found also retires its generation");
        wlan.OnQuery = () => profile.NetworkId = Guid.NewGuid();
        await Error(ErrorCode.EntityRemoved, () => access.Get(third));
        wlan.OnQuery = null;
        var fourth = (await access.List(Entities.WifiConnection)).Single();
        Check(!fourth.Equals(third) && (await access.Get(fourth)).RssiDbm == -61, "replacement during signal collection discards the old snapshot and supports a fresh target");
        await Error(ErrorCode.EntityRemoved, () => access.Get(third));
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(wlan.Opens == wlan.Closes && wlan.Queries == wlan.Frees && wlan.LiveHandles == 0 && wlan.LiveBuffers == 0
            && runtime.References.Values.All(count => count == 0), "removal and racing snapshots release every native resource");
    }

    private static async Task WifiRssiDeadlines()
    {
        foreach (var eventRead in new[] {false, true}) foreach (var stage in new[] {0, 1, 2}) {
            var runtime = new ConnectivityFixture();runtime.EnableWifi();var profile = runtime.AddWifi("Held");
            var wlan = new WlanFixture();wlan.Signals[profile.AdapterId] = -70;
            var caller = Environment.CurrentManagedThreadId;
            using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime, wlanApi: wlan));
            var target = (await access.List(Entities.WifiConnection)).Single();
            var configured = access.WithReadTimeout(TimeSpan.FromMilliseconds(250)).WithPollInterval(TimeSpan.FromHours(1));
            using var proceed = new ManualResetEventSlim(false);
            var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            Action hold = () => {entered.TrySetResult();if (!proceed.Wait(TimeSpan.FromSeconds(3))) throw new Exception("Held WLAN operation was not released by its test.");};
            IAsyncEnumerator<WifiConnectionSnapshot>? stream = null;var previousQueries = 0;var previousInventories = 0;
            try {
                if (eventRead) {stream = configured.Watch(target).GetAsyncEnumerator();Check(await stream.MoveNextAsync(), "initial Wi-Fi before blocked WLAN operation");}
                previousQueries = wlan.Queries;previousInventories = runtime.InventoryReads;
                if (stage == 0) wlan.OnOpen = hold;else if (stage == 1) wlan.OnQuery = hold;else wlan.OnClose = hold;
                if (eventRead) runtime.Fire();
                Task pending = eventRead ? stream!.MoveNextAsync().AsTask() : configured.Get(target);
                await entered.Task.WaitAsync(TimeSpan.FromSeconds(2));
                await Task.Delay(10);Check(!pending.IsCompleted, "host execution continues before native WLAN completion");
                await Error(ErrorCode.ReadTimeout, () => pending.WaitAsync(TimeSpan.FromSeconds(2)));
                access.Dispose();Check(!runtime.Stopped.Task.IsCompleted, "context disposal does not join held native open/query/close work");
            } finally {
                proceed.Set();access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
                if (stream is not null) await stream.DisposeAsync();
            }
            Check(wlan.Queries == previousQueries + (stage == 0 ? 0 : 1), "late opening performs no query and other held operations are not retried");
            Check(runtime.InventoryReads == previousInventories + 1, "timed-out native operations perform no follow-up profile inventory");
            Check(wlan.Opens == wlan.Closes && wlan.Queries == wlan.Frees && wlan.LiveHandles == 0 && wlan.LiveBuffers == 0
                && runtime.Registrations == runtime.Removals && runtime.References.Values.All(count => count == 0), "late native handles, buffers, profiles and registrations balance");
            Check(wlan.Threads.Distinct().Count() == 1 && !wlan.Threads.Contains(caller), "late native completion and cleanup stay on the collection worker");
        }
    }

    private static async Task ActualWlanRemoval()
    {
        // Simulate a stale WinRT profile while querying the real WLAN service for that absent adapter.
        var runtime = new ConnectivityFixture();runtime.EnableWifi();
        var profile = runtime.AddWifi("Synthetic stale profile");profile.AdapterId = new("11111111-2222-3333-4444-555555555555");
        var wlan = new NativeWlanProbe();var caller = Environment.CurrentManagedThreadId;
        using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime, wlanApi: wlan));
        var target = (await access.List(Entities.WifiConnection)).Single();
        Check(wlan.Opens == 0, "native WLAN remains unopened until a selected read");
        await Error(ErrorCode.EntityRemoved, () => access.Get(target));
        Check(wlan.OpenResult == 0 && wlan.Version == 2 && wlan.QueryResult == 1168 && wlan.DataSize == 0,
            "real native missing-interface result agrees with the independent C probe");
        Check(wlan.Opens == 1 && wlan.Queries == 1 && wlan.Closes == 1 && wlan.CloseResult == 0, "actual native client is closed after query failure");
        await Error(ErrorCode.EntityRemoved, () => access.Get(target));
        Check(wlan.Queries == 1 && !(await access.List(Entities.WifiConnection)).Single().Equals(target), "native removal permanently retires the stale target");
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(wlan.Threads.Distinct().Count() == 1 && !wlan.Threads.Contains(caller)
            && wlan.Threads.Distinct().Single() == runtime.Threads.Distinct().Single(), "actual WLAN open/query/close share the collection worker");
        Console.WriteLine("Native Windows WLAN: client version 2, absent-interface RSSI result 1168, zero output bytes and successful close; actual signal values remain unverified.");
    }

    private sealed class NativeWlanProbe : IWindowsWlanApi
    {
        private readonly WindowsWlanApi native = new();
        internal readonly List<int> Threads = [];
        internal int Opens, Queries, Closes;
        internal uint OpenResult, Version, QueryResult, DataSize, CloseResult;
        private void Record() => Threads.Add(Environment.CurrentManagedThreadId);
        public uint Open(out uint negotiatedVersion, out nint client)
        {
            Record();Opens++;OpenResult = native.Open(out negotiatedVersion, out client);Version = negotiatedVersion;return OpenResult;
        }
        public uint Query(nint client, in Guid adapter, WindowsWlanQuery kind, out uint size, out nint data)
        {
            Record();Queries++;QueryResult = native.Query(client, in adapter, kind, out size, out data);DataSize = size;return QueryResult;
        }
        public void Free(nint data) {Record();native.Free(data);}
        public uint Close(nint client) {Record();Closes++;CloseResult = native.Close(client);return CloseResult;}
    }

    private sealed class WlanFixture : IWindowsWlanApi
    {
        internal readonly Dictionary<Guid, int> Signals = [];
        internal readonly List<int> Threads = [];
        private readonly HashSet<nint> handles = [], buffers = [];
        internal int Opens, Closes, Queries, Frees;
        internal uint OpenResult = 0, QueryResult = 0, CloseResult = 0, Version = 2, DataSize = 4;
        internal bool NullClient = false, NullData = false;
        internal Action? OnOpen, OnQuery, OnClose;
        internal int LiveHandles => handles.Count;
        internal int LiveBuffers => buffers.Count;
        private void Record() => Threads.Add(Environment.CurrentManagedThreadId);
        public uint Open(out uint negotiatedVersion, out nint client)
        {
            Record();Opens++;negotiatedVersion = Version;client = NullClient ? 0 : Marshal.AllocHGlobal(1);
            if (client != 0) handles.Add(client);OnOpen?.Invoke();return OpenResult;
        }
        public uint Query(nint client, in Guid adapter, WindowsWlanQuery kind, out uint size, out nint data)
        {
            Record();Queries++;
            Check(handles.Contains(client) && (uint)kind == 0x10000102, "only the RSSI query opcode reaches WLAN");
            Check(Signals.ContainsKey(adapter), "query targets the selected WinRT adapter ID");
            size = DataSize;data = NullData ? 0 : Marshal.AllocHGlobal(4);
            if (data != 0) {Marshal.WriteInt32(data, Signals[adapter]);buffers.Add(data);}
            OnQuery?.Invoke();return QueryResult;
        }
        public void Free(nint data) {Record();Frees++;Check(buffers.Remove(data), "native output freed once");Marshal.FreeHGlobal(data);}
        public uint Close(nint client) {Record();Closes++;OnClose?.Invoke();Check(handles.Remove(client), "native client closed once");Marshal.FreeHGlobal(client);return CloseResult;}
    }
}
