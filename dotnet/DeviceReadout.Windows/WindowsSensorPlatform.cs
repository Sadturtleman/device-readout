using System.Runtime.InteropServices;
using System.Runtime.Versioning;

namespace DeviceReadout.Windows;

internal interface IWindowsSensorRuntime
{
    int Initialize();
    nint Factory(string name, Guid iid);
    void Release(nint value);
    void Uninitialize();
}
[UnmanagedFunctionPointer(CallingConvention.StdCall)] internal delegate int SensorGetUInt(nint self, out uint value);
[UnmanagedFunctionPointer(CallingConvention.StdCall)] internal delegate int SensorPutUInt(nint self, uint value);
[UnmanagedFunctionPointer(CallingConvention.StdCall)] internal delegate int SensorStringCall(nint self, nint text, out nint value);
[UnmanagedFunctionPointer(CallingConvention.StdCall)] internal delegate int SensorGetAt(nint self, uint index, out nint value);
[UnmanagedFunctionPointer(CallingConvention.StdCall)] internal delegate int SensorGetFloat(nint self, out float value);
[UnmanagedFunctionPointer(CallingConvention.StdCall)] internal delegate int SensorGetDouble(nint self, out double value);
[UnmanagedFunctionPointer(CallingConvention.StdCall)] internal delegate int SensorSelectorByType(nint self, int readingType, out nint selector);

[SupportedOSPlatform("windows")]
internal sealed class WindowsSensorPlatform(IWindowsSensorRuntime? runtime = null) : IWindowsSensorPlatform
{
    private sealed record Definition(string Class, Guid FactoryId, Guid HandlerId, int? SelectorSlot, int OpenSlot, int? MinimumSlot, int? SetIntervalSlot, int? GetIntervalSlot, int AddSlot, int? ReadingType = null, bool OpenAsync = true, int CurrentSlot = 6, bool CurrentAsync = false, Guid? OpenFactoryId = null, int? DefaultDeviceIdSlot = null);
    private static readonly Definition Light = new("Windows.Devices.Sensors.LightSensor", new("0ec0a650-ddc6-40ab-ace3-ec3359d42c51"), new("1ecf183a-9f0a-5f73-9225-5a33eab5594f"), 6, 7, 7, 8, 9, 10);
    private static readonly Definition Pressure = new("Windows.Devices.Sensors.Barometer", new("8fc6b1e7-95ff-44ac-878e-d65c8308c34c"), new("e4caf459-d101-5ca5-a4ea-deb0917ae27e"), 7, 6, 8, 9, 10, 11);
    private static readonly Definition Gyroscope = new("Windows.Devices.Sensors.Gyrometer", new("ef83f7a1-d700-4204-9613-79c6b161df4e"), new("15171524-5786-59a5-af5b-a01245726c44"), 6, 7, 7, 8, 9, 10);
    private static readonly Definition Magnetometer = new("Windows.Devices.Sensors.Magnetometer", new("2c0819f0-ffc6-4f89-a06f-18fa10792933"), new("f9a0da76-c4fd-50ab-98b6-bfd26d6d3d82"), 6, 7, 7, 8, 9, 10);
    private static readonly Definition Accelerometer = new("Windows.Devices.Sensors.Accelerometer", new("9de218cf-455d-4cf3-8200-70e1410340f8"), new("a5e83e40-b597-5b83-92f5-5bed3926ca80"), 7, 6, 7, 8, 9, 10, ReadingType: 0);
    private static readonly Definition LinearAcceleration = Accelerometer with {ReadingType = 1};
    private static readonly Definition Gravity = Accelerometer with {ReadingType = 2};
    private static readonly Definition AbsoluteOrientation = new("Windows.Devices.Sensors.OrientationSensor", new("a67feb55-2c85-4b28-a0fe-58c4b20495f5"), new("91ae0c43-e1f7-577d-a161-8aaf275eb927"), 6, 8, 7, 8, 9, 10, ReadingType: 0);
    private static readonly Definition RelativeOrientation = AbsoluteOrientation with {ReadingType = 1};
    private static readonly Definition Proximity = new("Windows.Devices.Sensors.ProximitySensor", new("29186649-6269-4e57-a5ad-82be80813392"), new("9f7e222b-892a-5e68-b08a-10384b5f92b9"), 6, 7, null, null, null, 10, OpenAsync: false, CurrentSlot: 9);
    private static readonly Definition Hinge = new("Windows.Devices.Sensors.HingeAngleSensor", new("b7b63910-fbb1-4123-89ce-4ea34eb0dfca"), new("68de2bf4-243c-5aee-9dd9-d2e5e3165866"), 6, 9, null, null, null, 11, CurrentAsync: true);
    private static readonly Definition HumanPresence = new("Windows.Devices.Sensors.HumanPresenceSensor", new("2ae89842-dba9-56b2-9f27-eac69d621004"), new("329678bc-3d7c-5ff3-87cb-4fc5e9fecf72"), 6, 6, null, null, null, 10, OpenAsync: false, CurrentSlot: 9, OpenFactoryId: new Guid("5de35843-d260-5a87-995e-ace91326e1c4"));
    private static readonly Definition Altimeter = new("Windows.Devices.Sensors.Altimeter", new("9eb4d7c3-e5ac-47ce-8eef-d3718168c01f"), new("d775d699-9d74-5473-9c1b-d51a89db6642"), null, 6, 8, 9, 10, 11, OpenAsync: false, DefaultDeviceIdSlot: 7);
    private static readonly Guid EnumerationId = new("c17f100e-3a46-4a78-8013-769dc9b97390");
    private static readonly Guid AsyncInfoId = new("00000036-0000-0000-c000-000000000046");
    private static readonly Guid AccelerationTypeId = new("1d373c4f-42d3-45b2-8144-ab7fb665eb59");
    private static readonly Guid OrientationTypeId = new("0d924cf9-2f1f-49c9-8042-4a1813d67760");
    private readonly IWindowsSensorRuntime runtime = runtime ?? new SensorRuntime();
    private readonly Dictionary<(string Class, Guid Iid), nint> factories = [];
    private readonly Dictionary<(EntityKind Kind, string Id), Source> sources = [];
    private bool initialized, closed;
    private sealed class Source(nint pointer, uint minimum, uint original, Definition definition)
    {
        internal readonly nint Pointer = pointer;
        internal readonly uint Minimum = minimum, Original = original;
        internal uint Interval = original;
        internal readonly Definition Definition = definition;
        internal readonly List<Client> Clients = [];
    }
    private sealed class Client(uint interval)
    {
        internal readonly uint Interval = interval;
        internal WindowsCellularEventHandler? Handler;
        internal long Token;
        internal bool Registered;
    }
    private static Definition For(EntityKind kind) => kind switch {
        EntityKind.Illuminance => Light, EntityKind.Pressure => Pressure, EntityKind.Gyroscope => Gyroscope,
        EntityKind.Magnetometer => Magnetometer,
        EntityKind.Accelerometer => Accelerometer,
        EntityKind.LinearAcceleration => LinearAcceleration, EntityKind.Gravity => Gravity,
        EntityKind.AbsoluteOrientation => AbsoluteOrientation,
        EntityKind.RelativeOrientation => RelativeOrientation,
        EntityKind.ProximityNear or EntityKind.ProximityDistance => Proximity,
        EntityKind.HingeAngle => Hinge,
        EntityKind.HumanPresence => HumanPresence,
        EntityKind.RelativeAltitude => Altimeter,
        _ => throw new DeviceReadoutException(ErrorCode.UnsupportedEntity, "Windows sensor mapping is unavailable.")
    };
    private nint Factory(string name, Guid iid)
    {
        if (closed) throw new DeviceReadoutException(ErrorCode.EntityRemoved, "Sensor platform is closed.");
        if (!initialized) {Check(runtime.Initialize(), "RoInitialize");initialized = true;}
        if (!factories.TryGetValue((name, iid), out var factory)) {
            factory = runtime.Factory(name, iid);
            if (factory == 0) throw new DeviceReadoutException(ErrorCode.UnsupportedEntity, "Sensor runtime class is unavailable.");
            factories.Add((name, iid), factory);
        }
        return factory;
    }
    public IReadOnlyList<WindowsSensorInfo> List(EntityKind kind, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();var definition = For(kind);
        if (definition.DefaultDeviceIdSlot is { } deviceIdSlot) {
            var sensor = DefaultSensor(definition, token);
            if (sensor == 0) return [];
            try {
                var id = TextProperty(sensor, deviceIdSlot, required: true)!;
                token.ThrowIfCancellationRequested();return [new(id, null)];
            } finally {Release(sensor);}
        }
        var factory = Factory(definition.Class, definition.FactoryId);
        var selectorSlot = definition.SelectorSlot ?? throw new DeviceReadoutException(ErrorCode.UnsupportedEntity, "Sensor selector is unavailable.");
        nint selector = 0, operation = 0, collection = 0;
        try {
            var selectorStatus = definition.ReadingType is { } readingType
                ? Method<SensorSelectorByType>(factory, selectorSlot)(factory, readingType, out selector)
                : Method<WinRtGetInterface>(factory, selectorSlot)(factory, out selector);
            Check(selectorStatus, "Sensor.GetDeviceSelector");
            if (selector == 0 || String(selector).Length == 0) throw new DeviceReadoutException(ErrorCode.UnsupportedEntity, "Sensor selector is unavailable.");
            token.ThrowIfCancellationRequested();var information = Factory("Windows.Devices.Enumeration.DeviceInformation", EnumerationId);
            Check(Method<SensorStringCall>(information, 10)(information, selector, out operation), "DeviceInformation.FindAllAsync");
            collection = Await(operation, token);
            if (collection == 0) throw new DeviceReadoutException(ErrorCode.ReadFailed, "Missing sensor inventory.");
            Check(Method<SensorGetUInt>(collection, 7)(collection, out var count), "Sensor inventory.Size");
            if (count > 4096) throw new DeviceReadoutException(ErrorCode.ReadFailed, "Sensor inventory is too large.");
            List<WindowsSensorInfo> result = [];
            for (uint index = 0; index < count; index++) {
                token.ThrowIfCancellationRequested();nint item = 0;
                try {
                    Check(Method<SensorGetAt>(collection, 6)(collection, index, out item), "Sensor inventory.GetAt");
                    if (item == 0) throw new DeviceReadoutException(ErrorCode.ReadFailed, "Missing sensor inventory entry.");
                    var id = TextProperty(item, 6, required: true)!;
                    token.ThrowIfCancellationRequested();result.Add(new(id, TextProperty(item, 7, required: false)));
                } finally {Release(item);}
            }
            token.ThrowIfCancellationRequested();return result;
        } finally {Release(collection);Release(operation);if (selector != 0) WindowsDeleteString(selector);}
    }
    private nint Open(EntityKind kind, string id, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();var definition = For(kind);
        if (definition.DefaultDeviceIdSlot is { } deviceIdSlot) {
            var selected = DefaultSensor(definition, token);
            if (selected == 0) throw new DeviceReadoutException(ErrorCode.EntityRemoved, "Selected default sensor is unavailable.");
            try {
                var actualId = TextProperty(selected, deviceIdSlot, required: true);
                token.ThrowIfCancellationRequested();
                if (!StringComparer.OrdinalIgnoreCase.Equals(id, actualId))
                    throw new DeviceReadoutException(ErrorCode.EntityRemoved, "Default sensor no longer matches this target.");
                return selected;
            } catch {Release(selected);throw;}
        }
        var factory = Factory(definition.Class, definition.OpenFactoryId ?? definition.FactoryId);
        Check(WindowsCreateString(id, id.Length, out var text), "WindowsCreateString");nint operation = 0;
        try {
            Check(Method<SensorStringCall>(factory, definition.OpenSlot)(factory, text, out operation), definition.OpenAsync ? "Sensor.FromIdAsync" : "Sensor.FromId");
            nint sensor;
            if (definition.OpenAsync) sensor = Await(operation, token);
            else {sensor = operation;operation = 0;}
            if (sensor == 0) throw new DeviceReadoutException(ErrorCode.EntityRemoved, "Selected sensor is unavailable.");
            try {
                token.ThrowIfCancellationRequested();
                if (definition.ReadingType is { } expectedType) {
                    var orientation = kind is EntityKind.AbsoluteOrientation or EntityKind.RelativeOrientation;
                    nint typedSensor = 0;var iid = orientation ? OrientationTypeId : AccelerationTypeId;
                    try {
                        Check(Marshal.QueryInterface(sensor, in iid, out typedSensor), orientation ? "IOrientationSensor2" : "IAccelerometer4");
                        if (typedSensor == 0) throw new DeviceReadoutException(ErrorCode.ReadFailed, "Missing sensor reading type interface.");
                        token.ThrowIfCancellationRequested();
                        Check(Method<WinRtGetInt32>(typedSensor, orientation ? 8 : 6)(typedSensor, out var actualType), "Sensor.ReadingType");
                        token.ThrowIfCancellationRequested();
                        if (actualType != expectedType) throw new DeviceReadoutException(ErrorCode.EntityRemoved, "Native reading kind no longer matches this target.");
                    } finally {Release(typedSensor);}
                }
                return sensor;
            } catch {Release(sensor);throw;}
        } finally {Release(operation);WindowsDeleteString(text);}
    }
    private nint DefaultSensor(Definition definition, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();var factory = Factory(definition.Class, definition.FactoryId);nint sensor = 0;
        try {
            Check(Method<WinRtGetInterface>(factory, definition.OpenSlot)(factory, out sensor), "Sensor.GetDefault");
            token.ThrowIfCancellationRequested();return sensor;
        } catch {Release(sensor);throw;}
    }
    public WindowsSensorInfo Describe(EntityKind kind, string id, CancellationToken token)
    {
        var sensor = Open(kind, id, token);
        try {
            token.ThrowIfCancellationRequested();
            if (kind == EntityKind.ProximityDistance) return new(id, null, MaximumRange: UnsignedProperty(sensor, 7, token) / 1000d);
            if (For(kind).MinimumSlot is not { } minimumSlot) return new(id, null);
            var hr = Method<SensorGetUInt>(sensor, minimumSlot)(sensor, out var minimum);
            token.ThrowIfCancellationRequested();return new(id, null, hr >= 0 && minimum > 0 ? TimeSpan.FromMilliseconds(minimum) : null);
        } finally {Release(sensor);}
    }
    public IDisposable Subscribe(EntityKind kind, string id, SensorSamplingRate rate, Action<WindowsSensorSample> emit, Action<Exception> fail, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();var definition = For(kind);var key = (kind, id);
        if (!sources.TryGetValue(key, out var source)) {
            var sensor = Open(kind, id, token);
            try {
                token.ThrowIfCancellationRequested();uint minimum = 0, original = 0;
                if (definition.MinimumSlot is { } minimumSlot) Check(Method<SensorGetUInt>(sensor, minimumSlot)(sensor, out minimum), "Sensor.MinimumReportInterval");
                if (definition.GetIntervalSlot is { } intervalSlot) Check(Method<SensorGetUInt>(sensor, intervalSlot)(sensor, out original), "Sensor.ReportInterval");
                source = new(sensor, minimum, original, definition);sources.Add(key, source);
            } catch {Release(sensor);throw;}
        }
        var requested = rate.Hertz is { } hz ? (uint)Math.Clamp(Math.Ceiling(1000 / hz), 1, uint.MaxValue) : 0;
        var client = new Client(requested == 0 ? 0 : Math.Max(requested, source.Minimum));source.Clients.Add(client);
        var firstSampleGate = new object();var eventReceived = 0;
        try {
            ApplyInterval(source);token.ThrowIfCancellationRequested();
            client.Handler = new(definition.HandlerId, args => {
                if (args == 0) throw new DeviceReadoutException(ErrorCode.ReadFailed, "Missing sensor event payload.");
                nint reading = 0;
                try {
                    Check(Method<WinRtGetInterface>(args, 6)(args, out reading), "Sensor event.Reading");
                    if (reading == 0) throw new DeviceReadoutException(ErrorCode.ReadFailed, "Missing sensor reading.");
                    var sample = Sample(kind, reading, token);
                    lock (firstSampleGate) {emit(sample);Volatile.Write(ref eventReceived, 1);}
                } finally {Release(reading);}
            }, fail);
            Check(Method<WinRtAddReportEvent>(source.Pointer, definition.AddSlot)(source.Pointer, client.Handler.Pointer, out client.Token), "Sensor.add ReadingChanged");
            client.Registered = true;token.ThrowIfCancellationRequested();nint initial = 0, initialOperation = 0;
            try {
                if (definition.CurrentAsync) {
                    Check(Method<WinRtGetInterface>(source.Pointer, definition.CurrentSlot)(source.Pointer, out initialOperation), "Sensor.GetCurrentReadingAsync");
                    initial = Await(initialOperation, token, () => Volatile.Read(ref eventReceived) != 0);
                } else Check(Method<WinRtGetInterface>(source.Pointer, definition.CurrentSlot)(source.Pointer, out initial), "Sensor.GetCurrentReading");
                token.ThrowIfCancellationRequested();
                if (initial != 0 && Volatile.Read(ref eventReceived) == 0) {
                    var sample = Sample(kind, initial, token);
                    lock (firstSampleGate) {if (eventReceived == 0) emit(sample);}
                }
            } finally {Release(initial);Release(initialOperation);}
            return new Lease(() => Remove(key, source, client));
        } catch {try {Remove(key, source, client);} catch (Exception) { } throw;}
    }
    private WindowsSensorSample Sample(EntityKind kind, nint reading, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        if (kind == EntityKind.HumanPresence) {
            var status = Method<WinRtGetInt32>(reading, 7)(reading, out var presence);
            token.ThrowIfCancellationRequested();
            return new(Detected: status >= 0 ? presence switch {1 => true, 2 => false, _ => null} : null);
        }
        if (kind is EntityKind.HingeAngle or EntityKind.RelativeAltitude) {
            var status = Method<SensorGetDouble>(reading, 7)(reading, out var angle);
            token.ThrowIfCancellationRequested();return new(Scalar: status >= 0 ? angle : null);
        }
        if (kind == EntityKind.ProximityDistance) return new(Scalar: UnsignedProperty(reading, 8, token));
        if (kind == EntityKind.ProximityNear) {
            var status = Method<WinRtGetBoolean>(reading, 7)(reading, out var detected);
            token.ThrowIfCancellationRequested();
            return new(Detected: status >= 0 ? detected switch {0 => false, 1 => true, _ => null} : null);
        }
        if (kind is EntityKind.AbsoluteOrientation or EntityKind.RelativeOrientation) {
            nint quaternion = 0;
            try {
                var status = Method<WinRtGetInterface>(reading, 8)(reading, out quaternion);
                token.ThrowIfCancellationRequested();
                if (status < 0 || quaternion == 0) return default;
                if (RotationComponent(6) is not { } w || RotationComponent(7) is not { } x || RotationComponent(8) is not { } y || RotationComponent(9) is not { } z) return default;
                return new(Rotation: new(x, y, z, w));

                double? RotationComponent(int slot)
                {
                    token.ThrowIfCancellationRequested();
                    var hr = Method<SensorGetFloat>(quaternion, slot)(quaternion, out var value);
                    token.ThrowIfCancellationRequested();return hr >= 0 ? value : null;
                }
            } finally {Release(quaternion);}
        }
        if (kind is EntityKind.Magnetometer or EntityKind.Gyroscope or EntityKind.Accelerometer or EntityKind.LinearAcceleration or EntityKind.Gravity) {
            if (Component(7) is not { } x || Component(8) is not { } y || Component(9) is not { } z) return default;
            return new(Vector: new(x, y, z));
        }
        if (kind == EntityKind.Illuminance) {
            Check(Method<SensorGetFloat>(reading, 7)(reading, out var value), "LightSensorReading.IlluminanceInLux");
            token.ThrowIfCancellationRequested();return new(Scalar: value);
        }
        Check(Method<SensorGetDouble>(reading, 7)(reading, out var pressure), "BarometerReading.StationPressureInHectopascals");
        token.ThrowIfCancellationRequested();return new(Scalar: pressure);

        double? Component(int slot)
        {
            token.ThrowIfCancellationRequested();int status;double value;
            if (kind == EntityKind.Magnetometer) {status = Method<SensorGetFloat>(reading, slot)(reading, out var single);value = single;}
            else status = Method<SensorGetDouble>(reading, slot)(reading, out value);
            token.ThrowIfCancellationRequested();return status >= 0 ? value : null;
        }
    }
    private uint? UnsignedProperty(nint instance, int slot, CancellationToken token)
    {
        nint reference = 0;
        try {
            token.ThrowIfCancellationRequested();
            var status = Method<WinRtGetInterface>(instance, slot)(instance, out reference);
            token.ThrowIfCancellationRequested();
            if (status < 0 || reference == 0) return null;
            status = Method<SensorGetUInt>(reference, 6)(reference, out var value);
            token.ThrowIfCancellationRequested();return status >= 0 ? value : null;
        } finally {Release(reference);}
    }
    private static void ApplyInterval(Source source)
    {
        if (source.Definition.SetIntervalSlot is not { } intervalSlot) return;
        var numeric = source.Clients.Where(client => client.Interval != 0).Select(client => client.Interval).ToArray();
        var desired = numeric.Length == 0 ? source.Original : numeric.Min();
        if (source.Interval == desired) return;
        Check(Method<SensorPutUInt>(source.Pointer, intervalSlot)(source.Pointer, desired), "Sensor.ReportInterval");source.Interval = desired;
    }
    private void Remove((EntityKind Kind, string Id) key, Source source, Client client)
    {
        if (!source.Clients.Remove(client)) return;client.Handler?.Stop();Exception? failure = null;
        try {if (client.Registered) Check(Method<WinRtRemoveReportEvent>(source.Pointer, source.Definition.AddSlot + 1)(source.Pointer, client.Token), "Sensor.remove ReadingChanged");}
        catch (Exception error) {failure = error;}
        finally {
            client.Handler?.ReleaseOwner();
            try {ApplyInterval(source);} catch (Exception error) {failure ??= error;}
            finally {if (source.Clients.Count == 0) {sources.Remove(key);Release(source.Pointer);}}
        }
        if (failure is not null) throw failure;
    }
    private nint Await(nint operation, CancellationToken token, Func<bool>? superseded = null)
    {
        if (operation == 0) throw new DeviceReadoutException(ErrorCode.ReadFailed, "Missing sensor asynchronous operation.");
        var iid = AsyncInfoId;Check(Marshal.QueryInterface(operation, in iid, out var info), "IAsyncInfo");var status = 0;
        try {
            while (true) {
                token.ThrowIfCancellationRequested();if (superseded?.Invoke() == true) return 0;
                Check(Method<WinRtGetInt32>(info, 7)(info, out status), "IAsyncInfo.Status");
                if (status != 0) break;token.WaitHandle.WaitOne(5);
            }
            if (status == 2) throw new OperationCanceledException(token);
            if (status == 3) {Check(Method<WinRtGetInt32>(info, 8)(info, out var error), "IAsyncInfo.ErrorCode");Check(error, "Sensor asynchronous operation");}
            if (status != 1) throw new DeviceReadoutException(ErrorCode.ReadFailed, "Invalid sensor operation completion state.");
            token.ThrowIfCancellationRequested();if (superseded?.Invoke() == true) return 0;
            nint result = 0;
            try {Check(Method<WinRtGetInterface>(operation, 8)(operation, out result), "Sensor operation.GetResults");return result;}
            catch {Release(result);throw;}
        } finally {
            try {if (status == 0) _ = Method<WinRtNoArguments>(info, 9)(info);}
            finally {try {_ = Method<WinRtNoArguments>(info, 10)(info);} finally {Release(info);}}
        }
    }
    private static string? TextProperty(nint instance, int slot, bool required)
    {
        nint text = 0;
        try {
            var hr = Method<WinRtGetInterface>(instance, slot)(instance, out text);
            if (hr < 0 && !required) return null;Check(hr, "Sensor device information");
            var value = text == 0 ? null : String(text);
            if (required && string.IsNullOrEmpty(value)) throw new DeviceReadoutException(ErrorCode.ReadFailed, "Missing sensor identity.");return value;
        } finally {if (text != 0) WindowsDeleteString(text);}
    }
    private static string String(nint text)
    {
        var buffer = WindowsGetStringRawBuffer(text, out var length);
        if (length > 65536 || length > 0 && buffer == 0) throw new DeviceReadoutException(ErrorCode.ReadFailed, "Invalid sensor string.");
        return length == 0 ? "" : Marshal.PtrToStringUni(buffer, (int)length)!;
    }
    private static T Method<T>(nint self, int slot) where T : Delegate => Marshal.GetDelegateForFunctionPointer<T>(Marshal.ReadIntPtr(Marshal.ReadIntPtr(self), slot * nint.Size));
    private void Release(nint value) {if (value != 0) runtime.Release(value);}
    internal static void Check(int status, string api)
    {
        if (status >= 0) return;
        var code = status switch {unchecked((int)0x80070005) => ErrorCode.PermissionDenied,
            unchecked((int)0x80004002) or unchecked((int)0x80040154) or unchecked((int)0x80004001) => ErrorCode.UnsupportedEntity,
            unchecked((int)0x8007048f) or unchecked((int)0x80070490) => ErrorCode.EntityRemoved, _ => ErrorCode.ReadFailed};
        throw new DeviceReadoutException(code, $"{api} failed (HRESULT 0x{status:X8}).");
    }
    public void Dispose()
    {
        if (closed) return;closed = true;Exception? failure = null;
        foreach (var pair in sources.ToArray()) foreach (var client in pair.Value.Clients.ToArray()) {
            try {Remove(pair.Key, pair.Value, client);} catch (Exception error) {failure ??= error;}
        }
        foreach (var factory in factories.Values) {try {Release(factory);} catch (Exception error) {failure ??= error;}}
        factories.Clear();if (initialized) {initialized = false;runtime.Uninitialize();}
        if (failure is not null) throw failure;
    }
    private sealed class Lease(Action cleanup) : IDisposable
    {
        private Action? dispose = cleanup;
        public void Dispose() => Interlocked.Exchange(ref dispose, null)?.Invoke();
    }
    internal sealed class SensorRuntime : IWindowsSensorRuntime
    {
        public int Initialize() => RoInitialize(1);
        public nint Factory(string name, Guid iid)
        {
            Check(WindowsCreateString(name, name.Length, out var text), "WindowsCreateString");nint factory = 0;
            try {Check(RoGetActivationFactory(text, in iid, out factory), "Sensor RoGetActivationFactory");return factory;}
            catch {if (factory != 0) Marshal.Release(factory);throw;}
            finally {WindowsDeleteString(text);}
        }
        public void Release(nint value) => Marshal.Release(value);
        public void Uninitialize() => RoUninitialize();
    }
    [DllImport("combase.dll")] private static extern int RoInitialize(uint type);
    [DllImport("combase.dll")] private static extern void RoUninitialize();
    [DllImport("combase.dll")] private static extern int RoGetActivationFactory(nint name, in Guid iid, out nint factory);
    [DllImport("combase.dll", CharSet = CharSet.Unicode)] private static extern int WindowsCreateString(string source, int length, out nint value);
    [DllImport("combase.dll")] private static extern int WindowsDeleteString(nint text);
    [DllImport("combase.dll")] private static extern nint WindowsGetStringRawBuffer(nint text, out uint length);
}
