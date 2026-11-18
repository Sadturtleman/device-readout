using System.Buffers.Binary;
using System.Collections.Immutable;
using System.Net;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Text;

namespace DeviceReadout.Windows;

internal interface IWindowsNetworkPropertiesPlatform
{
    uint Read(nint buffer, ref uint size);
}

internal sealed class WindowsNetworkProperties(IWindowsNetworkPropertiesPlatform platform)
{
    private const int Maximum = 8 * 1024 * 1024;
    internal NetworkInterfaceSnapshot? Read(string adapterId, CancellationToken token)
    {
        // IP_ADAPTER_ADDRESSES_LH pointer layout below is for 64-bit processes.
        if (IntPtr.Size != 8) return null;
        var capacity = 15 * 1024;
        try {
            for (var attempt = 0; attempt < 3; attempt++) {
                token.ThrowIfCancellationRequested();
                var buffer = Marshal.AllocHGlobal(capacity);
                try {
                    var size = (uint)capacity;
                    var result = platform.Read(buffer, ref size);
                    token.ThrowIfCancellationRequested();
                    if (result == 111) {
                        if (size <= capacity || size > Maximum) return null;
                        capacity = (int)size;continue;
                    }
                    if (result != 0 || size == 0 || size > capacity) return null;
                    var bytes = new byte[(int)size];Marshal.Copy(buffer, bytes, 0, bytes.Length);
                    return Decode(bytes, (ulong)buffer, adapterId, token);
                } finally {Marshal.FreeHGlobal(buffer);}
            }
        } catch (InvalidDataException) {return null;}
        return null;
    }

    private static NetworkInterfaceSnapshot? Decode(byte[] bytes, ulong start, string adapterId, CancellationToken token)
    {
        int Offset(ulong address, uint length) {
            if (address < start || address - start > (ulong)bytes.Length || length > (ulong)bytes.Length - (address - start))
                throw new InvalidDataException("Network pointer is outside its owned buffer.");
            return (int)(address - start);
        }
        uint UInt(int at) => BinaryPrimitives.ReadUInt32LittleEndian(bytes.AsSpan(at));
        ulong Pointer(int at) => BinaryPrimitives.ReadUInt64LittleEndian(bytes.AsSpan(at));
        string Identity(ulong address) {
            var at = Offset(address, 1);var limit = Math.Min(bytes.Length - at, 1024);
            var length = Array.IndexOf(bytes, (byte)0, at, limit) - at;
            if (length <= 0) throw new InvalidDataException("Invalid network adapter identity.");
            return Encoding.Latin1.GetString(bytes, at, length);
        }
        ImmutableArray<string>? Dns(ulong first) {
            try {
                var result = ImmutableArray.CreateBuilder<string>();var seen = new HashSet<ulong>();
                for (var current = first; current != 0;) {
                    token.ThrowIfCancellationRequested();
                    if (!seen.Add(current) || seen.Count > 65536) throw new InvalidDataException("Invalid DNS chain.");
                    var at = Offset(current, 32);var length = UInt(at);
                    if (length < 32) throw new InvalidDataException("Truncated DNS node.");
                    _ = Offset(current, length);
                    var size = UInt(at + 24);var socket = Offset(Pointer(at + 16), size);
                    if (size < 2) throw new InvalidDataException("Truncated DNS address.");
                    var family = BinaryPrimitives.ReadUInt16LittleEndian(bytes.AsSpan(socket));
                    result.Add(family switch {
                        2 when size >= 16 => new IPAddress(bytes.AsSpan(socket + 4, 4)).ToString(),
                        23 when size >= 28 => new IPAddress(bytes.AsSpan(socket + 8, 16), UInt(socket + 24)).ToString(),
                        _ => throw new InvalidDataException("Unknown DNS address family.")
                    });
                    current = Pointer(at + 8);
                }
                return result.ToImmutable();
            } catch (InvalidDataException) {return null;}
        }
        NetworkInterfaceSnapshot? snapshot = null;
        var visited = new HashSet<ulong>();var identities = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        for (var current = start; current != 0;) {
            token.ThrowIfCancellationRequested();
            if (!visited.Add(current) || visited.Count > 65536) throw new InvalidDataException("Invalid network inventory chain.");
            var at = Offset(current, 100);var length = UInt(at);
            if (length < 100) throw new InvalidDataException("Truncated network adapter.");
            _ = Offset(current, length);
            var id = Identity(Pointer(at + 16));
            if (!identities.Add(id)) throw new InvalidDataException("Duplicate network adapter identity.");
            if (string.Equals(id, adapterId, StringComparison.OrdinalIgnoreCase)) snapshot = new() {MtuBytes = UInt(at + 96), DnsServers = Dns(Pointer(at + 48))};
            current = Pointer(at + 8);
        }
        return snapshot;
    }
}

[SupportedOSPlatform("windows")]
internal sealed class WindowsNetworkPropertiesPlatform : IWindowsNetworkPropertiesPlatform
{
    public uint Read(nint buffer, ref uint size) => GetAdaptersAddresses(0, 2 | 4 | 128 | 256, 0, buffer, ref size);
    [DllImport("iphlpapi.dll")] private static extern uint GetAdaptersAddresses(uint family, uint flags, nint reserved, nint buffer, ref uint size);
}
