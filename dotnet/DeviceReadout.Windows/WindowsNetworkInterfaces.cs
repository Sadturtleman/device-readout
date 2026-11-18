using System.Collections.Immutable;
using System.Globalization;
using System.Net.NetworkInformation;
using System.Runtime.Versioning;
using BclInterface = System.Net.NetworkInformation.NetworkInterface;
using BclInterfaceType = System.Net.NetworkInformation.NetworkInterfaceType;

namespace DeviceReadout.Windows;

internal interface IWindowsNetworkPlatform
{
    BclInterface[] Enumerate(CancellationToken token);
    NetworkInterfaceSnapshot? Properties(string adapterId, CancellationToken token) => null;
    IDisposable? Observe(Action changed, Action<Exception> fail) => null;
    void Dispose() { }
}

[SupportedOSPlatform("windows")]
internal sealed class WindowsNetworkPlatform(IWindowsNetworkNotifications? notifications = null, IWindowsNetworkPropertiesPlatform? propertiesPlatform = null) : IWindowsNetworkPlatform
{
    private readonly WindowsNetworkProperties properties = new(propertiesPlatform ?? new WindowsNetworkPropertiesPlatform());
    private readonly WindowsNetworkChanges changes = new(notifications ?? new WindowsNetworkNotifications());
    public NetworkInterfaceSnapshot Properties(string adapterId, CancellationToken token)
        => properties.Read(adapterId, token) ?? new NetworkInterfaceSnapshot();
    public IDisposable Observe(Action changed, Action<Exception> fail)
        => changes.Subscribe(changed, fail);
    public void Dispose() => changes.Dispose();
    public BclInterface[] Enumerate(CancellationToken token)
    {
        token.ThrowIfCancellationRequested();var result = BclInterface.GetAllNetworkInterfaces();
        token.ThrowIfCancellationRequested();return result;
    }
}

internal sealed class WindowsNetworkInterfaces(IWindowsNetworkPlatform platform, IWindowsRoutePlatform routePlatform) : IDisposable
{
    private sealed record Listener(string Handle, Action<Func<CancellationToken, DeviceSnapshot>> Changed, Action<Exception> Fail);
    private readonly ResourceCatalog catalog = new();
    private readonly WindowsRoutes routes = new(routePlatform);
    private readonly object gate = new();
    private readonly List<Listener> listeners = [];
    private IDisposable? observation;
    private bool observing, closed;
    private Exception? observationFailure;
    private void AssertHealthy()
    {
        lock (gate) {
            if (closed) throw new DeviceReadoutException(ErrorCode.EntityRemoved, "Network observation is closed.");
            if (observationFailure is { } error) throw error;
        }
    }
    private void EnsureObservation()
    {
        AssertHealthy();if (observing) return;observing = true;
        try {observation = platform.Observe(Changed, Failed);}
        catch (Exception error) {Failed(error);throw;}
        AssertHealthy();
    }
    private void Changed()
    {
        Listener[] current;
        lock (gate) {if (closed || observationFailure is not null) return;current = listeners.ToArray();}
        foreach (var listener in current) {
            try {listener.Changed(token => Read(listener.Handle, token));}
            catch (Exception error) {NotifyFailure(listener, error);}
        }
    }
    private void Failed(Exception error)
    {
        Listener[] current;
        lock (gate) {if (closed) return;observationFailure ??= error;current = listeners.ToArray();}
        foreach (var listener in current) NotifyFailure(listener, error);
    }
    private static void NotifyFailure(Listener listener, Exception error)
    {try {listener.Fail(error);} catch (Exception) { /* Do not unwind into an OS notification. */ }}
    internal ICollectorSubscription Observe(string? handle, Action<Func<CancellationToken, DeviceSnapshot>> changed, Action<Exception> fail, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();EnsureObservation();_ = catalog.Resolve(handle);
        var listener = new Listener(handle!, changed, fail);
        lock (gate) {AssertHealthy();listeners.Add(listener);}
        return new Observation(() => {lock (gate) listeners.Remove(listener);});
    }
    private sealed class Observation(Action release) : ICollectorSubscription
    {public bool PollingRequired => true;public void Dispose() => release();}
    public void Dispose()
    {
        lock (gate) {if (closed) return;closed = true;listeners.Clear();}
        try {observation?.Dispose();}
        finally {observation = null;platform.Dispose();}
    }
    private Dictionary<string, BclInterface> Refresh(CancellationToken token)
    {
        EnsureObservation();
        var found = new Dictionary<string, BclInterface>(StringComparer.OrdinalIgnoreCase);
        BclInterface[] native;
        try {native = platform.Enumerate(token);}
        catch (NetworkInformationException error) {throw new DeviceReadoutException(error.ErrorCode == 5 ? ErrorCode.PermissionDenied : ErrorCode.ReadFailed, "Windows network inventory failed.", error);}
        foreach (var adapter in native) {
            token.ThrowIfCancellationRequested();
            if (string.IsNullOrEmpty(adapter.Id) || !found.TryAdd(adapter.Id, adapter))
                throw new DeviceReadoutException(ErrorCode.ReadFailed, "Invalid Windows network interface inventory.");
        }
        token.ThrowIfCancellationRequested();AssertHealthy();catalog.Update(found.Keys);
        Listener[] current;lock (gate) current = listeners.ToArray();
        foreach (var listener in current) {
            try {_ = catalog.Resolve(listener.Handle);}
            catch (DeviceReadoutException error) {NotifyFailure(listener, error);}
        }
        return found;
    }
    internal IReadOnlyList<string> List(CancellationToken token) => Refresh(token).Keys.Select(id => catalog.Find(id)!).ToArray();
    internal EntityCapabilities Capabilities(string? handle)
    {
        if (handle is null) return new(true, true);
        try {AssertHealthy();_ = catalog.Resolve(handle);return new(true, true);}
        catch (DeviceReadoutException) {return new(false, false);}
    }
    internal NetworkInterfaceSnapshot Read(string? handle, CancellationToken token)
    {
        _ = catalog.Resolve(handle);
        var found = Refresh(token);var adapter = found[catalog.Resolve(handle)];
        IPInterfaceProperties? ip = null;
        try {ip = adapter.GetIPProperties();} catch (NetworkInformationException) { }
        var address = adapter.GetPhysicalAddress().GetAddressBytes();
        var native = platform.Properties(adapter.Id, token);
        var snapshot = new NetworkInterfaceSnapshot {Name = adapter.Name,
            InterfaceType = adapter.NetworkInterfaceType switch {
                BclInterfaceType.Ethernet or BclInterfaceType.Ethernet3Megabit or BclInterfaceType.GigabitEthernet or BclInterfaceType.FastEthernetFx or BclInterfaceType.FastEthernetT => NetworkInterfaceType.Ethernet,
                BclInterfaceType.Wireless80211 => NetworkInterfaceType.Wifi, BclInterfaceType.Loopback => NetworkInterfaceType.Loopback,
                // Native IFTYPE values may be returned even without a named BCL enum member.
                (BclInterfaceType)243 or (BclInterfaceType)244 => NetworkInterfaceType.Cellular, // IF_TYPE_WWANPP / WWANPP2
                (BclInterfaceType)209 => NetworkInterfaceType.Bridge, // IANA bridge type
                BclInterfaceType.Tunnel => NetworkInterfaceType.Tunnel, BclInterfaceType.Ppp => NetworkInterfaceType.Ppp, _ => null
            },
            OperationalState = adapter.OperationalStatus switch {
                OperationalStatus.Up => NetworkOperationalState.Up, OperationalStatus.Down => NetworkOperationalState.Down,
                OperationalStatus.Testing => NetworkOperationalState.Testing, OperationalStatus.Dormant => NetworkOperationalState.Dormant,
                OperationalStatus.NotPresent => NetworkOperationalState.NotPresent, OperationalStatus.LowerLayerDown => NetworkOperationalState.LowerLayerDown, _ => null
            },
            HardwareAddress = address.Length == 0 ? null : string.Join(":", address.Select(value => value.ToString("X2", CultureInfo.InvariantCulture))),
            IpAddresses = ip?.UnicastAddresses.Select(value => new IpAddressInfo(value.Address.ToString(), value.PrefixLength)).ToImmutableArray(),
            // A native provider owns DNS availability: BCL conversion can discard IPv6 scopes.
            DnsServers = native is not null ? native.DnsServers : ip?.DnsAddresses.Select(value => value.ToString()).ToImmutableArray(),
            Gateways = ip?.GatewayAddresses.Select(value => value.Address.ToString()).ToImmutableArray(),
            Routes = routes.Read(adapter.Id, token),
            MtuBytes = native?.MtuBytes ?? Mtu(adapter, ip)};
        token.ThrowIfCancellationRequested();AssertHealthy();return snapshot;
    }
    private static ulong? Mtu(BclInterface adapter, IPInterfaceProperties? ip)
    {
        if (ip is null) return null;
        // Windows BCL exposes the native ULONG as an unchecked signed int.
        var ipv4 = Try(() => adapter.Supports(NetworkInterfaceComponent.IPv4)) == true ? Try(() => (ulong)unchecked((uint)ip.GetIPv4Properties().Mtu)) : null;
        if (ipv4.HasValue) return ipv4;
        return Try(() => adapter.Supports(NetworkInterfaceComponent.IPv6)) == true ? Try(() => (ulong)unchecked((uint)ip.GetIPv6Properties().Mtu)) : null;
    }
    private static T? Try<T>(Func<T> read) where T : struct
    {try {return read();} catch (IOException) {return null;} catch (UnauthorizedAccessException) {return null;} catch (NetworkInformationException) {return null;} catch (OverflowException) {return null;}}
}
