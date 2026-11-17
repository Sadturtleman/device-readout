using System.Collections.Immutable;
namespace DeviceReadout;

internal static partial class SnapshotRules
{
    internal static double? Finite(double? value) => value.HasValue && double.IsFinite(value.Value) ? value : null;
    internal static double? Ratio(double? value) => value is >= 0 and <= 1 ? value : null;
    internal static TimeSpan? Duration(TimeSpan? value) => value.HasValue && value >= TimeSpan.Zero ? value : null;
    internal static T? KnownEnum<T>(T? value) where T : struct, Enum => value.HasValue && Enum.IsDefined(value.Value) ? value : null;
    internal static ImmutableHashSet<T>? EnumSet<T>(ImmutableHashSet<T>? values) where T : struct, Enum
        => values is not null && values.All(Enum.IsDefined) ? values : null;
    internal static ImmutableDictionary<T, TValue>? EnumMap<T, TValue>(ImmutableDictionary<T, TValue>? values) where T : struct, Enum
        => values is not null && values.Keys.All(Enum.IsDefined) ? values : null;
    internal static ThermalState? Thermal(ThermalState? value) => value switch {
        ThermalState.Android state when Enum.IsDefined(state.Value) => state,
        ThermalState.Apple state when Enum.IsDefined(state.Value) => state,
        _ => null
    };
    private static bool AllFinite(params double[] values) => values.All(double.IsFinite);
    internal static Vector3? Vector(Vector3? value) => value is {} v && AllFinite(v.X, v.Y, v.Z) ? value : null;
    internal static Quaternion? Rotation(Quaternion? value)
    {
        if (value is not {} v || !AllFinite(v.X, v.Y, v.Z, v.W)) return null;
        var scale = Math.Max(Math.Max(Math.Abs(v.X), Math.Abs(v.Y)), Math.Max(Math.Abs(v.Z), Math.Abs(v.W)));
        if (scale == 0) return null;
        var x = v.X / scale;var y = v.Y / scale;var z = v.Z / scale;var w = v.W / scale;
        var length = Math.Sqrt(x * x + y * y + z * z + w * w);
        return new Quaternion(x / length, y / length, z / length, w / length);
    }
    internal static Rect? Rectangle(Rect? value) => value is {} v && AllFinite(v.X, v.Y, v.Width, v.Height) ? value : null;
    internal static Insets? Edges(Insets? value) => value is {} v && AllFinite(v.Top, v.Right, v.Bottom, v.Left) ? value : null;
    internal static Size<double>? Size(Size<double>? value) => value is {} v && AllFinite(v.Width, v.Height) ? value : null;
    internal static ImmutableArray<string>? Strings(ImmutableArray<string>? value)
        => value.HasValue && !value.Value.IsDefault && value.Value.All(item => item is not null) ? value : null;
    internal static ImmutableArray<DisplayMode>? DisplayModes(ImmutableArray<DisplayMode>? value)
        => value.HasValue && !value.Value.IsDefault && value.Value.All(item => item is not null)
            ? value.Value.Select(item => item with {RefreshRateHz = Finite(item.RefreshRateHz)}).ToImmutableArray() : null;
    internal static ImmutableArray<IpAddressInfo>? Addresses(ImmutableArray<IpAddressInfo>? value)
        => value.HasValue && !value.Value.IsDefault && value.Value.All(item => item?.Address is not null) ? value : null;
    internal static ImmutableArray<NetworkRoute>? Routes(ImmutableArray<NetworkRoute>? value)
        => value.HasValue && !value.Value.IsDefault && value.Value.All(item => item?.Destination is not null) ? value : null;
}
