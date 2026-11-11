using System.Runtime.CompilerServices;
[assembly: InternalsVisibleTo("DeviceReadout.Tests")]

namespace DeviceReadout.Windows;

/// <summary>Context-local generations keep removed native resources from rebinding old handles.</summary>
internal sealed class ResourceCatalog
{
    private readonly Dictionary<string, string> active = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, string> resources = [];
    private readonly HashSet<string> removed = [];
    private long sequence;
    internal IReadOnlyList<string> Update(IEnumerable<string> nativeIds)
    {
        var present = nativeIds.ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach(var pair in active.ToArray()) if (!present.Contains(pair.Key)) {removed.Add(pair.Value);active.Remove(pair.Key);}
        foreach(var nativeId in present) if (!active.ContainsKey(nativeId)) {
            var handle = (++sequence).ToString(System.Globalization.CultureInfo.InvariantCulture);
            active[nativeId] = handle;resources[handle] = nativeId;
        }
        return active.Values.ToArray();
    }
    internal string Resolve(string? handle) => handle is not null && !removed.Contains(handle) && resources.TryGetValue(handle, out var nativeId)
        ? nativeId : throw new DeviceReadoutException(ErrorCode.EntityRemoved, "The selected native resource was removed.");
    internal string? Find(string nativeId) => active.GetValueOrDefault(nativeId);
    internal void Retire(string handle)
    {
        removed.Add(handle);
        if (resources.TryGetValue(handle, out var nativeId) && active.GetValueOrDefault(nativeId) == handle) active.Remove(nativeId);
    }
}
