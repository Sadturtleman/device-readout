using System.Collections.Immutable;
namespace DeviceReadout;

public sealed class EntityCollection<T> where T : DeviceSnapshot
{
    private readonly DeviceAccess access;
    private readonly Entity<T> kind;
    internal EntityCollection(DeviceAccess access, Entity<T> kind) => (this.access, this.kind) = (access, kind);
    public Task<ImmutableArray<Entity<T>>> List(CancellationToken token = default) => access.List(kind, token);
    public Task<Entity<T>?> Current(CancellationToken token = default) => access.Current(kind, token);
}
public sealed class SensorCollection
{
    private readonly DeviceAccess access;
    internal SensorCollection(DeviceAccess access) => this.access = access;
    public Task<ImmutableArray<Entity<T>>> List<T>(Entity<T> kind, CancellationToken token = default) where T : DeviceSnapshot
        => kind.Mode != EntityMode.State ? access.List(kind, token)
            : throw new DeviceReadoutException(ErrorCode.InvalidConfiguration, "Expected a sensor kind.");
}
public sealed class CapabilityAccess
{
    private readonly DeviceAccess access;
    internal CapabilityAccess(DeviceAccess access) => this.access = access;
    public Task<EntityCapabilities> Get<T>(Entity<T> entity, CancellationToken token = default) where T : DeviceSnapshot
        => access.GetCapabilities(entity, token);
}
