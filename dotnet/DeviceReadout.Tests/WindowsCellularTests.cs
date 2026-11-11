using System.Runtime.InteropServices;
using DeviceReadout;
using DeviceReadout.Windows;

internal static partial class WindowsConnectivityTests
{
    private static async Task CellularAccounts()
    {
        var runtime = new ConnectivityFixture();runtime.EnableCellular();
        var first = runtime.AddAccount("Carrier");var second = runtime.AddAccount("Carrier");
        var caller = Environment.CurrentManagedThreadId;
        using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime));
        Check(runtime.Initializations == 0, "cellular context construction is inert");
        var targets = await access.List(Entities.CellularSubscription);
        Check(targets.Length == 2 && !targets[0].Equals(targets[1]), "same-provider subscriptions remain distinct accounts");
        Check((await access.Get(targets[0])).CarrierName == "Carrier", "selected account supplies its home provider name");
        second.Name = "Second";
        Check((await access.Get(targets[1])).CarrierName == "Second", "selected account is not the first provider match");
        first.Name = "";
        Check((await access.Get(targets[0])).CarrierName == "", "readable empty strings are preserved");
        Check((await access.Capabilities.Get(targets[0])).Readable == true, "account capability is exposed");
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        await using (var stream = access.WithPollInterval(TimeSpan.FromMilliseconds(25)).Watch(targets[0], deadline.Token).GetAsyncEnumerator()) {
            Check(await stream.MoveNextAsync() && await stream.MoveNextAsync(), "initial and equal polling snapshots are delivered");
            Check(stream.Current.CollectedAt != default, "snapshot receives one completion timestamp");
        }
        first.Present = false;
        Check((await access.List(Entities.CellularSubscription)).Length == 1, "observed removal updates inventory");
        first.Present = true;
        var replacement = await access.List(Entities.CellularSubscription);
        Check(replacement.Length == 2 && !replacement.Contains(targets[0]), "same native account reappears with a new handle");
        await Error(ErrorCode.EntityRemoved, () => access.Get(targets[0]));
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.Initializations == 1 && runtime.Uninitializations == 1 && runtime.References.Values.All(value => value == 0)
            && runtime.Threads.Distinct().Count() == 1 && !runtime.Threads.Contains(caller), "account and network factories share a worker-owned runtime and release all interfaces");
    }

    private static async Task CellularFields()
    {
        var runtime = new ConnectivityFixture();runtime.EnableCellular();
        var account = runtime.AddAccount("Home carrier");
        var first = runtime.AddWifi("APN label");first.IsWifi = false;first.IsWwan = true;account.Profiles.Add(first);
        var second = runtime.AddWifi("Other APN");second.IsWifi = false;second.IsWwan = true;account.Profiles.Add(second);
        second.AdapterId = first.AdapterId;
        using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime));
        var targets = await access.List(Entities.CellularSubscription);Check(targets.Length == 1, "multiple APNs do not duplicate an account");
        var target = targets[0];var value = await access.Get(target);
        Check(value is {CarrierName: "Home carrier", SlotIndex: 0, MobileCountryCode: "001", MobileNetworkCode: "01", RadioTechnology: RadioTechnology.Lte, Roaming: false}, "account provider, slot zero, home MCC/MNC and current LTE mapping");
        Check(value.CountryCode is null, "no country is guessed from MCC or locale");
        foreach (var (native, expected) in new (uint, RadioTechnology?)[] {
            (1, RadioTechnology.Gprs), (2, RadioTechnology.Edge), (4, RadioTechnology.Umts), (8, RadioTechnology.Hsdpa), (16, RadioTechnology.Hsupa),
            (32, RadioTechnology.Lte), (64, RadioTechnology.NrNsa), (128, RadioTechnology.NrSa), (65536, RadioTechnology.Cdma1x),
            (131072, RadioTechnology.Evdo0), (262144, RadioTechnology.EvdoA), (2097152, RadioTechnology.EvdoB),
            (0, null), (96, null), (256, null), (524288, null), (1048576, null), (4194304, null), (0x80000000, null)
        }) {first.DataClass = second.DataClass = native;Check((await access.Get(target)).RadioTechnology == expected, "explicit current data class and unknown/combined values");}
        first.DataClass = 32;second.DataClass = 64;
        Check((await access.Get(target)).RadioTechnology is null, "disagreeing active profiles do not choose the fastest radio");
        second.Level = 0;Check((await access.Get(target)).RadioTechnology == RadioTechnology.Lte, "disconnected profile is not an active radio");
        first.Level = 0;Check((await access.Get(target)).RadioTechnology is null, "registered but disconnected account has no active data technology");
        foreach (var (native, expected) in new (int, bool?)[] {(0, null), (1, null), (2, null), (3, false), (4, true), (5, true), (6, null), (99, null)}) {
            account.Registration = native;Check((await access.Get(target)).Roaming == expected, "home, roaming, partner and unregistered states");
        }
        first.HomeProvider = second.HomeProvider = "310260";
        value = await access.Get(target);Check(value.MobileCountryCode == "310" && value.MobileNetworkCode == "260", "three-digit MNC remains a string");
        account.CellularClass = 2;value = await access.Get(target);
        Check(value.MobileCountryCode is null && value.MobileNetworkCode is null, "CDMA provider IDs are SIDs, not MCC/MNC");
        account.CellularClass = 1;first.HomeProvider = second.HomeProvider = "12abc";
        Check((await access.Get(target)).MobileCountryCode is null, "malformed home provider is unavailable");
        first.HomeProvider = "00101";second.HomeProvider = "00102";
        Check((await access.Get(target)).MobileCountryCode is null, "ambiguous home providers are not selected arbitrarily");
        account.Slot = -1;Check((await access.Get(target)).SlotIndex is null, "negative native slot is unavailable");
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.References.Values.All(count => count == 0), "nested account, device, slot, network and profile interfaces are released");
    }

    private static async Task CellularCurrent()
    {
        var runtime = new ConnectivityFixture();runtime.EnableCellular();runtime.EnableWifi();
        var first = runtime.AddAccount("Shared carrier");var second = runtime.AddAccount("Shared carrier");
        var firstProfile = runtime.AddWifi("First APN");firstProfile.IsWifi = false;firstProfile.IsWwan = true;first.Profiles.Add(firstProfile);
        var secondProfile = runtime.AddWifi("Second APN");secondProfile.IsWifi = false;secondProfile.IsWwan = true;second.Profiles.Add(secondProfile);
        using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime));
        var targets = await access.List(Entities.CellularSubscription);
        runtime.Preferred = secondProfile;
        Check(targets[1].Equals(await access.Current(Entities.CellularSubscription)), "current account matches the preferred cellular adapter, not provider name or list order");
        runtime.Preferred = firstProfile;Check(targets[0].Equals(await access.Current(Entities.CellularSubscription)), "preferred data account follows Windows path selection");
        firstProfile.Level = 0;Check(await access.Current(Entities.CellularSubscription) is null, "disconnected preferred profile is not an active subscription");
        firstProfile.Level = 3;
        secondProfile.AdapterId = firstProfile.AdapterId;Check(await access.Current(Entities.CellularSubscription) is null, "ambiguous account association does not select first");
        secondProfile.AdapterId = Guid.NewGuid();runtime.Preferred = runtime.AddWifi("Preferred Wi-Fi");
        Check(await access.Current(Entities.CellularSubscription) is null, "Wi-Fi preference does not choose a background cellular account");
        runtime.Preferred = null;Check(await access.Current(Entities.CellularSubscription) is null, "no default path means no current data subscription");
        runtime.Preferred = secondProfile;
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        await using (var stream = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(targets[1], deadline.Token).GetAsyncEnumerator()) {
            Check(await stream.MoveNextAsync(), "initial selected account snapshot");
            second.Registration = 4;secondProfile.DataClass = 128;runtime.Fire();
            Check(await stream.MoveNextAsync() && stream.Current is {RadioTechnology: RadioTechnology.NrSa, Roaming: true}, "native notification refreshes selected account before poll");
            runtime.Fire();Check(await stream.MoveNextAsync() && stream.Current.Roaming == true, "equal event snapshots are retained");
        }
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.Registrations == runtime.Removals && runtime.HandlerCount == 0 && runtime.References.Values.All(count => count == 0), "account watches release status events and both native factories");
    }

    private static async Task CellularFailures()
    {
        const int denied = unchecked((int)0x80070005), failed = unchecked((int)0x80004005);
        var runtime = new ConnectivityFixture();runtime.EnableCellular();var account = runtime.AddAccount("Readable");
        var profile = runtime.AddWifi("APN");profile.IsWwan = true;account.Profiles.Add(profile);
        using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime));
        var target = (await access.List(Entities.CellularSubscription)).Single();
        account.NameResult = denied;
        Check((await access.Get(target)) is {CarrierName: null, SlotIndex: 0, Roaming: false, RadioTechnology: RadioTechnology.Lte}, "unreadable carrier does not erase independent native fields");
        account.NameResult = 0;account.DeviceResult = denied;
        Check((await access.Get(target)) is {CarrierName: "Readable", SlotIndex: null, MobileCountryCode: null, RadioTechnology: RadioTechnology.Lte, Roaming: false}, "device access failure leaves independent network/profile data");
        account.DeviceResult = 0;account.ProfilesResult = denied;
        Check((await access.Get(target)) is {CarrierName: "Readable", SlotIndex: 0, MobileCountryCode: null, RadioTechnology: null, Roaming: false}, "profile failure remains field-local");
        account.ProfilesResult = 0;account.Device4Result = unchecked((int)0x80004002);
        Check((await access.Get(target)) is {SlotIndex: null, MobileCountryCode: "001"}, "unavailable optional slot interface preserves cellular class");
        account.Device4Result = 0;account.NameResult = account.DeviceResult = account.NetworkResult = account.ProfilesResult = failed;
        await Error(ErrorCode.ReadFailed, () => access.Get(target));
        account.NameResult = denied;await Error(ErrorCode.PermissionDenied, () => access.Get(target));
        account.NameResult = account.DeviceResult = account.NetworkResult = account.ProfilesResult = 0;
        foreach (var mode in new[] {0, 1, 2, 3, 4, 5}) {
            runtime.AccountInventoryResult = mode == 0 ? denied : 0;runtime.AccountSizeResult = mode == 1 ? failed : 0;
            runtime.AccountItemResult = mode == 2 ? failed : 0;runtime.AccountInvalidSize = mode == 3 ? 4097u : null;
            runtime.NoAccountVector = mode == 4;if (mode == 5) runtime.Accounts.Add(account);
            await Error(mode == 0 ? ErrorCode.PermissionDenied : ErrorCode.ReadFailed, () => access.List(Entities.CellularSubscription));
            if (mode == 5) runtime.Accounts.RemoveAt(1);
            runtime.AccountInventoryResult = runtime.AccountSizeResult = runtime.AccountItemResult = 0;
            runtime.AccountInvalidSize = null;runtime.NoAccountVector = false;
            Check((await access.List(Entities.CellularSubscription)).Single().Equals(target), "failed or malformed inventory does not retire the existing target");
        }
        account.ReturnedId = Guid.NewGuid().ToString();await Error(ErrorCode.ReadFailed, () => access.Get(target));account.ReturnedId = null;
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        await using (var stream = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(target, deadline.Token).GetAsyncEnumerator()) {
            Check(await stream.MoveNextAsync(), "initial state before inventory denial");runtime.AccountInventoryResult = denied;runtime.Fire();
            await Error(ErrorCode.PermissionDenied, async () => {await stream.MoveNextAsync();});
        }
        runtime.AccountInventoryResult = 0;
        Check((await access.Get(target)).CarrierName == "Readable", "explicit read recovers with fresh native state");
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.References.Values.All(count => count == 0) && runtime.HandlerCount == 0 && runtime.Registrations == runtime.Removals,
            "failed calls release nonnull native outputs and failed watches unregister");
    }

    private static async Task CellularDeadlines()
    {
        foreach (var stage in new[] {0, 1, 2}) foreach (var eventRead in new[] {false, true}) {
            var runtime = new ConnectivityFixture();runtime.EnableCellular();runtime.AddAccount("Held");
            var caller = Environment.CurrentManagedThreadId;
            using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime));
            var target = (await access.List(Entities.CellularSubscription)).Single();
            var configured = access.WithReadTimeout(TimeSpan.FromMilliseconds(250)).WithPollInterval(TimeSpan.FromHours(1));
            using var release = new ManualResetEventSlim(false);
            var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            Action hold = () => {started.TrySetResult();if (!release.Wait(TimeSpan.FromSeconds(3))) throw new Exception("Cellular test gate timed out.");};
            IAsyncEnumerator<CellularSubscriptionSnapshot>? stream = null;var devices = 0;var names = 0;
            try {
                if (eventRead) {stream = configured.Watch(target).GetAsyncEnumerator();Check(await stream.MoveNextAsync(), "initial state before held native event");}
                devices = runtime.AccountDeviceReads;names = runtime.AccountNameReads;
                if (stage == 0) runtime.OnAccountInventory = hold;
                else if (stage == 1) runtime.OnAccountCreate = hold;
                else runtime.OnAccountName = hold;
                if (eventRead) runtime.Fire();
                Task pending = eventRead ? stream!.MoveNextAsync().AsTask() : configured.Get(target);
                await started.Task.WaitAsync(TimeSpan.FromSeconds(2));
                await Task.Delay(10);Check(!pending.IsCompleted, "host continuation proceeds while native cellular call is held");
                await Error(ErrorCode.ReadTimeout, () => pending.WaitAsync(TimeSpan.FromSeconds(2)));
                access.Dispose();Check(!runtime.Stopped.Task.IsCompleted, "context disposal does not join native work");
            } finally {
                release.Set();access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
                if (stream is not null) await stream.DisposeAsync();
            }
            Check(runtime.AccountDeviceReads == devices && runtime.AccountNameReads == names + (stage == 2 ? 1 : 0), "late native result is released before subsequent field queries");
            Check(runtime.References.Values.All(count => count == 0) && runtime.Registrations == runtime.Removals && runtime.HandlerCount == 0
                && runtime.Threads.Distinct().Count() == 1 && !runtime.Threads.Contains(caller), "late native cleanup and event removal stay on the worker");
        }
    }

    private static async Task CellularObservers()
    {
        var runtime = new ConnectivityFixture();runtime.EnableCellular();runtime.AddAccount("Observed");
        using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime));
        var target = (await access.List(Entities.CellularSubscription)).Single();var requests = 0;
        using var coordinator = access.Observers.OnPermissionRequest((_, _) => {Interlocked.Increment(ref requests);return Task.CompletedTask;});
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        await using (var stream = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(target, deadline.Token).GetAsyncEnumerator()) {
            Check(await stream.MoveNextAsync(), "native initial state without a permission prompt");
            access.Observers.Permission(target, PermissionStatus.Denied);
            Check(await access.Permissions.Check(target) == PermissionStatus.Denied, "permission state comes from the app observer");
            access.Observers.Failure(target, new DeviceReadoutException(ErrorCode.PermissionDenied, "App reports unavailable access."));
            await Error(ErrorCode.PermissionDenied, async () => {await stream.MoveNextAsync();});
        }
        var inventories = runtime.AccountInventories;await Error(ErrorCode.PermissionDenied, () => access.Get(target));
        Check(runtime.AccountInventories == inventories && requests == 0, "observer failure blocks native reads and get/watch do not invoke permission coordination");
        var request = access.WithReadTimeout(TimeSpan.FromMilliseconds(5)).Permissions.Request(target, deadline.Token);
        await Task.Delay(50);Check(!request.IsCompleted && requests == 1, "explicit app permission interaction waits outside the read timeout");
        access.Observers.Permission(target, PermissionStatus.Granted);
        Check(await request == PermissionStatus.Granted, "observed state completes explicit permission interaction");
        access.Observers.Failure(target, null);Check((await access.Get(target)).CarrierName == "Observed", "explicit recovery reads fresh native state");
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.References.Values.All(count => count == 0) && runtime.Registrations == runtime.Removals, "observer failure releases native observation");
    }

    private static async Task ActualCellular()
    {
        var runtime = new NativeConnectivityProbe();var caller = Environment.CurrentManagedThreadId;
        using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime));
        var targets = await access.List(Entities.CellularSubscription);var current = await access.Current(Entities.CellularSubscription);
        Check(current is null || targets.Contains(current), "native preferred cellular account belongs to discovered inventory");
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        foreach (var target in targets) {
            var value = await access.Get(target);Check(value.CollectedAt != default, "actual account read produces a completion timestamp");
            await using var stream = access.WithPollInterval(TimeSpan.FromMilliseconds(25)).Watch(target, deadline.Token).GetAsyncEnumerator();
            Check(await stream.MoveNextAsync() && await stream.MoveNextAsync(), "actual available account initial/poll state");
        }
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.CellularFactoryReleases == 1 && runtime.FactoryReleases == 1 && runtime.Initializations == 1 && runtime.Uninitializations == 1
            && runtime.CellularSubscriptions == 1 && runtime.CellularUnsubscriptions == 1
            && runtime.Registrations == runtime.Removals && runtime.Active == 0 && runtime.Threads.Distinct().Count() == 1 && !runtime.Threads.Contains(caller),
            "actual cellular/network factory and runtime lifetimes are balanced on the worker");
        Console.WriteLine($"Native Windows cellular: available accounts={targets.Length}, preferred cellular={current is not null}; account/SIM identifiers are not logged.");
    }

    private sealed partial class ConnectivityFixture
    {
        internal sealed class CellularAccount
        {
            internal nint Pointer;
            internal string Id = Guid.NewGuid().ToString(), Name = "";
            internal bool Present = true;
            internal int Slot = 0, CellularClass = 1, Registration = 3;
            internal int NameResult = 0, DeviceResult = 0, NetworkResult = 0, ProfilesResult = 0, Device4Result = 0;
            internal string? ReturnedId = null;
            internal readonly List<WifiProfile> Profiles = [];
        }
        internal readonly List<CellularAccount> Accounts = [];
        private nint cellularFactory;
        private CellularAccount[] accountInventory = [];
        internal int AccountInventoryResult = 0, AccountSizeResult = 0, AccountItemResult = 0;
        internal uint? AccountInvalidSize = null;
        internal bool NoAccountVector = false;
        internal int AccountInventories, AccountNameReads, AccountDeviceReads;
        internal Action? OnAccountInventory, OnAccountCreate, OnAccountName;
        internal void EnableCellular()
        {
            cellularFactory = Interface(8);var vector = Interface(10);
            Set(cellularFactory, 6, new WinRtGetInterface((nint self, out nint value) => {
                Record();AccountInventories++;accountInventory = Accounts.Where(a => a.Present).ToArray();value = NoAccountVector ? 0 : Take(vector);OnAccountInventory?.Invoke();return AccountInventoryResult;
            }));
            Set(vector, 7, new WinRtGetUInt32((nint self, out uint value) => {Record();value = AccountInvalidSize ?? (uint)accountInventory.Length;return AccountSizeResult;}));
            Set(vector, 6, new WinRtGetAt((nint self, uint index, out nint value) => {Record();var id = accountInventory[index].Id;var hr = WindowsCreateString(id, id.Length, out value);return hr < 0 ? hr : AccountItemResult;}));
            Set(cellularFactory, 7, new WinRtCreateAccount((nint self, nint id, out nint value) => {
                Record();var raw = WindowsGetStringRawBuffer(id, out var length);var key = Marshal.PtrToStringUni(raw, (int)length);
                var account = Accounts.FirstOrDefault(a => a.Present && a.Id == key);value = account is null ? 0 : Take(account.Pointer);OnAccountCreate?.Invoke();return 0;
            }));
        }
        internal CellularAccount AddAccount(string name)
        {
            var account = new CellularAccount {Pointer = Interface(11), Name = name};
            var extended = Interface(7);var vector = Interface(10);var device = Interface(20);var device4 = Interface(7);
            var slots = Interface(14);var network = Interface(16);
            Set(account.Pointer, 0, new Query((nint self, in Guid iid, out nint value) => {Record();value = Take(extended);return iid == new Guid("38f52f1c-1136-4257-959f-b658a352b6d4") ? 0 : unchecked((int)0x80004002);}));
            Set(extended, 6, new WinRtGetInterface((nint self, out nint value) => {Record();value = Take(vector);return account.ProfilesResult;}));
            Set(vector, 7, new WinRtGetUInt32((nint self, out uint value) => {Record();value = (uint)account.Profiles.Count;return 0;}));
            Set(vector, 6, new WinRtGetAt((nint self, uint index, out nint value) => {Record();value = Take(account.Profiles[(int)index].Pointer);return 0;}));
            Set(account.Pointer, 9, new WinRtGetInterface((nint self, out nint value) => {Record();value = Take(network);return account.NetworkResult;}));
            Set(network, 7, new WinRtGetInt32((nint self, out int value) => {Record();value = account.Registration;return 0;}));
            Set(account.Pointer, 10, new WinRtGetInterface((nint self, out nint value) => {Record();AccountDeviceReads++;value = Take(device);return account.DeviceResult;}));
            Set(device, 10, new WinRtGetInt32((nint self, out int value) => {Record();value = account.CellularClass;return 0;}));
            Set(device, 0, new Query((nint self, in Guid iid, out nint value) => {Record();value = Take(device4);return iid == new Guid("263f3152-7b9d-582c-b17c-f80a60b50031") ? account.Device4Result : unchecked((int)0x80004002);}));
            Set(device4, 6, new WinRtGetInterface((nint self, out nint value) => {Record();value = Take(slots);return 0;}));
            Set(slots, 7, new WinRtGetInt32((nint self, out int value) => {Record();value = account.Slot;return 0;}));
            Set(account.Pointer, 6, new WinRtGetInterface((nint self, out nint value) => {Record();var id = account.ReturnedId ?? account.Id;return WindowsCreateString(id, id.Length, out value);}));
            Set(account.Pointer, 8, new WinRtGetInterface((nint self, out nint value) => {Record();AccountNameReads++;var hr = WindowsCreateString(account.Name, account.Name.Length, out value);OnAccountName?.Invoke();return hr < 0 ? hr : account.NameResult;}));
            Accounts.Add(account);return account;
        }
        public nint ActivateCellularFactory() {Record();return cellularFactory == 0 ? 0 : Take(cellularFactory);}
        [DllImport("combase.dll")] private static extern nint WindowsGetStringRawBuffer(nint value, out uint length);
    }
}
