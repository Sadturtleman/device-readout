using System.Net.NetworkInformation;
using System.Runtime.Versioning;
using DeviceReadout;
using DeviceReadout.Windows;
using BclInterface = System.Net.NetworkInformation.NetworkInterface;
using BclInterfaceType = System.Net.NetworkInformation.NetworkInterfaceType;

[SupportedOSPlatform("windows")]
internal static partial class WindowsNetworkTests
{
    internal static IEnumerable<(string Name, Func<Task> Run)> Cases() => [
        ("Windows network handles retire after observed removal and do not bind a reappearing native ID", Generations),
        ("Windows network failed inventories preserve handles and read-time removal remains permanent", InventoryFailures),
        ("Windows network notifications wake worker reads, preserve equal values and retire every removed-target stream", Notifications),
        ("Windows IP notification registration ignores acknowledgements, retains protocol changes and releases native callbacks", NativeNotificationContract),
        ("Windows network native registration failures roll back and callback failures stop existing streams", NotificationFailures),
        ("real Windows network reads register all IP notifications and cancel them on the collection worker", ActualNativeNotifications),
        ("Windows network routes preserve IPv4, scoped IPv6, default and on-link paths for the selected adapter", RouteFields),
        ("Windows route failures remain field-local and an unspecified scoped next hop is not a gateway", RouteFailures),
        ("Windows MTU reads IPv6-only interfaces and preserves partial availability without changing other fields", MtuFields),
        ("real Windows network route snapshots include IPv4 and IPv6 loopback routes with no gateway", ActualRoutes)
    ];
    private static async Task Generations()
    {
        var platform = new NetworkFixture();using var access = new DeviceAccess(new WindowsCollector(networkPlatform: platform));
        var first = (await access.NetworkInterfaces.List()).Single();
        Check((await access.Get(first)).Name == "Fixture Ethernet", "initial interface read");
        platform.Adapters = [];
        Check((await access.NetworkInterfaces.List()).Length == 0, "successful empty inventory");
        await Error(ErrorCode.EntityRemoved, () => access.Get(first));
        platform.Adapters = [new AdapterFixture()];
        var fresh = (await access.NetworkInterfaces.List()).Single();
        Check(fresh != first, "reappearance must create a new context-owned handle");
        await Error(ErrorCode.EntityRemoved, () => access.Get(first));
        Check((await access.Get(fresh)).Name == "Fixture Ethernet", "fresh generation remains readable");
    }
    private static async Task ActualNativeNotifications()
    {
        var native = new NativeNotificationProbe();var caller = Environment.CurrentManagedThreadId;
        using var access = new DeviceAccess(new WindowsCollector(networkPlatform: new WindowsNetworkPlatform(native)));
        Check(native.Threads.Count == 0, "native network construction is inert");
        var targets = await access.NetworkInterfaces.List();Check(targets.Length > 0, "native inventory includes a readable interface");
        await native.Initial.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var snapshots = new List<NetworkInterfaceSnapshot>();foreach (var target in targets) snapshots.Add(await access.Get(target));
        Check(snapshots.All(snapshot => !string.IsNullOrEmpty(snapshot.Name)), "actual native interface names");
        await using (var stream = access.Watch(targets[0]).GetAsyncEnumerator()) Check(await stream.MoveNextAsync(), "actual native watch initial state");
        Check(native.Registered == 3 && native.Removed == 0, "one context-owned registration per native table");
        access.Dispose();await native.Disposed.Task.WaitAsync(TimeSpan.FromSeconds(3));
        Check(native.Removed == 3 && native.Threads.Distinct().Count() == 1 && !native.Threads.Contains(caller), "all native cancellations succeed off the caller");
        Console.WriteLine($"Native Windows network: {targets.Length} interfaces read; three notification acknowledgements and three cancellations completed on the worker.");
    }
    private static async Task NotificationFailures()
    {
        var partial = new NotificationFixture();partial.Results[WindowsNetworkChangeKind.Address] = 5;
        using (var access = new DeviceAccess(new WindowsCollector(networkPlatform: new NetworkFixture {Notifications = partial}))) {
            await Error(ErrorCode.PermissionDenied, () => access.NetworkInterfaces.List());
            Check(partial.Entries.Count == 2 && partial.Removed.SequenceEqual(new nint[] {1}), "failed second registration releases the first");
            await Error(ErrorCode.PermissionDenied, () => access.NetworkInterfaces.List());
            Check(partial.Entries.Count == 2, "registration failure is not silently retried");
        }
        var unsupported = new NotificationFixture();foreach (var kind in Enum.GetValues<WindowsNetworkChangeKind>()) unsupported.Results[kind] = 50;
        using (var access = new DeviceAccess(new WindowsCollector(networkPlatform: new NetworkFixture {Notifications = unsupported}))) {
            var target = (await access.NetworkInterfaces.List()).Single();
            await using var stream = access.WithPollInterval(TimeSpan.FromMilliseconds(25)).Watch(target).GetAsyncEnumerator();
            Check(await stream.MoveNextAsync() && await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(2)), "unsupported native observations retain equal polling values");
        }
        var notifications = new NotificationFixture();var platform = new NetworkFixture {Notifications = notifications};
        using (var access = new DeviceAccess(new WindowsCollector(networkPlatform: platform))) {
            var target = (await access.NetworkInterfaces.List()).Single();
            await using var stream = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(target).GetAsyncEnumerator();
            Check(await stream.MoveNextAsync(), "initial state before native failure");
            notifications.Emit(WindowsNetworkChangeKind.Interface, 0, 0);
            await Error(ErrorCode.ReadFailed, () => stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(2)));
            notifications.Emit(WindowsNetworkChangeKind.Interface, 0, 1);
            await Error(ErrorCode.ReadFailed, () => access.Get(target));
            await Error(ErrorCode.ReadFailed, () => access.NetworkInterfaces.List());
        }
        await platform.Disposed.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(notifications.Removed.Count == 3, "callback failure still releases every native registration");
    }
    private static async Task NativeNotificationContract()
    {
        var notifications = new NotificationFixture();var platform = new NetworkFixture {Notifications = notifications};
        using var access = new DeviceAccess(new WindowsCollector(networkPlatform: platform));
        var target = (await access.NetworkInterfaces.List()).Single();
        Check(notifications.Entries.Count == 3, "interface, address and route observation must register before inventory");
        await using var stream = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(target).GetAsyncEnumerator();
        Check(await stream.MoveNextAsync(), "initial state");
        var next = stream.MoveNextAsync().AsTask();
        notifications.Emit(WindowsNetworkChangeKind.Interface, 3, 0);
        await Task.Delay(30);Check(!next.IsCompleted, "registration acknowledgement is not an extra snapshot");
        // The native row is only a wake-up signal: deleting one protocol's MIB instance is not device removal.
        notifications.Emit(WindowsNetworkChangeKind.Interface, 2, 1);
        Check(await next.WaitAsync(TimeSpan.FromSeconds(2)) && stream.Current.Name == "Fixture Ethernet", "remaining adapter survives a protocol deletion");
        foreach (var kind in new[] {WindowsNetworkChangeKind.Address, WindowsNetworkChangeKind.Route}) {
            notifications.Emit(kind, 0, 1);
            Check(await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(2)), "native table change triggers a snapshot");
        }
        await stream.DisposeAsync();access.Dispose();await platform.Disposed.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(notifications.Removed.Count == 3 && notifications.Threads.Distinct().Count() == 1, "all registrations are removed on their collection worker");
        notifications.Emit(WindowsNetworkChangeKind.Interface, 0, 1);
    }
    private static async Task Notifications()
    {
        var platform = new NetworkFixture();var caller = Environment.CurrentManagedThreadId;
        using var access = new DeviceAccess(new WindowsCollector(networkPlatform: platform));
        Check(platform.Threads.Count == 0, "network construction must be inert");
        var target = (await access.NetworkInterfaces.List()).Single();
        await using var first = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(target).GetAsyncEnumerator();
        await using var second = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(target).GetAsyncEnumerator();
        Check(await first.MoveNextAsync() && await second.MoveNextAsync(), "initial state for both streams");
        platform.Adapters = [new AdapterFixture {State = OperationalStatus.Down}];
        platform.Signal();
        Check(await first.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(2)) && first.Current.OperationalState == NetworkOperationalState.Down, "event triggers fresh first-stream state before the poll");
        Check(await second.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(2)) && second.Current.OperationalState == NetworkOperationalState.Down, "shared event reaches the second stream");
        platform.Signal();
        Check(await first.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(2)) && first.Current.OperationalState == NetworkOperationalState.Down, "equal event value is retained");
        Check(await second.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(2)), "equal value for second stream");
        platform.Adapters = [];
        Check((await access.NetworkInterfaces.List()).Length == 0, "independent discovery observes removal");
        await Error(ErrorCode.EntityRemoved, () => first.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(2)));
        await Error(ErrorCode.EntityRemoved, () => second.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(2)));
        Check(platform.Registered == 1 && platform.Released == 0, "context keeps a single native observation after streams end");
        access.Dispose();
        await platform.Disposed.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(platform.Threads.Distinct().Count() == 1 && !platform.Threads.Contains(caller), "queries, registration and disposal stay on one worker");
        platform.Signal(); // A callback retained by an OS seam cannot revive a closed context.
    }
    private static async Task InventoryFailures()
    {
        var platform = new NetworkFixture();using var access = new DeviceAccess(new WindowsCollector(networkPlatform: platform));
        var first = (await access.NetworkInterfaces.List()).Single();
        platform.Failure = new NetworkInformationException(5);
        await Error(ErrorCode.PermissionDenied, () => access.NetworkInterfaces.List());
        platform.Failure = null;
        Check((await access.NetworkInterfaces.List()).Single() == first, "failed inventory must retain the existing generation");
        platform.Adapters = [new AdapterFixture(), new AdapterFixture()];
        await Error(ErrorCode.ReadFailed, () => access.NetworkInterfaces.List());
        platform.Adapters = [new AdapterFixture()];
        Check((await access.NetworkInterfaces.List()).Single() == first, "malformed inventory must retain the existing generation");
        platform.Adapters = [];
        await Error(ErrorCode.EntityRemoved, () => access.Get(first));
        platform.Adapters = [new AdapterFixture()];
        await Error(ErrorCode.EntityRemoved, () => access.Get(first));
        Check((await access.Capabilities.Get(first)).Readable == false, "removed generation capabilities");
        Check((await access.NetworkInterfaces.List()).Single() != first, "read-time removal survives rediscovery");
    }
    private sealed class NetworkFixture : IWindowsNetworkPlatform
    {
        internal BclInterface[] Adapters = [new AdapterFixture()];
        internal Exception? Failure;
        internal Action? Changed;
        internal IWindowsNetworkNotifications? Notifications;
        internal int Registered, Released;
        internal readonly List<int> Threads = [];
        internal readonly TaskCompletionSource Disposed = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public BclInterface[] Enumerate(CancellationToken token) {Threads.Add(Environment.CurrentManagedThreadId);token.ThrowIfCancellationRequested();if (Failure is not null) throw Failure;return Adapters.ToArray();}
        public IDisposable Observe(Action changed, Action<Exception> fail)
        {
            Threads.Add(Environment.CurrentManagedThreadId);Registered++;Changed = changed;
            var native = Notifications is null ? null : new WindowsNetworkChanges(Notifications).Subscribe(changed, fail);
            return new Cleanup(() => {native?.Dispose();Threads.Add(Environment.CurrentManagedThreadId);Released++;Disposed.TrySetResult();});
        }
        internal void Signal() => (Changed ?? throw new Exception("Native network observation was not registered."))();
    }
    private sealed class NotificationFixture : IWindowsNetworkNotifications
    {
        internal readonly Dictionary<WindowsNetworkChangeKind, uint> Results = [];
        internal readonly Dictionary<WindowsNetworkChangeKind, (WindowsNetworkChangeCallback Callback, nint Context, nint Handle)> Entries = [];
        internal readonly List<nint> Removed = [];
        internal readonly List<int> Threads = [];
        public uint Register(WindowsNetworkChangeKind kind, WindowsNetworkChangeCallback callback, nint context, out nint handle)
        {
            Threads.Add(Environment.CurrentManagedThreadId);handle = (int)kind + 1;Entries.Add(kind, (callback, context, handle));
            if (Results.GetValueOrDefault(kind) is > 0 and var failure) {handle = 0;return failure;}
            callback(context, 0, 3);return 0;
        }
        public uint Unregister(nint handle) {Threads.Add(Environment.CurrentManagedThreadId);Removed.Add(handle);return 0;}
        internal void Emit(WindowsNetworkChangeKind kind, uint type, nint row)
        {var entry = Entries[kind];entry.Callback(entry.Context, row, type);}
    }
    private sealed class NativeNotificationProbe : IWindowsNetworkNotifications
    {
        private readonly WindowsNetworkNotifications native = new();
        private readonly List<WindowsNetworkChangeCallback> callbacks = [];
        private int acknowledged;
        internal int Registered, Removed;
        internal readonly List<int> Threads = [];
        internal readonly TaskCompletionSource Initial = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource Disposed = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public uint Register(WindowsNetworkChangeKind kind, WindowsNetworkChangeCallback callback, nint context, out nint handle)
        {
            Threads.Add(Environment.CurrentManagedThreadId);
            WindowsNetworkChangeCallback probe = (state, row, type) => {
                if (type == 3 && Interlocked.Increment(ref acknowledged) == 3) Initial.TrySetResult();
                callback(state, row, type);
            };
            callbacks.Add(probe);var result = native.Register(kind, probe, context, out handle);
            if (result == 0) Registered++;return result;
        }
        public uint Unregister(nint handle)
        {
            Threads.Add(Environment.CurrentManagedThreadId);var result = native.Unregister(handle);
            if (result == 0 && ++Removed == 3) Disposed.TrySetResult();return result;
        }
    }
    private sealed class Cleanup(Action release) : IDisposable {public void Dispose() => release();}
    private sealed class AdapterFixture : BclInterface
    {
        public override string Id => "{52FDD4D7-27B8-4616-A8B3-100000000001}";
        public override string Name => "Fixture Ethernet";
        public override string Description => "Controlled native network input";
        internal OperationalStatus State = OperationalStatus.Up;
        internal IPInterfaceProperties? Properties;
        internal bool Ipv4 = true, Ipv6 = true;
        public override OperationalStatus OperationalStatus => State;
        public override BclInterfaceType NetworkInterfaceType => BclInterfaceType.Ethernet;
        public override long Speed => 1_000_000_000;
        public override bool SupportsMulticast => true;
        public override bool IsReceiveOnly => false;
        public override IPInterfaceProperties GetIPProperties() => Properties ?? throw new NetworkInformationException(50);
        public override IPv4InterfaceStatistics GetIPv4Statistics() => throw new NetworkInformationException(50);
        public override IPInterfaceStatistics GetIPStatistics() => throw new NetworkInformationException(50);
        public override PhysicalAddress GetPhysicalAddress() => new([0, 0x11, 0x22, 0x33, 0x44, 0x55]);
        public override bool Supports(NetworkInterfaceComponent component) => component == NetworkInterfaceComponent.IPv4 ? Ipv4 : Ipv6;
    }
    private static void Check(bool condition, string message) {if (!condition) throw new Exception(message);}
    private static async Task Error(ErrorCode code, Func<Task> action)
    {
        try {await action();} catch (DeviceReadoutException error) when (error.Code == code) {return;}
        throw new Exception($"Expected {code}.");
    }
}
