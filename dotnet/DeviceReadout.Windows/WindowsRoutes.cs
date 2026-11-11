using System.Buffers.Binary;
using System.Collections.Immutable;
using System.ComponentModel;
using System.Net;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;

namespace DeviceReadout.Windows;

internal interface IWindowsRoutePlatform
{
    ulong Luid(Guid id, CancellationToken token);
    byte[] Table(CancellationToken token);
}

internal sealed class WindowsRoutes(IWindowsRoutePlatform platform)
{
    internal ImmutableArray<NetworkRoute>? Read(string adapterId, CancellationToken token)
    {
        if (!Guid.TryParse(adapterId, out var guid)) return null;
        try {
            var luid = platform.Luid(guid, token);if (luid == 0) return null;
            var table = platform.Table(token);token.ThrowIfCancellationRequested();
            if (luid != platform.Luid(guid, token)) return null;
            if (table.Length < 8 || (table.Length - 8) % 104 != 0 || BinaryPrimitives.ReadUInt32LittleEndian(table) != (table.Length - 8) / 104) return null;
            var routes = ImmutableArray.CreateBuilder<NetworkRoute>();
            for (var offset = 8; offset < table.Length; offset += 104) {
                token.ThrowIfCancellationRequested();var row = table.AsSpan(offset, 104);
                if (BinaryPrimitives.ReadUInt64LittleEndian(row) != luid) continue;
                var destination = Address(row.Slice(12, 28));var gateway = Address(row.Slice(44, 28));
                if (destination is null || gateway is null || destination.AddressFamily != gateway.AddressFamily) return null;
                var prefix = row[40];if (prefix > (destination.GetAddressBytes().Length == 4 ? 32 : 128)) return null;
                var local = gateway.GetAddressBytes().All(value => value == 0);
                routes.Add(new(destination.ToString(), prefix, local ? null : gateway.ToString()));
            }
            return routes.ToImmutable();
        } catch (Win32Exception) {return null;}
        catch (DeviceReadoutException error) when (error.Code is ErrorCode.ReadFailed or ErrorCode.PermissionDenied or ErrorCode.UnsupportedEntity) {return null;}
    }
    private static IPAddress? Address(ReadOnlySpan<byte> native)
        => BinaryPrimitives.ReadUInt16LittleEndian(native) switch {
            2 => new IPAddress(native.Slice(4, 4)),
            23 => new IPAddress(native.Slice(8, 16), BinaryPrimitives.ReadUInt32LittleEndian(native[24..])),
            _ => null
        };
}

[SupportedOSPlatform("windows")]
internal sealed class WindowsRoutePlatform : IWindowsRoutePlatform
{
    public ulong Luid(Guid id, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();var result = ConvertInterfaceGuidToLuid(ref id, out var luid);
        token.ThrowIfCancellationRequested();if (result != 0) throw new Win32Exception((int)result);return luid;
    }
    public byte[] Table(CancellationToken token)
    {
        token.ThrowIfCancellationRequested();var result = GetIpForwardTable2(0, out var table);
        try {
            token.ThrowIfCancellationRequested();
            if (result == 1168) return new byte[8]; // ERROR_NOT_FOUND: no matching IP routes.
            if (result != 0) throw new Win32Exception((int)result);
            if (table == 0) throw InvalidTable();
            var count = (uint)Marshal.ReadInt32(table);
            if (count == 0) return new byte[8];
            if (count > (8 * 1024 * 1024 - 8) / 104) throw InvalidTable();
            var bytes = new byte[8 + (int)count * 104];Marshal.Copy(table, bytes, 0, bytes.Length);
            token.ThrowIfCancellationRequested();return bytes;
        } finally {if (table != 0) FreeMibTable(table);}
    }
    private static DeviceReadoutException InvalidTable() => new(ErrorCode.ReadFailed, "Invalid Windows route table.");
    [DllImport("iphlpapi.dll")] private static extern uint ConvertInterfaceGuidToLuid(ref Guid id, out ulong luid);
    [DllImport("iphlpapi.dll")] private static extern uint GetIpForwardTable2(ushort family, out nint table);
    [DllImport("iphlpapi.dll")] private static extern void FreeMibTable(nint table);
}
