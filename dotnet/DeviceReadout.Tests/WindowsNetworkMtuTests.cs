using System.Net.NetworkInformation;
using System.Net;
using DeviceReadout;
using DeviceReadout.Windows;

internal static partial class WindowsNetworkTests
{
    private static async Task MtuFields()
    {
        var adapter = new AdapterFixture {Ipv4 = false, Properties = new IpPropertiesFixture {Six = new Ipv6PropertiesFixture(1280)}};
        var platform = new NetworkFixture {Adapters = [adapter]};
        using var access = new DeviceAccess(new WindowsCollector(networkPlatform: platform));
        var target = (await access.NetworkInterfaces.List()).Single();
        Check((await access.Get(target)).MtuBytes == 1280, "IPv6-only adapter's MTU");
        adapter.Ipv4 = true;adapter.Properties = new IpPropertiesFixture {Six = new Ipv6PropertiesFixture(1500)};
        Check((await access.Get(target)).MtuBytes == 1500, "unavailable IPv4 metadata does not discard readable IPv6 MTU");
        adapter.Properties = new IpPropertiesFixture {Four = new Ipv4PropertiesFixture(9000), Six = new Ipv6PropertiesFixture(9000)};
        Check((await access.Get(target)).MtuBytes == 9000, "dual-stack native MTU");
        adapter.Properties = new IpPropertiesFixture {Four = new Ipv4PropertiesFixture(0)};
        Check((await access.Get(target)).MtuBytes == 0, "reported zero remains zero");
        adapter.Properties = new IpPropertiesFixture {Four = new Ipv4PropertiesFixture(-1), Six = new Ipv6PropertiesFixture(-1)};
        Check((await access.Get(target)).MtuBytes == uint.MaxValue, "Windows BCL preserves ULONG MTU bits in its signed int result");
        adapter.Properties = new IpPropertiesFixture();
        var unavailable = await access.Get(target);
        Check(unavailable.MtuBytes is null && unavailable.IpAddresses?.Length == 0 && unavailable.DnsServers?.Length == 0
            && unavailable.Gateways?.Length == 0 && unavailable.Name == "Fixture Ethernet", "unavailable MTU does not discard other fields or known empty lists");
    }
    private sealed class IpPropertiesFixture : IPInterfaceProperties
    {
        internal IPv4InterfaceProperties? Four;
        internal IPv6InterfaceProperties? Six;
        internal IPAddressCollection? Dns;
        public override bool IsDnsEnabled => true;
        public override string DnsSuffix => "";
        public override bool IsDynamicDnsEnabled => false;
        public override UnicastIPAddressInformationCollection UnicastAddresses => new EmptyUnicast();
        public override MulticastIPAddressInformationCollection MulticastAddresses => new EmptyMulticast();
        public override IPAddressInformationCollection AnycastAddresses => throw new NetworkInformationException(50);
        public override IPAddressCollection DnsAddresses => Dns ?? new EmptyIps();
        public override GatewayIPAddressInformationCollection GatewayAddresses => new EmptyGateways();
        public override IPAddressCollection DhcpServerAddresses => new EmptyIps();
        public override IPAddressCollection WinsServersAddresses => new EmptyIps();
        public override IPv4InterfaceProperties GetIPv4Properties() => Four ?? throw new NetworkInformationException(50);
        public override IPv6InterfaceProperties GetIPv6Properties() => Six ?? throw new NetworkInformationException(50);
    }
    private sealed class Ipv4PropertiesFixture(int mtu) : IPv4InterfaceProperties
    {
        public override bool UsesWins => false;
        public override bool IsDhcpEnabled => false;
        public override bool IsAutomaticPrivateAddressingActive => false;
        public override bool IsAutomaticPrivateAddressingEnabled => false;
        public override int Index => 7;
        public override bool IsForwardingEnabled => false;
        public override int Mtu => mtu;
    }
    private sealed class Ipv6PropertiesFixture(int mtu) : IPv6InterfaceProperties
    {public override int Index => 7;public override int Mtu => mtu;}
    private sealed class EmptyUnicast : UnicastIPAddressInformationCollection
    {public override int Count => 0;public override IEnumerator<UnicastIPAddressInformation> GetEnumerator() => Enumerable.Empty<UnicastIPAddressInformation>().GetEnumerator();}
    private sealed class EmptyMulticast : MulticastIPAddressInformationCollection;
    private sealed class EmptyIps : IPAddressCollection
    {public override int Count => 0;public override IEnumerator<IPAddress> GetEnumerator() => Enumerable.Empty<IPAddress>().GetEnumerator();}
    private sealed class IpListFixture(params IPAddress[] addresses) : IPAddressCollection
    {public override int Count => addresses.Length;public override IEnumerator<IPAddress> GetEnumerator() => addresses.AsEnumerable().GetEnumerator();}
    private sealed class EmptyGateways : GatewayIPAddressInformationCollection
    {public override int Count => 0;public override IEnumerator<GatewayIPAddressInformation> GetEnumerator() => Enumerable.Empty<GatewayIPAddressInformation>().GetEnumerator();}
}
