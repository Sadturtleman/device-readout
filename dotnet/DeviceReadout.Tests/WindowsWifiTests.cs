using System.Runtime.InteropServices;
using DeviceReadout;
using DeviceReadout.Windows;

internal static partial class WindowsConnectivityTests
{
    private static async Task WifiFields()
    {
        var runtime = new ConnectivityFixture();runtime.EnableWifi();
        var first = runtime.AddWifi("First");var second = runtime.AddWifi("Second");
        var idle = runtime.AddWifi("Saved");idle.Level = 0;
        var wired = runtime.AddWifi("Wired");wired.IsWifi = false;
        var caller = Environment.CurrentManagedThreadId;
        using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime, wlanApi: new WlanFixture {OpenResult = 50}));
        Check(runtime.Initializations == 0, "Wi-Fi context construction is inert");
        var targets = await access.List(Entities.WifiConnection);
        Check(targets.Length == 2, "list excludes remembered disconnected profiles and Ethernet");
        Check((await access.Current(Entities.WifiConnection))!.Equals(targets[0]), "current is the OS preferred Wi-Fi profile");
        var snapshot = await access.Get(targets[0]);
        Check(snapshot.Ssid == "First" && snapshot.Security == WifiSecurity.Psk, "connected SSID and selected authentication are read from the selected profile");
        Check(snapshot.Bssid is null && snapshot.RssiDbm is null && snapshot.FrequencyHz is null
            && snapshot.ReceiveLinkSpeedBps is null && snapshot.TransmitLinkSpeedBps is null, "unsupported quality fields are not invented from adapter capacity or signal bars");
        Check((await access.Get(targets[1])).Ssid == "Second", "multiple adapters retain distinct typed targets");
        first.Ssid = "";first.Auth = 0;first.Encryption = 0;
        Check((await access.Get(targets[0])) is {Ssid: "", Security: WifiSecurity.Open}, "successful empty SSID is preserved");
        foreach (var (auth, encryption, expected) in new (int, int, WifiSecurity?)[] {
            (2, 0, WifiSecurity.Open), (2, 2, WifiSecurity.Wep), (2, 3, WifiSecurity.Wep), (2, 4, WifiSecurity.Wep),
            (2, 1, null), (2, 6, null), (3, 2, WifiSecurity.Wep), (4, 6, WifiSecurity.Eap),
            (5, 5, WifiSecurity.Psk), (7, 6, WifiSecurity.Eap), (8, 6, WifiSecurity.Psk),
            (10, 11, WifiSecurity.EapWpa3Enterprise192Bit), (11, 10, WifiSecurity.Sae),
            (12, 6, WifiSecurity.Owe), (13, 10, WifiSecurity.EapWpa3Enterprise),
            (1, 0, null), (6, 5, null), (9, 9, null), (99, 6, null)
        }) {
            first.Auth = auth;first.Encryption = encryption;
            Check((await access.Get(targets[0])).Security == expected, $"native authentication {auth}/{encryption} retains its defined meaning");
        }
        runtime.Preferred = wired;
        Check(await access.Current(Entities.WifiConnection) is null, "preferred Ethernet does not select an arbitrary Wi-Fi connection");
        runtime.Preferred = null;
        Check(await access.Current(Entities.WifiConnection) is null, "no preferred path gives no current Wi-Fi target");
        Check((await access.Capabilities.Get(targets[0])).Readable == true, "discovered Wi-Fi is readable");
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.References.Values.All(count => count == 0) && runtime.Threads.Distinct().Count() == 1
            && !runtime.Threads.Contains(caller), "profile vectors, queried interfaces and runtime are released on the collector worker");
    }

    private static async Task WifiEvents()
    {
        var runtime = new ConnectivityFixture();runtime.EnableWifi();
        var first = runtime.AddWifi("First");runtime.AddWifi("Second");
        using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime, wlanApi: new WlanFixture {OpenResult = 50}));
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        var targets = await access.List(Entities.WifiConnection);
        var slow = access.WithPollInterval(TimeSpan.FromHours(1));
        await using var a = slow.Watch(targets[0], deadline.Token).GetAsyncEnumerator();
        await using var b = slow.Watch(targets[1], deadline.Token).GetAsyncEnumerator();
        Check(await a.MoveNextAsync() && await b.MoveNextAsync(), "both initial Wi-Fi snapshots");
        Check(runtime.Registrations == 2, "each Wi-Fi watch subscribes to native network changes");
        first.Auth = 11;runtime.Fire();
        Check(await a.MoveNextAsync() && a.Current.Security == WifiSecurity.Sae, "event refreshes selected connection before polling");
        Check(await b.MoveNextAsync() && b.Current.Ssid == "Second", "second selected connection retains its own snapshot");
        runtime.Fire();Check(await a.MoveNextAsync() && await b.MoveNextAsync(), "equal native events are retained");
        var lateHandler = runtime.RetainFirstHandler();
        first.Level = 0;runtime.Fire();
        await Error(ErrorCode.EntityRemoved, async () => {await a.MoveNextAsync();});
        Check(await b.MoveNextAsync() && b.Current.Ssid == "Second", "unrelated Wi-Fi stream survives disconnection");
        await a.DisposeAsync();
        await TestCompletion.Until(() => runtime.HandlerCount == 1, "removed Wi-Fi registration released");
        Check(runtime.Removals == 1 && runtime.HandlerCount == 1, "only removed connection unsubscribes");
        var reads = runtime.InventoryReads;ConnectivityFixture.Invoke(lateHandler);Marshal.Release(lateHandler);
        await Task.Delay(25);Check(runtime.InventoryReads == reads, "callback retained after removal does not enqueue native work");
        await Error(ErrorCode.EntityRemoved, () => access.Get(targets[0]));
        await Error(ErrorCode.EntityRemoved, () => access.Capabilities.Get(targets[0]));
        Check((await access.List(Entities.WifiConnection)).Length == 1, "disconnected connection disappears from discovery");
        first.Level = 3;
        var replacement = (await access.List(Entities.WifiConnection)).Single(target => !target.Equals(targets[1]));
        Check(!replacement.Equals(targets[0]), "reconnection creates a fresh typed handle");
        await Error(ErrorCode.EntityRemoved, () => access.Get(targets[0]));
        first.NetworkId = Guid.NewGuid();
        await Error(ErrorCode.EntityRemoved, () => access.Get(replacement));
        Check((await access.List(Entities.WifiConnection)).Length == 2, "different network on the same adapter replaces the old connection");
        await b.DisposeAsync();
        await TestCompletion.Until(() => runtime.HandlerCount == 0, "Wi-Fi registrations removed");
        Check(runtime.Registrations == runtime.Removals && runtime.HandlerCount == 0, "native event sources are balanced");
        await using (var polled = access.WithPollInterval(TimeSpan.FromMilliseconds(25)).Watch(targets[1], deadline.Token).GetAsyncEnumerator()) {
            Check(await polled.MoveNextAsync() && await polled.MoveNextAsync() && polled.Current.Ssid == "Second", "equal serial polls remain active with native events");
        }
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.References.Values.All(count => count == 0), "all profile and event references released after removal and polling");
    }

    private static async Task WifiFailures()
    {
        const int denied = unchecked((int)0x80070005), failed = unchecked((int)0x80004005);
        var runtime = new ConnectivityFixture();runtime.EnableWifi();var profile = runtime.AddWifi("Selected");
        using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime, wlanApi: new WlanFixture {OpenResult = 50}));
        var target = (await access.List(Entities.WifiConnection)).Single();
        profile.SsidResult = denied;
        Check((await access.Get(target)) is {Ssid: null, Security: WifiSecurity.Psk}, "failed SSID preserves independently readable authentication");
        profile.SsidResult = 0;profile.AuthResult = failed;
        Check((await access.Get(target)) is {Ssid: "Selected", Security: null}, "failed authentication preserves SSID");
        profile.SsidResult = denied;
        await Error(ErrorCode.PermissionDenied, () => access.Get(target));
        profile.SsidResult = failed;
        await Error(ErrorCode.ReadFailed, () => access.Get(target));
        profile.SsidResult = profile.AuthResult = 0;
        profile.DetailsResult = denied;profile.SecurityResult = failed;
        await Error(ErrorCode.PermissionDenied, () => access.Get(target));
        profile.DetailsResult = profile.SecurityResult = 0;
        profile.Auth = 2;profile.EncryptionResult = denied;
        Check((await access.Get(target)).Security is null, "open-system authentication without readable encryption cannot become Open");
        profile.Auth = 5;
        Check((await access.Get(target)).Security == WifiSecurity.Psk, "PSK does not require an unrelated cipher lookup");
        profile.EncryptionResult = 0;profile.NoDetails = profile.NoSecurity = true;
        Check((await access.Get(target)) is {Ssid: null, Security: null}, "successfully absent field sources preserve null");
        profile.NoDetails = profile.NoSecurity = false;
        foreach (var fault in new Action[] {
            () => runtime.InventoryResult = denied, () => runtime.SizeResult = failed, () => runtime.ItemResult = failed,
            () => profile.QueryResult = failed, () => profile.IsWifiResult = failed, () => profile.LevelResult = failed,
            () => profile.AdapterResult = failed, () => profile.NetworkResult = failed,
            () => profile.NoAdapter = true, () => profile.NoNetwork = true,
            () => profile.Level = 99, () => runtime.InvalidSize = 4097
        }) {
            fault();await Error(runtime.InventoryResult == denied ? ErrorCode.PermissionDenied : ErrorCode.ReadFailed, () => access.List(Entities.WifiConnection));
            runtime.InventoryResult = runtime.SizeResult = runtime.ItemResult = 0;runtime.InvalidSize = null;
            profile.QueryResult = profile.IsWifiResult = profile.LevelResult = profile.AdapterResult = profile.NetworkResult = 0;
            profile.NoAdapter = profile.NoNetwork = false;profile.Level = 3;
            Check((await access.List(Entities.WifiConnection)).Single().Equals(target), "failed enumeration preserves the existing target generation");
        }
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        await using (var stream = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(target, deadline.Token).GetAsyncEnumerator()) {
            Check(await stream.MoveNextAsync(), "initial value before whole inventory failure");
            runtime.InventoryResult = denied;runtime.Fire();
            await Error(ErrorCode.PermissionDenied, async () => {await stream.MoveNextAsync();});
        }
        await TestCompletion.Until(() => runtime.HandlerCount == 0, "failed Wi-Fi registration removed");
        Check(runtime.HandlerCount == 0 && runtime.Registrations == runtime.Removals, "failed event read stops its registration");
        runtime.InventoryResult = 0;
        Check((await access.Get(target)).Ssid == "Selected", "later explicit read can recover without cached data");
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.References.Values.All(count => count == 0), "all failed native calls release nonnull out-interfaces");
    }

    private static async Task WifiDeadlines()
    {
        foreach (var eventRead in new[] {false, true}) {
            var runtime = new ConnectivityFixture();runtime.EnableWifi();runtime.AddWifi("Held");
            var caller = Environment.CurrentManagedThreadId;
            using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime, wlanApi: new WlanFixture {OpenResult = 50}));
            var target = (await access.List(Entities.WifiConnection)).Single();
            var configured = access.WithReadTimeout(TimeSpan.FromMilliseconds(250)).WithPollInterval(TimeSpan.FromHours(1));
            IAsyncEnumerator<WifiConnectionSnapshot>? stream = null;var fieldsBefore = 0;
            try {
                if (eventRead) {stream = configured.Watch(target).GetAsyncEnumerator();Check(await stream.MoveNextAsync(), "initial Wi-Fi before blocking event");}
                fieldsBefore = runtime.WifiFieldReads;runtime.InventoryStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);runtime.ContinueInventory.Reset();
                if (eventRead) runtime.Fire();
                Task pending = eventRead ? stream!.MoveNextAsync().AsTask() : configured.Get(target);
                await runtime.InventoryStarted.Task.WaitAsync(TimeSpan.FromSeconds(2));
                await Task.Delay(10);Check(!pending.IsCompleted, "host continuation proceeds while native inventory is held");
                await Error(ErrorCode.ReadTimeout, () => pending.WaitAsync(TimeSpan.FromSeconds(2)));
                access.Dispose();Check(!runtime.Stopped.Task.IsCompleted, "context close does not join borrowed native work");
            } finally {
                runtime.ContinueInventory.Set();access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
                if (stream is not null) await stream.DisposeAsync();runtime.ContinueInventory.Dispose();
            }
            Check(runtime.WifiFieldReads == fieldsBefore && runtime.References.Values.All(count => count == 0), "late inventory result is released before further field reads");
            Check(runtime.Registrations == runtime.Removals && runtime.HandlerCount == 0 && runtime.Uninitializations == 1
                && runtime.Threads.Distinct().Count() == 1 && !runtime.Threads.Contains(caller), "deadline cleanup stays on the worker and balances subscriptions");
        }
    }

    private static async Task WifiObservers()
    {
        var runtime = new ConnectivityFixture();runtime.EnableWifi();runtime.AddWifi("Observed");
        using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime, wlanApi: new WlanFixture {OpenResult = 50}));
        var target = (await access.List(Entities.WifiConnection)).Single();var requests = 0;
        using var coordinator = access.Observers.OnPermissionRequest((_, _) => {Interlocked.Increment(ref requests);return Task.CompletedTask;});
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        Check(await access.Permissions.Check(target) is null, "SDK has no invented permission state before an app observation");
        _ = await access.Get(target);
        await using (var stream = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(target, deadline.Token).GetAsyncEnumerator()) {
            Check(await stream.MoveNextAsync(), "native initial snapshot");
            access.Observers.Permission(target, PermissionStatus.Denied);
            Check(await access.Permissions.Check(target) == PermissionStatus.Denied, "app-observed status is returned without native request work");
            access.Observers.Failure(target, new DeviceReadoutException(ErrorCode.PermissionDenied, "Application reports unavailable access."));
            await Error(ErrorCode.PermissionDenied, async () => {await stream.MoveNextAsync();});
        }
        var reads = runtime.InventoryReads;await Error(ErrorCode.PermissionDenied, () => access.Get(target));
        Check(runtime.InventoryReads == reads && requests == 0, "failure state blocks fresh native work and reads never request permission");
        var request = access.WithReadTimeout(TimeSpan.FromMilliseconds(5)).Permissions.Request(target, deadline.Token);
        await Task.Delay(50);Check(!request.IsCompleted && requests == 1, "only explicit request reaches app coordinator, outside read timeout");
        access.Observers.Permission(target, PermissionStatus.Granted);
        Check(await request == PermissionStatus.Granted, "application observer completes permission wait");
        access.Observers.Failure(target, null);
        Check((await access.Get(target)).Ssid == "Observed", "clearing app failure resumes fresh explicit collection");
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.References.Values.All(count => count == 0) && runtime.Registrations == runtime.Removals, "observer failure closes native registration and releases interfaces");
    }

    private static async Task ActualWifi()
    {
        var runtime = new NativeConnectivityProbe();var caller = Environment.CurrentManagedThreadId;
        using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime));
        var targets = await access.List(Entities.WifiConnection);
        var current = await access.Current(Entities.WifiConnection);
        Check(current is null || targets.Contains(current), "native preferred Wi-Fi target belongs to the active inventory");
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        foreach (var target in targets) {
            var value = await access.Get(target);
            Check(value.CollectedAt != default && value.Bssid is null, "actual native read has completion timestamp and performs no gated BSSID query");
            await using var stream = access.WithPollInterval(TimeSpan.FromMilliseconds(25)).Watch(target, deadline.Token).GetAsyncEnumerator();
            Check(await stream.MoveNextAsync() && await stream.MoveNextAsync(), "actual native initial snapshot and poll");
        }
        await TestCompletion.Until(() => Volatile.Read(ref runtime.Active) == 0, "actual Wi-Fi registrations removed");
        Check(runtime.Active == 0 && runtime.Registrations == runtime.Removals && runtime.RemovalResult == 0, "available physical Wi-Fi registrations are removed");
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.FactoryReleases == 1 && runtime.Initializations == 1 && runtime.Uninitializations == 1
            && runtime.Threads.Distinct().Count() == 1 && !runtime.Threads.Contains(caller), "actual inventory and lifetime remain worker-owned");
        Console.WriteLine($"Native Windows Wi-Fi: active connections={targets.Length}, preferred Wi-Fi={current is not null}; no SSIDs or network identifiers logged.");
    }

    private sealed partial class ConnectivityFixture
    {
        [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int Query(nint self, in Guid iid, out nint value);
        internal sealed class WifiProfile
        {
            internal nint Pointer;
            internal string Ssid = "";
            internal Guid AdapterId = Guid.NewGuid(), NetworkId = Guid.NewGuid();
            internal bool IsWifi = true, Present = true, NoDetails = false, NoSecurity = false, NoAdapter = false, NoNetwork = false;
            internal int Level = 3, Auth = 8, Encryption = 6;
            internal bool IsWwan = false;
            internal string HomeProvider = "00101";
            internal uint DataClass = 32;
            internal int QueryResult = 0, IsWifiResult = 0, LevelResult = 0, AdapterResult = 0, NetworkResult = 0, SsidResult = 0, DetailsResult = 0, SecurityResult = 0, AuthResult = 0, EncryptionResult = 0;
        }
        internal readonly List<WifiProfile> WifiProfiles = [];
        internal WifiProfile? Preferred;
        internal int InventoryReads, WifiFieldReads, InventoryResult = 0, SizeResult = 0, ItemResult = 0;
        internal uint? InvalidSize = null;
        internal TaskCompletionSource InventoryStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly ManualResetEventSlim ContinueInventory = new(true);
        private WifiProfile[] inventory = [];
        internal void EnableWifi()
        {
            var vector = Interface(10);
            Set(factory, 6, new WinRtGetInterface((nint self, out nint value) => {
                Record();InventoryReads++;value = Take(vector);inventory = WifiProfiles.Where(p => p.Present).ToArray();InventoryStarted.TrySetResult();
                return ContinueInventory.Wait(TimeSpan.FromSeconds(3)) ? InventoryResult : unchecked((int)0x80004005);
            }));
            Set(vector, 7, new WinRtGetUInt32((nint self, out uint value) => {Record();value = InvalidSize ?? (uint)inventory.Length;return SizeResult;}));
            Set(vector, 6, new WinRtGetAt((nint self, uint index, out nint value) => {Record();value = Take(inventory[index].Pointer);return ItemResult;}));
            Set(factory, 7, new WinRtGetInterface((nint self, out nint value) => {Record();value = Preferred is null ? 0 : Take(Preferred.Pointer);return ProfileResult;}));
        }
        internal WifiProfile AddWifi(string ssid)
        {
            var profile = new WifiProfile {Pointer = Interface(15), Ssid = ssid};
            var extended = Interface(10);var adapter = Interface(11);var network = Interface(8);
            var details = Interface(7);var security = Interface(8);
            var wwan = Interface(10);
            Set(profile.Pointer, 0, new Query((nint self, in Guid iid, out nint value) => {
                Record();value = Take(extended);return iid == new Guid("e2045145-4c9f-400c-9150-7ec7d6e2888a") ? profile.QueryResult : unchecked((int)0x80004002);
            }));
            Set(extended, 7, new WinRtGetBoolean((nint self, out byte value) => {Record();value = profile.IsWifi ? (byte)1 : (byte)0;return profile.IsWifiResult;}));
            Set(extended, 6, new WinRtGetBoolean((nint self, out byte value) => {Record();value = profile.IsWwan ? (byte)1 : (byte)0;return 0;}));
            Set(extended, 8, new WinRtGetInterface((nint self, out nint value) => {Record();value = Take(wwan);return 0;}));
            Set(wwan, 6, new WinRtGetInterface((nint self, out nint value) => {Record();return WindowsCreateString(profile.HomeProvider, profile.HomeProvider.Length, out value);}));
            Set(wwan, 9, new WinRtGetUInt32((nint self, out uint value) => {Record();value = profile.DataClass;return 0;}));
            Set(profile.Pointer, 7, new WinRtGetInt32((nint self, out int value) => {Record();value = profile.Level;return profile.LevelResult;}));
            Set(profile.Pointer, 11, new WinRtGetInterface((nint self, out nint value) => {Record();value = profile.NoAdapter ? 0 : Take(adapter);return profile.AdapterResult;}));
            Set(adapter, 10, new WinRtGetGuid((nint self, out Guid value) => {Record();value = profile.AdapterId;return 0;}));
            Set(adapter, 9, new WinRtGetInterface((nint self, out nint value) => {Record();value = profile.NoNetwork ? 0 : Take(network);return profile.NetworkResult;}));
            Set(network, 6, new WinRtGetGuid((nint self, out Guid value) => {Record();value = profile.NetworkId;return 0;}));
            Set(extended, 9, new WinRtGetInterface((nint self, out nint value) => {Record();value = profile.NoDetails ? 0 : Take(details);return profile.DetailsResult;}));
            Set(details, 6, new WinRtGetInterface((nint self, out nint value) => {
                Record();WifiFieldReads++;var hr = WindowsCreateString(profile.Ssid, profile.Ssid.Length, out value);return hr < 0 ? hr : profile.SsidResult;
            }));
            Set(profile.Pointer, 14, new WinRtGetInterface((nint self, out nint value) => {Record();value = profile.NoSecurity ? 0 : Take(security);return profile.SecurityResult;}));
            Set(security, 6, new WinRtGetInt32((nint self, out int value) => {Record();value = profile.Auth;return profile.AuthResult;}));
            Set(security, 7, new WinRtGetInt32((nint self, out int value) => {Record();value = profile.Encryption;return profile.EncryptionResult;}));
            WifiProfiles.Add(profile);Preferred ??= profile;return profile;
        }
        [DllImport("combase.dll", CharSet = CharSet.Unicode)] private static extern int WindowsCreateString(string text, int length, out nint value);
    }
}
