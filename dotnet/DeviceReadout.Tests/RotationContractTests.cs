using DeviceReadout;

internal static class RotationContractTests
{
    internal static IEnumerable<(string Name, Func<Task> Run)> Cases() => [
        ("orientation get and watch normalize unit rotations while preserving axes and signs", VerifyBoth)
    ];

    private static async Task VerifyBoth()
    {
        await Verify(Entities.RelativeOrientation, q => new RelativeOrientationSnapshot {Value = q}, s => s.Value);
        await Verify(Entities.AbsoluteOrientation, q => new AbsoluteOrientationSnapshot {Value = q}, s => s.Value);
    }

    private static async Task Verify<T>(Entity<T> kind, Func<Quaternion?, T> make, Func<T, Quaternion?> value) where T : DeviceSnapshot
    {
        Quaternion?[] samples = [
            new(double.NaN, 0, 0, 1), new(0, double.PositiveInfinity, 0, 1),
            new(0, 0, double.NegativeInfinity, 1), new(0, 0, 0, double.NaN), null,
            new(0, 0, 0, 0), new(0, 0, 0, 1), new(0, 0, 0, -1),
            new(0, 0, 3, 4), new(0, 0, -3, -4), new(double.MaxValue, double.MaxValue, 0, 0), new(double.Epsilon, 0, 0, 0)
        ];
        Quaternion?[] expected = [null, null, null, null, null, null,
            new(0, 0, 0, 1), new(0, 0, 0, -1), new(0, 0, 0.6, 0.8), new(0, 0, -0.6, -0.8),
            new(0.7071067811865475, 0.7071067811865475, 0, 0), new(1, 0, 0, 0)];
        using var access = new DeviceAccess(new NoReadCollector());
        using var limit = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        var target = access.Observers.Target(kind, "rotation");
        using var source = access.Observers.SensorSource(target, session => {
            foreach (var sample in samples) session.Publish(make(sample));
            return null;
        });
        Check(value(await access.Get(target, limit.Token)) is null, "one invalid component yields a grouped null");
        await using var stream = access.Watch(target, limit.Token).GetAsyncEnumerator();
        foreach (var wanted in expected) {
            Check(await stream.MoveNextAsync(), "all real samples must arrive");
            var result = value(stream.Current);
            if (wanted is not {} e) {Check(result is null, "zero or nonfinite rotation is unavailable");continue;}
            Check(result is not null, "finite nonzero rotation is available");
            var q = result!.Value;
            Check(Math.Abs(q.X-e.X) <= 1e-15 && Math.Abs(q.Y-e.Y) <= 1e-15 &&
                Math.Abs(q.Z-e.Z) <= 1e-15 && Math.Abs(q.W-e.W) <= 1e-15, "unit rotation components");
        }
    }

    private static void Check(bool condition, string message) {if (!condition) throw new Exception(message);}
    private sealed class NoReadCollector : IDeviceCollector
    {
        public DeviceSnapshot Read(EntityAddress entity, CancellationToken token) => throw new Exception("Sensor sources cannot probe state");
    }
}
