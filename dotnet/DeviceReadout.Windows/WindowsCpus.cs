using System.Buffers.Binary;
using System.ComponentModel;
using System.Globalization;

namespace DeviceReadout.Windows;

internal sealed class WindowsCpus(IWindowsCpuPlatform platform)
{
    private readonly ResourceCatalog catalog = new();
    private sealed record Topology(SortedDictionary<int, CpuCoreSnapshot> Logical, int Cores, int? Packages);
    internal IReadOnlyList<string> List(CancellationToken token)
    {
        var topology = Refresh(token);
        return topology.Logical.Keys.Select(index => catalog.Find(Key(index))!).ToArray();
    }
    internal (int Logical, int Physical, int? Packages) Counts(CancellationToken token)
    {
        var topology = Refresh(token);return (topology.Logical.Count, topology.Cores, topology.Packages);
    }
    internal CpuCoreSnapshot Read(string? handle, CancellationToken token)
    {
        var key = catalog.Resolve(handle);var topology = Refresh(token);_ = catalog.Resolve(handle);
        var index = int.Parse(key, CultureInfo.InvariantCulture);var snapshot = topology.Logical[index];
        // The documented power record has no group field. Only map an unambiguous group-zero inventory.
        var count = topology.Logical.Count;
        if (topology.Logical.Keys.First() != 0 || topology.Logical.Keys.Last() != count - 1 || count > 64) return snapshot;
        byte[]? power;
        try {power = platform.PowerInformation(count, token);}
        catch (Win32Exception) {return snapshot;}
        token.ThrowIfCancellationRequested();
        if (power is null || power.Length != count * 24) return snapshot;
        var numbers = new HashSet<uint>();(uint Current, uint Maximum)? clocks = null;
        for (var offset = 0; offset < power.Length; offset += 24) {
            var number = BinaryPrimitives.ReadUInt32LittleEndian(power.AsSpan(offset));
            if (number >= count || !numbers.Add(number)) return snapshot;
            if (number == index) clocks = (BinaryPrimitives.ReadUInt32LittleEndian(power.AsSpan(offset + 8)), BinaryPrimitives.ReadUInt32LittleEndian(power.AsSpan(offset + 4)));
        }
        return snapshot with {CurrentClockHz = clocks?.Current * 1_000_000.0, MaximumClockHz = clocks?.Maximum * 1_000_000.0};
    }
    internal EntityCapabilities Capabilities(string? handle)
    {
        if (!platform.AffinityMasksReliable) return new(false, false);
        if (handle is null) return new(true, true);
        try {_ = catalog.Resolve(handle);return new(true, true);} catch (DeviceReadoutException) {return new(false, false);}
    }
    private Topology Refresh(CancellationToken token)
    {
        if (!platform.AffinityMasksReliable) throw new DeviceReadoutException(ErrorCode.UnsupportedEntity, "Native affinity masks cannot identify all logical processors in this process architecture.");
        try {
            var bytes = platform.Topology(token);token.ThrowIfCancellationRequested();
            var topology = Parse(bytes, platform.PointerSize);
            catalog.Update(topology.Logical.Keys.Select(Key));return topology;
        } catch (Win32Exception error) {
            throw new DeviceReadoutException(error.NativeErrorCode == 5 ? ErrorCode.PermissionDenied : ErrorCode.ReadFailed,
                $"Windows CPU topology query failed (Win32 {error.NativeErrorCode}).", error);
        }
    }
    private static Topology Parse(byte[] bytes, int pointerSize)
    {
        if (pointerSize is not (4 or 8)) throw Malformed();
        var cores = new List<HashSet<int>>();var packages = new List<HashSet<int>>();
        for (var offset = 0; offset < bytes.Length;) {
            if (bytes.Length - offset < 8) throw Malformed();
            var kind = BinaryPrimitives.ReadUInt32LittleEndian(bytes.AsSpan(offset));
            var size = BinaryPrimitives.ReadUInt32LittleEndian(bytes.AsSpan(offset + 4));
            if (size < 8 || size > bytes.Length - offset) throw Malformed();
            if (kind is 0 or 3) {
                if (size < 32) throw Malformed();
                var groupCount = BinaryPrimitives.ReadUInt16LittleEndian(bytes.AsSpan(offset + 30));
                var stride = pointerSize + 8;
                if (groupCount == 0 || (kind == 0 && groupCount != 1) || 32 + groupCount * stride > size) throw Malformed();
                var members = new HashSet<int>();var groups = new HashSet<ushort>();
                for (var index = 0; index < groupCount; index++) {
                    var position = offset + 32 + index * stride;
                    var mask = pointerSize == 8 ? BinaryPrimitives.ReadUInt64LittleEndian(bytes.AsSpan(position)) : BinaryPrimitives.ReadUInt32LittleEndian(bytes.AsSpan(position));
                    var group = BinaryPrimitives.ReadUInt16LittleEndian(bytes.AsSpan(position + pointerSize));
                    if (mask == 0 || !groups.Add(group)) throw Malformed();
                    for (var bit = 0; bit < pointerSize * 8; bit++) if ((mask & (1UL << bit)) != 0) members.Add(group * 64 + bit);
                }
                (kind == 0 ? cores : packages).Add(members);
            }
            offset += (int)size;
        }
        if (cores.Count == 0) throw Malformed();
        cores = cores.OrderBy(core => core.Min()).ToList();packages = packages.OrderBy(package => package.Min()).ToList();
        var logical = new SortedDictionary<int, CpuCoreSnapshot>();
        for (var core = 0; core < cores.Count; core++) foreach(var index in cores[core]) {
            if (!logical.TryAdd(index, new CpuCoreSnapshot {LogicalIndex = index, CoreIndex = core, Online = true})) throw Malformed();
        }
        for (var package = 0; package < packages.Count; package++) foreach(var index in packages[package]) {
            if (!logical.TryGetValue(index, out var value) || value.PackageIndex is not null) throw Malformed();
            logical[index] = value with {PackageIndex = package};
        }
        if (packages.Count > 0 && (logical.Values.Any(value => value.PackageIndex is null)
            || cores.Any(core => core.Select(index => logical[index].PackageIndex).Distinct().Count() != 1))) throw Malformed();
        return new(logical, cores.Count, packages.Count == 0 ? null : packages.Count);
    }
    private static string Key(int logical) => logical.ToString(CultureInfo.InvariantCulture);
    private static DeviceReadoutException Malformed() => new(ErrorCode.ReadFailed, "Invalid Windows CPU topology response.");
}
