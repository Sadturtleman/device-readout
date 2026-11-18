using System.Runtime.InteropServices;
using System.Collections.Immutable;
using System.Net;
using System.Text.Json;
using DeviceReadout;
using DeviceReadout.Windows;

internal static partial class WindowsNetworkTests
{
    private static async Task ActualNdisInventory()
    {
        using var reference = new NativeNetworkReference();
        var names = reference.Names();
        using var access = WindowsDeviceAccess.Create();
        var targets = await access.NetworkInterfaces.List();
        Check(targets.Length == names.Length, $"Complete NDIS inventory: SDK={targets.Length}, Windows SDK reference={names.Length}.");
        var snapshots = new List<NetworkInterfaceSnapshot>();
        foreach (var target in targets) snapshots.Add(await access.Get(target));
        Check(snapshots.Select(value => value.Name).Order().SequenceEqual(names.Order()), "All native NDIS names remain readable through public handles.");
        Check((await access.NetworkInterfaces.List()).SequenceEqual(targets), "Stable inventory retains the same handles.");
        Console.WriteLine($"NDIS inventory: {targets.Length} interfaces agree with the independent Windows SDK reference.");
    }
    private static async Task ActualNdisFields()
    {
        using var reference = new NativeNetworkReference();
        var expected = reference.Read();
        using var access = WindowsDeviceAccess.Create();
        var actual = new List<NetworkInterfaceSnapshot>();
        foreach (var target in await access.NetworkInterfaces.List()) actual.Add(await access.Get(target));
        Check(actual.Count == expected.Length, "Full inventory must remain readable.");
        var failures = new List<string>();
        string Ordered<T>(ImmutableArray<T>? values) => values is null ? "null" : string.Join("|", values.Value.Select(value => JsonSerializer.Serialize(value)).Order());
        for (var index = 0; index < expected.Length; index++) {
            var item = expected[index];var value = actual.Single(snapshot => snapshot.Name == item.Name);
            void Same(bool same, string field) {if (!same) failures.Add($"{index}:{field}");}
            Same(value.InterfaceType == item.InterfaceType, "type");
            Same(value.OperationalState == item.OperationalState, "state");
            Same(value.HardwareAddress == item.HardwareAddress, "hardware");
            Same(value.MtuBytes == item.MtuBytes, $"mtu({value.MtuBytes?.ToString() ?? "null"}/{item.MtuBytes})");
            Same(Ordered(value.IpAddresses) == Ordered(item.IpAddresses), "addresses");
            Same(Ordered(value.DnsServers) == Ordered(item.DnsServers), $"dns({value.DnsServers?.Length}/{item.DnsServers?.Length};scoped={value.DnsServers?.Count(address => address.Contains('%'))}/{item.DnsServers?.Count(address => address.Contains('%'))};siteLocal={value.DnsServers?.Count(address => IPAddress.Parse(address).IsIPv6SiteLocal)}/{item.DnsServers?.Count(address => IPAddress.Parse(address).IsIPv6SiteLocal)})");
            Same(Ordered(value.Gateways) == Ordered(item.Gateways), "gateways");
            Same(Ordered(value.Routes) == Ordered(item.Routes), "routes");
        }
        Check(failures.Count == 0, "Native NDIS field differences: " + string.Join(", ", failures));
        Console.WriteLine($"NDIS fields: {actual.Count} interfaces, nine fields and {actual.Sum(value => value.Routes?.Length ?? 0)} routes agree with the independent native reference.");
    }
    private sealed class NativeNetworkReference : IDisposable
    {
        private readonly nint library;
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate uint CountCall();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate nint TextCall(uint item, uint field, uint index);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate ulong NumberCall(uint item, uint field, uint index);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void FreeCall();
        internal NativeNetworkReference()
        {
            var root = new DirectoryInfo(AppContext.BaseDirectory);
            while (root is not null && !File.Exists(Path.Combine(root.FullName, "tools/windows-memory-probe/CMakeLists.txt"))) root = root.Parent;
            if (root is null) throw new Exception("Could not locate the independent native network reference.");
            library = NativeLibrary.Load(Path.Combine(root.FullName, ".tools/windows-memory-probe/Release/device_readout_memory_probe.dll"));
        }
        private T Function<T>(string name) where T : Delegate => Marshal.GetDelegateForFunctionPointer<T>(NativeLibrary.GetExport(library, name));
        internal string?[] Names()
        {
            Check(Function<CountCall>("readout_probe_network_refresh")() == 0, "Native reference query succeeds.");
            var count = Function<CountCall>("readout_probe_network_count")();
            var text = Function<TextCall>("readout_probe_network_text");
            return Enumerable.Range(0, checked((int)count)).Select(index => Marshal.PtrToStringUni(text((uint)index, 0, 0))).ToArray();
        }
        internal NetworkInterfaceSnapshot[] Read()
        {
            var names = Names();
            var number = Function<NumberCall>("readout_probe_network_number");
            var text = Function<TextCall>("readout_probe_network_text");
            string? Text(uint item, uint field, uint index = 0) => Marshal.PtrToStringUni(text(item, field, index));
            string Address(uint item, uint field, uint index) => IPAddress.Parse(Text(item, field, index)!).ToString();
            IEnumerable<uint> Indices(uint item, uint field) => Enumerable.Range(0, checked((int)number(item, field, 0))).Select(index => (uint)index);
            return names.Select((name, index) => {
                var item = (uint)index;
                return new NetworkInterfaceSnapshot {
                    Name = name, HardwareAddress = Text(item, 1), MtuBytes = number(item, 2, 0),
                    InterfaceType = number(item, 0, 0) switch {
                        6 or 26 or 62 or 69 or 117 => DeviceReadout.NetworkInterfaceType.Ethernet,
                        71 => DeviceReadout.NetworkInterfaceType.Wifi, 24 => DeviceReadout.NetworkInterfaceType.Loopback,
                        131 => DeviceReadout.NetworkInterfaceType.Tunnel, 23 => DeviceReadout.NetworkInterfaceType.Ppp,
                        243 or 244 => DeviceReadout.NetworkInterfaceType.Cellular, 209 => DeviceReadout.NetworkInterfaceType.Bridge, _ => null
                    },
                    OperationalState = number(item, 1, 0) switch {
                        1 => NetworkOperationalState.Up, 2 => NetworkOperationalState.Down, 3 => NetworkOperationalState.Testing,
                        5 => NetworkOperationalState.Dormant, 6 => NetworkOperationalState.NotPresent, 7 => NetworkOperationalState.LowerLayerDown, _ => null
                    },
                    IpAddresses = Indices(item, 3).Select(n => new IpAddressInfo(Address(item, 2, n), checked((int)number(item, 7, n)))).ToImmutableArray(),
                    DnsServers = Indices(item, 4).Select(n => Address(item, 3, n)).ToImmutableArray(),
                    Gateways = Indices(item, 5).Select(n => Address(item, 4, n)).ToImmutableArray(),
                    Routes = Indices(item, 6).Select(n => {
                        var gateway = Address(item, 6, n);
                        return new NetworkRoute(Address(item, 5, n), checked((int)number(item, 8, n)), IPAddress.Parse(gateway).GetAddressBytes().All(value => value == 0) ? null : gateway);
                    }).ToImmutableArray()
                };
            }).ToArray();
        }
        public void Dispose() {Function<FreeCall>("readout_probe_network_free")();NativeLibrary.Free(library);}
    }
}
