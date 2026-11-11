namespace DeviceReadout;

public abstract record DeviceSnapshot
{
    public DateTimeOffset CollectedAt { get; init; }
}
public readonly record struct Size<T>(T Width, T Height);
public readonly record struct Rect(double X, double Y, double Width, double Height);
public readonly record struct Insets(double Top, double Right, double Bottom, double Left);
public readonly record struct Vector3(double X, double Y, double Z);
public readonly record struct Quaternion(double X, double Y, double Z, double W);
public sealed record DisplayMode(Size<int>? PixelSize, double? RefreshRateHz);
public sealed record IpAddressInfo(string Address, int? PrefixLength);
public sealed record NetworkRoute(string Destination, int? PrefixLength, string? Gateway);

public abstract record ThermalState
{
    private ThermalState() { }
    public sealed record Android(AndroidThermalState Value) : ThermalState;
    public sealed record Apple(AppleThermalState Value) : ThermalState;
}

public enum ErrorCode { UnsupportedEntity, PermissionDenied, EntityRemoved, ReadTimeout, ReadFailed, InvalidConfiguration }
public sealed class DeviceReadoutException(ErrorCode code, string message, Exception? inner = null) : Exception(message, inner)
{
    public ErrorCode Code { get; } = code;
}
public enum EntityMode { State, Sample, Event }
public readonly record struct EntityAddress(EntityKind Kind, string? TargetId = null);
public sealed record EntityCapabilities(bool? Readable, bool? Watchable);

public sealed class Entity<T> : IEquatable<Entity<T>> where T : DeviceSnapshot
{
    public EntityKind Kind { get; }
    internal EntityMode Mode { get; }
    internal bool RequiresTarget { get; }
    internal object? Owner { get; }
    internal string? TargetId { get; }
    internal Entity(EntityKind kind, bool requiresTarget, EntityMode mode, object? owner = null, string? targetId = null)
        => (Kind, RequiresTarget, Mode, Owner, TargetId) = (kind, requiresTarget, mode, owner, targetId);
    internal EntityAddress Address(object owner, bool collection = false)
    {
        if (Owner is not null && !ReferenceEquals(Owner, owner))
            throw new DeviceReadoutException(ErrorCode.InvalidConfiguration, "Entity handle belongs to another DeviceAccess context.");
        if (RequiresTarget && TargetId is null && !collection)
            throw new DeviceReadoutException(ErrorCode.InvalidConfiguration, "Discover or observe a target before reading this entity.");
        return new(Kind, TargetId);
    }
    internal Entity<T> Bind(object owner, string id) => new(Kind, true, Mode, owner, id);
    public bool Equals(Entity<T>? other) => other is not null && Kind == other.Kind && Mode == other.Mode
        && RequiresTarget == other.RequiresTarget && ReferenceEquals(Owner, other.Owner)
        && string.Equals(TargetId, other.TargetId, StringComparison.Ordinal);
    public override bool Equals(object? other) => other is Entity<T> entity && Equals(entity);
    public override int GetHashCode() => HashCode.Combine(Kind, Mode, RequiresTarget,
        Owner is null ? 0 : System.Runtime.CompilerServices.RuntimeHelpers.GetHashCode(Owner), TargetId);
    public static bool operator ==(Entity<T>? left, Entity<T>? right) => ReferenceEquals(left, right) || (left is not null && left.Equals(right));
    public static bool operator !=(Entity<T>? left, Entity<T>? right) => !(left == right);
}

public sealed record SensorSamplingRate
{
    public double? Hertz { get; }
    private SensorSamplingRate(double? hertz) => Hertz = hertz;
    public static SensorSamplingRate PlatformDefault { get; } = new((double?)null);
    public static SensorSamplingRate AtHertz(double hertz)
    {
        if (!double.IsFinite(hertz) || hertz <= 0)
            throw new DeviceReadoutException(ErrorCode.InvalidConfiguration, "Sampling frequency must be positive and finite.");
        return new(hertz);
    }
}
