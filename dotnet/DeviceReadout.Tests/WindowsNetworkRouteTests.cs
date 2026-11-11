using System.Buffers.Binary;
using System.ComponentModel;
using System.Net;
using System.Net.Sockets;
using DeviceReadout;
using DeviceReadout.Windows;

internal static partial class WindowsNetworkTests
{
    private static async Task RouteFields()
    {
        var routes = new RouteFixture();var caller = Environment.CurrentManagedThreadId;var platform = new NetworkFixture();
        using var access = new DeviceAccess(new WindowsCollector(networkPlatform: platform, routePlatform: routes));
        Check(routes.Threads.Count == 0, "route construction must be inert");
        var target = (await access.NetworkInterfaces.List()).Single();
        var snapshot = await access.Get(target);
        var expected = new[] {
            new NetworkRoute("0.0.0.0", 0, "192.0.2.1"),
            new NetworkRoute("192.0.2.0", 24, null),
            new NetworkRoute("2001:db8:1::", 64, "fe80::1%7"),
            new NetworkRoute("::1", 128, null)
        };
        Check(snapshot.Routes?.SequenceEqual(expected) == true, "selected adapter's complete typed IPv4 and IPv6 routes");
        routes.Data = RouteTable(RouteRow(99, "198.51.100.0", 24, "198.51.100.1"));
        Check((await access.Get(target)).Routes?.Length == 0, "a complete table without matching routes is an empty list");
        routes.Data = RouteTable();
        Check((await access.Get(target)).Routes?.Length == 0, "successful empty route table");
        await using (var stream = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(target).GetAsyncEnumerator()) {
            Check(await stream.MoveNextAsync() && stream.Current.Routes?.Length == 0, "initial empty route snapshot");
            routes.Data = RouteTable(RouteRow(42, "203.0.113.0", 24, "192.0.2.1"));platform.Signal();
            Check(await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(2)) && stream.Current.Routes?.Single().Destination == "203.0.113.0", "native change notification refreshes the route field");
        }
        Check(routes.Threads.Distinct().Count() == 1 && !routes.Threads.Contains(caller), "route lookup and native table read stay on the collection worker");
    }
    private static async Task ActualRoutes()
    {
        using var access = WindowsDeviceAccess.Create();var targets = await access.NetworkInterfaces.List();
        var all = new List<NetworkRoute>();var readable = 0;NetworkInterfaceSnapshot? loopback = null;
        foreach (var target in targets) {
            var snapshot = await access.Get(target);
            if (snapshot.Routes is { } routes) {readable++;all.AddRange(routes);}
            if (snapshot.InterfaceType == DeviceReadout.NetworkInterfaceType.Loopback) loopback = snapshot;
        }
        Check(loopback?.Routes?.Contains(new NetworkRoute("127.0.0.0", 8, null)) == true, "native IPv4 loopback prefix");
        Check(loopback?.Routes?.Contains(new NetworkRoute("::1", 128, null)) == true, "native IPv6 loopback host route");
        var ipv4 = all.Count(route => IPAddress.Parse(route.Destination).AddressFamily == AddressFamily.InterNetwork);
        var ipv6 = all.Count(route => IPAddress.Parse(route.Destination).AddressFamily == AddressFamily.InterNetworkV6);
        Check(readable > 0 && ipv4 > 0 && ipv6 > 0, "native selected-interface route lists");
        Console.WriteLine($"Native Windows routes: {readable}/{targets.Length} readable interface tables, {all.Count} routes, IPv4={ipv4}, IPv6={ipv6}; loopback IPv4/IPv6 prefixes and absent gateways verified.");
    }
    private static async Task RouteFailures()
    {
        var routes = new RouteFixture();using var access = new DeviceAccess(new WindowsCollector(networkPlatform: new NetworkFixture(), routePlatform: routes));
        var target = (await access.NetworkInterfaces.List()).Single();var valid = routes.Data;
        async Task Missing() {var snapshot = await access.Get(target);Check(snapshot.Routes is null && snapshot.Name == "Fixture Ethernet", "route failure must preserve independent network fields");}
        var unknown = RouteRow(42, "192.0.2.0", 24, "192.0.2.1");BinaryPrimitives.WriteUInt16LittleEndian(unknown.AsSpan(12), 99);
        foreach (var data in new[] {new byte[7], valid[..^1], RouteTable(RouteRow(42, "192.0.2.0", 33, "192.0.2.1")),
            RouteTable(RouteRow(42, "192.0.2.0", 24, "fe80::1")), RouteTable(unknown)}) {
            routes.Data = data;await Missing();
        }
        routes.Data = valid;routes.Failure = new Win32Exception(5);await Missing();routes.Failure = null;
        routes.ChangeLuid = true;await Missing();routes.ChangeLuid = false;routes.InterfaceLuid = 42;
        routes.Data = RouteTable(RouteRow(42, "fe80::", 64, "::%7"));
        var scoped = await access.Get(target);
        Check(scoped.Routes?.Single().Gateway is null && scoped.Routes?.Single().Destination == "fe80::", "unspecified address has no gateway even when a native scope ID is present");
    }
    private sealed class RouteFixture : IWindowsRoutePlatform
    {
        internal ulong InterfaceLuid = 42;
        internal byte[] Data = RouteTable(
            RouteRow(42, "0.0.0.0", 0, "192.0.2.1"), RouteRow(99, "198.51.100.0", 24, "198.51.100.1"),
            RouteRow(42, "192.0.2.0", 24, "0.0.0.0"), RouteRow(42, "2001:db8:1::", 64, "fe80::1%7"), RouteRow(42, "::1", 128, "::"));
        internal readonly List<int> Threads = [];
        internal Exception? Failure;
        internal bool ChangeLuid;
        public ulong Luid(Guid id, CancellationToken token) {Threads.Add(Environment.CurrentManagedThreadId);token.ThrowIfCancellationRequested();return InterfaceLuid;}
        public byte[] Table(CancellationToken token) {Threads.Add(Environment.CurrentManagedThreadId);token.ThrowIfCancellationRequested();if (Failure is not null) throw Failure;if (ChangeLuid) InterfaceLuid = 99;return Data.ToArray();}
    }
    private static byte[] RouteTable(params byte[][] rows)
    {
        var result = new byte[8 + rows.Length * 104];BinaryPrimitives.WriteUInt32LittleEndian(result, (uint)rows.Length);
        for (var index = 0; index < rows.Length; index++) rows[index].CopyTo(result, 8 + index * 104);
        return result;
    }
    private static byte[] RouteRow(ulong luid, string destination, byte prefix, string gateway)
    {
        var row = new byte[104];BinaryPrimitives.WriteUInt64LittleEndian(row, luid);
        Sockaddr(row.AsSpan(12, 28), IPAddress.Parse(destination));row[40] = prefix;
        Sockaddr(row.AsSpan(44, 28), IPAddress.Parse(gateway));return row;
    }
    private static void Sockaddr(Span<byte> output, IPAddress address)
    {
        var bytes = address.GetAddressBytes();BinaryPrimitives.WriteUInt16LittleEndian(output, bytes.Length == 4 ? (ushort)2 : (ushort)23);
        bytes.CopyTo(output[(bytes.Length == 4 ? 4 : 8)..]);
        if (bytes.Length == 16) BinaryPrimitives.WriteUInt32LittleEndian(output[24..], checked((uint)address.ScopeId));
    }
}
