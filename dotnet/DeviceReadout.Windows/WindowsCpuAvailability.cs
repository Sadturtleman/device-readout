using System.ComponentModel;
using System.Buffers.Binary;
using System.Numerics;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;

namespace DeviceReadout.Windows;

internal readonly record struct WindowsProcessAffinity(ushort ActiveGroups, uint ActiveProcessors, int MaskWidth, ulong ProcessMask, ulong SystemMask);
internal interface IWindowsCpuAvailabilityPlatform
{
    WindowsProcessAffinity Affinity(CancellationToken token);
    uint[] DefaultCpuSets(CancellationToken token);
    byte[] CpuSetInformation(CancellationToken token);
}

internal sealed class WindowsCpuAvailability(IWindowsCpuAvailabilityPlatform platform)
{
    internal int? Read(CancellationToken token)
    {
        try {
            var affinity = platform.Affinity(token);token.ThrowIfCancellationRequested();
            if (affinity.ActiveGroups != 1 || affinity.MaskWidth is not (32 or 64) || affinity.ActiveProcessors > affinity.MaskWidth
                || affinity.ProcessMask == 0 || affinity.SystemMask == 0 || (affinity.ProcessMask & ~affinity.SystemMask) != 0) return null;
            var selected = platform.DefaultCpuSets(token);
            var data = platform.CpuSetInformation(token);token.ThrowIfCancellationRequested();
            if (affinity != platform.Affinity(token) || !selected.Order().SequenceEqual(platform.DefaultCpuSets(token).Order())) return null;
            if (selected.Distinct().Count() != selected.Length) return null;
            if (data.Length == 0) return selected.Length == 0 ? BitOperations.PopCount(affinity.ProcessMask) : null;
            var ids = new HashSet<uint>();var requested = selected.ToHashSet();
            ulong known = 0, allowed = 0, preferred = 0;
            for (var offset = 0; offset < data.Length;) {
                if (data.Length - offset < 8) return null;
                var size = BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(offset));
                if (size < 8 || size > data.Length - offset) return null;
                if (BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(offset + 4)) == 0) {
                    if (size < 32) return null;
                    var id = BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(offset + 8));
                    var group = BinaryPrimitives.ReadUInt16LittleEndian(data.AsSpan(offset + 12));
                    var logical = data[offset + 14];var flags = data[offset + 19];
                    if (!ids.Add(id) || logical >= 64 || (flags & 0xf0) != 0 || group != 0) return null;
                    var bit = 1UL << logical;known |= bit;
                    if ((flags & 2) == 0 || (flags & 4) != 0) {
                        allowed |= bit;if (requested.Contains(id)) preferred |= bit;
                    }
                }
                offset += (int)size;
            }
            if ((affinity.SystemMask & ~known) != 0 || requested.Any(id => !ids.Contains(id))) return null;
            allowed &= affinity.ProcessMask;preferred &= allowed;
            // A hard affinity wins over a conflicting soft CPU-set assignment. Reserved sets for another process are ignored.
            var effective = selected.Length > 0 && preferred != 0 ? preferred : allowed;
            token.ThrowIfCancellationRequested();return effective == 0 ? null : BitOperations.PopCount(effective);
        } catch (Win32Exception) {return null;}
        catch (DeviceReadoutException error) when (error.Code is ErrorCode.ReadFailed or ErrorCode.PermissionDenied or ErrorCode.UnsupportedEntity) {return null;}
    }
}

[SupportedOSPlatform("windows")]
internal sealed class WindowsCpuAvailabilityPlatform : IWindowsCpuAvailabilityPlatform
{
    public uint[] DefaultCpuSets(CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        if (GetProcessDefaultCpuSets(-1, null, 0, out var required)) return required == 0 ? [] : throw InvalidResponse();
        var error = Marshal.GetLastPInvokeError();if (error != 122) throw new Win32Exception(error);
        for (var attempt = 0; attempt < 3; attempt++) {
            token.ThrowIfCancellationRequested();if (required is 0 or > 65536) throw InvalidResponse();
            var ids = new uint[required];
            if (GetProcessDefaultCpuSets(-1, ids, (uint)ids.Length, out required)) {
                token.ThrowIfCancellationRequested();if (required > ids.Length) throw InvalidResponse();return ids[..(int)required];
            }
            error = Marshal.GetLastPInvokeError();if (error != 122) throw new Win32Exception(error);
            if (required <= ids.Length) break;
        }
        throw InvalidResponse();
    }
    public byte[] CpuSetInformation(CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        if (GetSystemCpuSetInformation(null, 0, out var required, -1, 0)) return required == 0 ? [] : throw InvalidResponse();
        var error = Marshal.GetLastPInvokeError();if (error != 122) throw new Win32Exception(error);
        for (var attempt = 0; attempt < 3; attempt++) {
            token.ThrowIfCancellationRequested();if (required is 0 or > 8 * 1024 * 1024) throw InvalidResponse();
            var data = new byte[required];
            if (GetSystemCpuSetInformation(data, (uint)data.Length, out required, -1, 0)) {
                token.ThrowIfCancellationRequested();if (required > data.Length) throw InvalidResponse();return data[..(int)required];
            }
            error = Marshal.GetLastPInvokeError();if (error != 122) throw new Win32Exception(error);
            if (required <= data.Length) break;
        }
        throw InvalidResponse();
    }
    private static DeviceReadoutException InvalidResponse() => new(ErrorCode.ReadFailed, "Invalid Windows CPU-set response.");
    public WindowsProcessAffinity Affinity(CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        var groups = GetActiveProcessorGroupCount();var count = GetActiveProcessorCount(0);
        if (groups == 0 || count == uint.MaxValue || !GetProcessAffinityMask(-1, out var process, out var system)) throw new Win32Exception(Marshal.GetLastPInvokeError());
        token.ThrowIfCancellationRequested();return new(groups, count, IntPtr.Size * 8, (ulong)process, (ulong)system);
    }
    [DllImport("kernel32.dll", SetLastError = true)] private static extern ushort GetActiveProcessorGroupCount();
    [DllImport("kernel32.dll", SetLastError = true)] private static extern uint GetActiveProcessorCount(ushort group);
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetProcessAffinityMask(nint process, out nuint processMask, out nuint systemMask);
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetProcessDefaultCpuSets(nint process, [Out] uint[]? ids, uint count, out uint required);
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetSystemCpuSetInformation([Out] byte[]? data, uint length, out uint required, nint process, uint flags);
}
