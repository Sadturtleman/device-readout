using System.Buffers.Binary;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using DeviceReadout;
using DeviceReadout.Windows;

[SupportedOSPlatform("windows")]
internal static class WindowsCpuTests
{
    internal static IEnumerable<(string Name, Func<Task> Run)> Cases() => [
        ("Windows CPU topology separates logical processors, cores and packages across groups", TopologyFields),
        ("Windows CPU clocks preserve per-processor frequency, units and independent availability", ClockFields),
        ("real Windows CPU topology and per-core reads agree with the system-wide active processor count", NativeTopology),
        ("Windows CPU polling retires observed removals and retains targets across failed discovery", TargetLifetimes),
        ("Windows CPU malformed topology and ambiguous power records cannot corrupt discovery", InvalidResponses)
    ];

    private static async Task NativeTopology()
    {
        using var access = WindowsDeviceAccess.Create();
        var cpu = await access.Get(Entities.Cpu);var cores = await access.CpuCores.List();
        Check(cpu.LogicalProcessorCount == GetActiveProcessorCount(ushort.MaxValue) && cores.Length == cpu.LogicalProcessorCount, "independent system-wide processor count");
        Check(cpu.PhysicalCoreCount > 0 && cpu.PhysicalCoreCount <= cores.Length && cpu.ProcessorPackageCount > 0, "native physical relationship counts");
        var snapshots = new List<CpuCoreSnapshot>();foreach(var core in cores) snapshots.Add(await access.Get(core));
        Check(snapshots.Select(core => core.LogicalIndex).Distinct().Count() == cores.Length && snapshots.All(core => core.Online == true), "distinct live native logical processors");
        Check(snapshots.All(core => core.CoreIndex >= 0 && core.PackageIndex >= 0), "native core/package assignments");
        Console.WriteLine($"Native CPU topology: logical={cpu.LogicalProcessorCount}, available={cpu.AvailableLogicalProcessorCount}, physical={cpu.PhysicalCoreCount}, packages={cpu.ProcessorPackageCount}; first clocks={snapshots[0].CurrentClockHz}/{snapshots[0].MaximumClockHz} Hz.");
    }
    [DllImport("kernel32.dll")] private static extern uint GetActiveProcessorCount(ushort group);

    private static async Task TargetLifetimes()
    {
        var platform = new CpuPlatformFixture();var original = platform.Records;
        using var access = new DeviceAccess(new WindowsCollector(cpuPlatform: platform));
        var targets = await access.CpuCores.List();var removed = targets[^1];
        await using var stream = access.WithPollInterval(TimeSpan.FromMilliseconds(25)).Watch(removed).GetAsyncEnumerator();
        Check(await stream.MoveNextAsync() && stream.Current.LogicalIndex == 64, "initial core state");
        platform.Records = [Relation(0, (0, 3)), Relation(0, (0, 12)), Relation(3, (0, 15))];
        await Error(ErrorCode.EntityRemoved, async () => {while (await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1))) { }});
        await Error(ErrorCode.EntityRemoved, () => access.Get(removed));
        Check((await access.Get(targets[0])).Online == true, "unrelated logical processor remains readable");
        platform.Records = original;
        var fresh = await access.CpuCores.List();
        Check(fresh[^1] != removed && (await access.Get(fresh[^1])).LogicalIndex == 64, "reappearing processor receives a fresh handle");
        platform.Failure = new Win32Exception(5);
        await Error(ErrorCode.PermissionDenied, () => access.CpuCores.List());
        var partial = await access.Get(Entities.Cpu);
        Check(partial.PhysicalCoreCount is null && partial.ProcessorPackageCount is null && partial.AvailableLogicalProcessorCount > 0, "partial CPU failure retains independent process availability");
        platform.Failure = null;
        Check((await access.CpuCores.List()).SequenceEqual(fresh), "failed inventory did not fabricate removal");
        await Error(ErrorCode.EntityRemoved, () => access.Get(removed));
    }

    private static async Task InvalidResponses()
    {
        var platform = new CpuPlatformFixture();var valid = platform.Records;
        using var access = new DeviceAccess(new WindowsCollector(cpuPlatform: platform));var targets = await access.CpuCores.List();
        foreach(var invalid in new byte[][][] {
            [Words(0, 0)], [Words(0, 48)], [Relation(0, (0, 0))], [Relation(0, (0, 3)), Relation(0, (0, 1))],
            [Relation(0, (0, 3)), Relation(3, (0, 4))], [Relation(0, (0, 3)), Relation(3, (0, 3)), Relation(3, (0, 1))],
            [Relation(0, (0, 3)), Relation(3, (0, 1))], [Relation(0, (0, 3)), Relation(3, (0, 1)), Relation(3, (0, 2))]
        }) {
            platform.Records = invalid;await Error(ErrorCode.ReadFailed, () => access.CpuCores.List());
            platform.Records = valid;Check((await access.CpuCores.List()).SequenceEqual(targets), "invalid native data cannot retire valid targets");
        }
        platform.Records = [..valid, Words(777, 8)];Check((await access.CpuCores.List()).Length == 5, "unrelated future native relationship does not change CPU fields");
        platform.Records = [Relation(0, (0, 3)), Relation(3, (0, 3))];var first = (await access.CpuCores.List())[0];
        foreach(var invalid in new[] {Words(0, 4800), Words(0, 4800, 2400, 0, 0, 0, 0, 4800, 2400, 0, 0, 0), Words(0, 4800, 2400, 0, 0, 0, 99, 4800, 2400, 0, 0, 0)}) {
            platform.Power = invalid;var snapshot = await access.Get(first);
            Check(snapshot.Online == true && snapshot.CurrentClockHz is null && snapshot.MaximumClockHz is null, "ambiguous clock records cannot select a processor or erase topology");
        }
    }

    private static async Task Error(ErrorCode code, Func<Task> action)
    {
        try {await action();throw new Exception("Expected " + code);} catch (DeviceReadoutException error) {Check(error.Code == code, $"expected {code}, got {error.Code}");}
    }

    private static async Task ClockFields()
    {
        var platform = new CpuPlatformFixture {
            Records = [Relation(0, (0, 3)), Relation(3, (0, 3))],
            Power = Words(1, 5200, 0, 2600, 0, 0, 0, 4800, 2400, 1600, 0, 0)
        };
        using var access = new DeviceAccess(new WindowsCollector(cpuPlatform: platform));
        var targets = await access.CpuCores.List();
        var first = await access.Get(targets[0]);var second = await access.Get(targets[1]);
        Check(first.MaximumClockHz == 4_800_000_000 && first.CurrentClockHz == 2_400_000_000, "MHz converts to Hz without integer overflow or thermal-limit substitution");
        Check(second.MaximumClockHz == 5_200_000_000 && second.CurrentClockHz == 0, "native processor number selects values and real zero is retained");
        platform.Power = null;
        var missing = await access.Get(targets[0]);
        Check(missing.CurrentClockHz is null && missing.MaximumClockHz is null && missing.CoreIndex == 0 && missing.Online == true, "optional unavailable frequency retains topology");
    }

    private static async Task TopologyFields()
    {
        var platform = new CpuPlatformFixture();
        var callerThread = Environment.CurrentManagedThreadId;
        using var access = new DeviceAccess(new WindowsCollector(cpuPlatform: platform));
        Check(platform.Threads.Count == 0, "inert CPU collector construction");
        var cores = await access.CpuCores.List();Check(cores.Length == 5, "five logical processors in two groups");
        var snapshots = new List<CpuCoreSnapshot>();
        foreach (var core in cores) snapshots.Add(await access.Get(core));
        Check(snapshots.Select(core => core.LogicalIndex).SequenceEqual(new int?[] {0, 1, 2, 3, 64}), "group-aware stable logical indices");
        Check(snapshots.Select(core => core.CoreIndex).SequenceEqual(new int?[] {0, 0, 1, 1, 2}), "SMT siblings share a physical core");
        Check(snapshots.Select(core => core.PackageIndex).SequenceEqual(new int?[] {0, 0, 0, 0, 1}), "native package relationship");
        Check(snapshots.All(core => core.Online == true && core.CurrentClockHz is null && core.MaximumClockHz is null), "active membership does not fabricate clocks");
        var cpu = await access.Get(Entities.Cpu);
        Check(cpu.LogicalProcessorCount == 5 && cpu.PhysicalCoreCount == 3 && cpu.ProcessorPackageCount == 2, "system topology counts are distinct");
        Check(cpu.AvailableLogicalProcessorCount is > 0, "process availability retains its independent live source");
        Check(await access.CpuCores.Current() is null, "no arbitrary default CPU");
        Check((await access.Capabilities.Get(cores[0])).Watchable == true, "CPU core supports polling");
        platform.Records = platform.Records.Reverse().ToArray();
        Check((await access.CpuCores.List()).SequenceEqual(cores), "native record ordering does not change handles");
        Check((await access.Get(cores[0])).CoreIndex == 0 && (await access.Get(cores[4])).PackageIndex == 1, "record ordering does not renumber relationships");
        Check(platform.Threads.Distinct().Count() == 1 && platform.Threads.All(thread => thread != callerThread), "native queries stay on the collection worker");
    }

    private sealed class CpuPlatformFixture : IWindowsCpuPlatform
    {
        public int PointerSize => 8;
        internal readonly List<int> Threads = [];
        internal byte[]? Power;
        internal Exception? Failure;
        internal byte[][] Records = [Relation(0, (0, 3)), Relation(0, (0, 12)), Relation(0, (1, 1)), Relation(3, (0, 15)), Relation(3, (1, 1))];
        public byte[] Topology(CancellationToken token) {Threads.Add(Environment.CurrentManagedThreadId);token.ThrowIfCancellationRequested();if (Failure is not null) throw Failure;return Records.SelectMany(record => record).ToArray();}
        public byte[]? PowerInformation(int count, CancellationToken token) {Threads.Add(Environment.CurrentManagedThreadId);token.ThrowIfCancellationRequested();return Power?.ToArray();}
    }
    private static byte[] Words(params uint[] values)
    {
        var bytes = new byte[values.Length * 4];
        for (var index = 0; index < values.Length; index++) BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(index * 4), values[index]);
        return bytes;
    }
    private static byte[] Relation(uint kind, params (ushort Group, ulong Mask)[] masks)
    {
        var data = new byte[32 + masks.Length * 16];
        BinaryPrimitives.WriteUInt32LittleEndian(data, kind);BinaryPrimitives.WriteUInt32LittleEndian(data.AsSpan(4), (uint)data.Length);
        BinaryPrimitives.WriteUInt16LittleEndian(data.AsSpan(30), (ushort)masks.Length);
        for (var index = 0; index < masks.Length; index++) {
            BinaryPrimitives.WriteUInt64LittleEndian(data.AsSpan(32 + index * 16), masks[index].Mask);
            BinaryPrimitives.WriteUInt16LittleEndian(data.AsSpan(40 + index * 16), masks[index].Group);
        }
        return data;
    }
    private static void Check(bool condition, string message) {if (!condition) throw new Exception(message);}
}
