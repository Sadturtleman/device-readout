using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace DeviceReadout;

public static class SnapshotJson
{
    private static readonly JsonSerializerOptions Options = CreateOptions();
    private static JsonSerializerOptions CreateOptions()
    {
        var options = new JsonSerializerOptions {PropertyNamingPolicy = JsonNamingPolicy.CamelCase};
        options.Converters.Add(new UnsignedIntegerConverter());options.Converters.Add(new SignedIntegerConverter());
        options.Converters.Add(new DurationConverter());options.Converters.Add(new ThermalConverter());
        options.Converters.Add(new JsonStringEnumConverter(allowIntegerValues:false));
        options.TypeInfoResolver = ModelJsonContext.Default;
        options.MakeReadOnly();return options;
    }
    public static string Serialize(DeviceSnapshot snapshot) => JsonSerializer.Serialize(SnapshotRules.Normalize(snapshot), snapshot.GetType(), Options);

    private sealed class UnsignedIntegerConverter : JsonConverter<ulong>
    {
        public override ulong Read(ref Utf8JsonReader reader, Type type, JsonSerializerOptions options) => reader.TokenType == JsonTokenType.String
            ? ulong.Parse(reader.GetString()!, CultureInfo.InvariantCulture) : reader.GetUInt64();
        public override void Write(Utf8JsonWriter writer, ulong value, JsonSerializerOptions options) => writer.WriteStringValue(value.ToString(CultureInfo.InvariantCulture));
    }
    private sealed class SignedIntegerConverter : JsonConverter<long>
    {
        public override long Read(ref Utf8JsonReader reader, Type type, JsonSerializerOptions options) => reader.TokenType == JsonTokenType.String
            ? long.Parse(reader.GetString()!, CultureInfo.InvariantCulture) : reader.GetInt64();
        public override void Write(Utf8JsonWriter writer, long value, JsonSerializerOptions options) => writer.WriteStringValue(value.ToString(CultureInfo.InvariantCulture));
    }
    private sealed class DurationConverter : JsonConverter<TimeSpan>
    {
        public override TimeSpan Read(ref Utf8JsonReader reader, Type type, JsonSerializerOptions options) => TimeSpan.FromMilliseconds(reader.GetDouble());
        public override void Write(Utf8JsonWriter writer, TimeSpan value, JsonSerializerOptions options) => writer.WriteNumberValue(value.TotalMilliseconds);
    }
    private sealed class ThermalConverter : JsonConverter<ThermalState>
    {
        public override ThermalState? Read(ref Utf8JsonReader reader, Type type, JsonSerializerOptions options) => throw new NotSupportedException("Snapshot deserialization is not a public SDK API.");
        public override void Write(Utf8JsonWriter writer, ThermalState value, JsonSerializerOptions options)
        {
            switch (value) {
                case ThermalState.Android android when Enum.IsDefined(android.Value): writer.WriteStringValue($"AndroidThermalState.{android.Value}");break;
                case ThermalState.Apple apple when Enum.IsDefined(apple.Value): writer.WriteStringValue($"AppleThermalState.{apple.Value}");break;
                default: writer.WriteNullValue();break;
            }
        }
    }
}
