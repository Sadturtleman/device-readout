using System.ComponentModel;
using System.Buffers.Binary;
using System.Diagnostics;
using System.Numerics;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using Microsoft.Win32.SafeHandles;
using DeviceReadout;
using DeviceReadout.Windows;

[SupportedOSPlatform("windows")]
internal static class WindowsCpuAvailabilityTests
{
    internal static IEnumerable<(string Name, Func<Task> Run)> Cases() => [
        ("Windows CPU availability follows native affinity, CPU-set, polling and Job changes in an isolated child process", NativeChild),
        ("Windows CPU availability respects reservations, hard affinity and distinct logical processors", AvailabilityFields),
        ("Windows CPU ambiguous or failed availability remains null without discarding other CPU fields", AvailabilityFailures)
    ];
    private static async Task AvailabilityFields()
    {
        var platform = new AvailabilityFixture();var caller = Environment.CurrentManagedThreadId;
        using var access = new DeviceAccess(new WindowsCollector(cpuAvailabilityPlatform: platform));
        if (platform.Threads.Count != 0) throw new Exception("Availability construction must be inert.");
        async Task Expect(int? count) {if ((await access.Get(Entities.Cpu)).AvailableLogicalProcessorCount != count) throw new Exception("Unexpected live availability count.");}
        await Expect(3); // Parked CPU 1 is online, CPU 2 belongs to another process, CPU 3 belongs to us.
        platform.Selected = [102, 104];await Expect(2);
        platform.State = platform.State with {ProcessMask = 1};await Expect(1); // Hard affinity overrides the disjoint soft assignment.
        platform.State = platform.State with {ProcessMask = 15};platform.Selected = [103];await Expect(3); // Unusable reservation assignment is ignored by Windows.
        platform.Data = [..CpuSet(101, 0, 0), ..CpuSet(102, 1, 0), ..CpuSet(103, 2, 0), ..CpuSet(104, 3, 0), ..CpuSet(105, 0, 0)];
        platform.Selected = [101, 105];await Expect(1); // Two virtual sets with the same home processor are one logical processor.
        if (platform.Threads.Distinct().Count() != 1 || platform.Threads.Contains(caller)) throw new Exception("Availability queries escaped the collection lane.");
    }
    private static async Task AvailabilityFailures()
    {
        var platform = new AvailabilityFixture();using var access = new DeviceAccess(new WindowsCollector(cpuAvailabilityPlatform: platform));
        async Task Missing() {
            var snapshot = await access.Get(Entities.Cpu);
            if (snapshot.AvailableLogicalProcessorCount is not null || snapshot.LogicalProcessorCount is not > 0 || snapshot.PhysicalCoreCount is not > 0)
                throw new Exception("Optional availability failure must preserve independent topology.");
        }
        var valid = platform.Data;var affinity = platform.State;
        platform.Selected = [999];await Missing();platform.Selected = [];
        platform.State = affinity with {ActiveGroups = 2};await Missing();
        platform.State = affinity with {MaskWidth = 32, ActiveProcessors = 64};await Missing();
        platform.State = affinity with {ProcessMask = 16};await Missing();platform.State = affinity;
        foreach (var invalid in new[] {new byte[7], CpuSet(101, 0, 0), new byte[32], CpuSet(101, 0, 0x80), CpuSet(101, 64, 0)}) {
            platform.Data = invalid;await Missing();
        }
        platform.Data = valid;platform.Failure = new Win32Exception(5);await Missing();platform.Failure = null;
        platform.ChangeDuringRead = true;await Missing();
        platform.ChangeDuringRead = false;platform.State = affinity;platform.ChangeSelectionDuringRead = true;await Missing();
    }
    private sealed class AvailabilityFixture : IWindowsCpuAvailabilityPlatform
    {
        internal WindowsProcessAffinity State = new(1, 4, 64, 15, 15);
        internal uint[] Selected = [];
        internal byte[] Data = [..CpuSet(101, 0, 0), ..CpuSet(102, 1, 1), ..CpuSet(103, 2, 2), ..CpuSet(104, 3, 6)];
        internal Exception? Failure;
        internal bool ChangeDuringRead, ChangeSelectionDuringRead;
        internal readonly List<int> Threads = [];
        private void Record(CancellationToken token) {Threads.Add(Environment.CurrentManagedThreadId);token.ThrowIfCancellationRequested();if (Failure is not null) throw Failure;}
        public WindowsProcessAffinity Affinity(CancellationToken token) {Record(token);return State;}
        public uint[] DefaultCpuSets(CancellationToken token) {Record(token);return Selected.ToArray();}
        public byte[] CpuSetInformation(CancellationToken token) {Record(token);if (ChangeDuringRead) State = State with {ProcessMask = 1};if (ChangeSelectionDuringRead) Selected = [104];return Data.ToArray();}
    }
    private static byte[] CpuSet(uint id, byte logical, byte flags)
    {
        var bytes = new byte[32];BinaryPrimitives.WriteUInt32LittleEndian(bytes, 32);BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(8), id);
        bytes[14] = logical;bytes[19] = flags;return bytes;
    }
    private static async Task NativeChild()
    {
        var start = new ProcessStartInfo(Environment.ProcessPath!) {UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true};
        if (string.Equals(Path.GetFileNameWithoutExtension(Environment.ProcessPath), "dotnet", StringComparison.OrdinalIgnoreCase))
            start.ArgumentList.Add(Assembly.GetExecutingAssembly().Location);
        start.ArgumentList.Add("--cpu-availability-child");
        using var child = Process.Start(start) ?? throw new Exception("Could not start the owned CPU fixture.");
        var output = child.StandardOutput.ReadToEndAsync();var error = child.StandardError.ReadToEndAsync();
        try {
            await child.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(20));
            var stdout = await output;var stderr = await error;
            if (child.ExitCode != 0) throw new Exception($"CPU fixture exited {child.ExitCode}: {stdout} {stderr}");
            Console.WriteLine(stdout.Trim());
        } finally {if (!child.HasExited) {child.Kill(entireProcessTree: true);await child.WaitForExitAsync();}}
    }

    internal static async Task RunChild()
    {
        if (!GetProcessAffinityMask(-1, out var original, out _)) throw new Win32Exception(Marshal.GetLastPInvokeError());
        var mask = (ulong)original;
        if (BitOperations.PopCount(mask) < 2) throw new Exception("The native CPU fixture needs at least two available processors.");
        var first = 1UL << BitOperations.TrailingZeroCount(mask);
        var defaultSets = ReadDefaultSets();var selectedSet = FindCpuSet((byte)BitOperations.TrailingZeroCount(mask));
        var startup = Environment.ProcessorCount;
        using var access = WindowsDeviceAccess.Create();
        _ = await access.Get(Entities.Cpu);
        try {
            if (!SetProcessAffinityMask(-1, (nuint)first)) throw new Win32Exception(Marshal.GetLastPInvokeError());
            var restricted = await access.Get(Entities.Cpu);
            if (restricted.AvailableLogicalProcessorCount != 1) throw new Exception($"Live affinity expected 1, got {restricted.AvailableLogicalProcessorCount}; runtime startup count={startup}.");
            AssertAffinity((nuint)first);
            if (!SetProcessAffinityMask(-1, original)) throw new Win32Exception(Marshal.GetLastPInvokeError());
            var restored = await access.Get(Entities.Cpu);
            if (restored.AvailableLogicalProcessorCount != BitOperations.PopCount(mask)) throw new Exception("Restored affinity was not observed.");
            if (!SetProcessDefaultCpuSets(-1, [selectedSet], 1)) throw new Win32Exception(Marshal.GetLastPInvokeError());
            var selected = await access.Get(Entities.Cpu);
            if (selected.AvailableLogicalProcessorCount != 1) throw new Exception($"Default CPU set expected 1, got {selected.AvailableLogicalProcessorCount}.");
            AssertAffinity(original);
            if (!ReadDefaultSets().SequenceEqual(new[] {selectedSet})) throw new Exception("SDK read changed the application's CPU-set selection.");
            var second = 1UL << BitOperations.TrailingZeroCount(mask & ~first);var pair = first | second;
            if (!SetProcessAffinityMask(-1, (nuint)second)) throw new Win32Exception(Marshal.GetLastPInvokeError());
            if ((await access.Get(Entities.Cpu)).AvailableLogicalProcessorCount != 1) throw new Exception("Conflicting soft CPU set must not erase the hard-affinitized processor.");
            AssertAffinity((nuint)second);
            if (!SetProcessAffinityMask(-1, original)) throw new Win32Exception(Marshal.GetLastPInvokeError());
            if (!SetProcessDefaultCpuSets(-1, [], 0)) throw new Win32Exception(Marshal.GetLastPInvokeError());
            if ((await access.Get(Entities.Cpu)).AvailableLogicalProcessorCount != BitOperations.PopCount(mask)) throw new Exception("Cleared CPU-set selection was not observed.");
            await using (var stream = access.WithPollInterval(TimeSpan.FromMilliseconds(25)).Watch(Entities.Cpu).GetAsyncEnumerator()) {
                if (!await stream.MoveNextAsync()) throw new Exception("CPU polling did not start.");
                if (!SetProcessAffinityMask(-1, (nuint)pair)) throw new Win32Exception(Marshal.GetLastPInvokeError());
                do {if (!await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(3))) throw new Exception("CPU polling ended before affinity change.");} while (stream.Current.AvailableLogicalProcessorCount != 2);
                if (!await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(3)) || stream.Current.AvailableLogicalProcessorCount != 2) throw new Exception("Equal CPU availability sample was not preserved.");
            }
            if (!SetProcessAffinityMask(-1, original)) throw new Win32Exception(Marshal.GetLastPInvokeError());
            await JobLimits(access, original, (nuint)pair);
            Console.WriteLine($"Native CPU availability child: startup={startup}, affinity=1, restored={restored.AvailableLogicalProcessorCount}, default set=1, polling=2, Job affinity=2; CPU-time cap did not become a processor count.");
        } finally {
            if (!SetProcessDefaultCpuSets(-1, defaultSets, (uint)defaultSets.Length)) throw new Win32Exception(Marshal.GetLastPInvokeError());
            if (!SetProcessAffinityMask(-1, original)) throw new Win32Exception(Marshal.GetLastPInvokeError());
        }
    }
    private static void AssertAffinity(nuint expected)
    {
        if (!GetProcessAffinityMask(-1, out var actual, out _)) throw new Win32Exception(Marshal.GetLastPInvokeError());
        if (actual != expected) throw new Exception("SDK read changed the application's affinity.");
    }
    private static async Task JobLimits(DeviceAccess access, nuint original, nuint pair)
    {
        using var job = CreateJobObject(0, null);if (job.IsInvalid) throw new Win32Exception(Marshal.GetLastPInvokeError());
        var rate = new JobRate {Flags = 5, Rate = 5000};
        var limits = new JobLimitsInfo {Flags = 0x10, Affinity = original};
        try {
            if (!SetJobLimits(job, 2, ref limits, (uint)Marshal.SizeOf<JobLimitsInfo>()) || !AssignProcessToJobObject(job, -1)) throw new Win32Exception(Marshal.GetLastPInvokeError());
            if (!SetJobRate(job, 15, ref rate, 8)) throw new Win32Exception(Marshal.GetLastPInvokeError());
            if ((await access.Get(Entities.Cpu)).AvailableLogicalProcessorCount != BitOperations.PopCount((ulong)original)) throw new Exception("CPU time budget is not a logical processor count.");
            limits.Affinity = pair;if (!SetJobLimits(job, 2, ref limits, (uint)Marshal.SizeOf<JobLimitsInfo>())) throw new Win32Exception(Marshal.GetLastPInvokeError());
            if ((await access.Get(Entities.Cpu)).AvailableLogicalProcessorCount != 2) throw new Exception("Live Job affinity was not reflected.");
        } finally {
            rate = default;limits.Affinity = original;
            if (!SetJobRate(job, 15, ref rate, 8) || !SetJobLimits(job, 2, ref limits, (uint)Marshal.SizeOf<JobLimitsInfo>())) throw new Win32Exception(Marshal.GetLastPInvokeError());
        }
    }
    [StructLayout(LayoutKind.Sequential)] private struct JobRate {public uint Flags, Rate;}
    [StructLayout(LayoutKind.Sequential)] private struct JobLimitsInfo
    {
        public long ProcessTime, JobTime;public uint Flags;public nuint MinimumWorkingSet, MaximumWorkingSet;
        public uint ProcessLimit;public nuint Affinity;public uint Priority, Scheduling;
    }
    private static uint[] ReadDefaultSets()
    {
        if (GetProcessDefaultCpuSets(-1, null, 0, out var length)) return [];
        if (Marshal.GetLastPInvokeError() != 122) throw new Win32Exception(Marshal.GetLastPInvokeError());
        var sets = new uint[length];if (!GetProcessDefaultCpuSets(-1, sets, length, out length)) throw new Win32Exception(Marshal.GetLastPInvokeError());return sets[..(int)length];
    }
    private static uint FindCpuSet(byte logical)
    {
        _ = GetSystemCpuSetInformation(null, 0, out var length, -1, 0);
        if (Marshal.GetLastPInvokeError() != 122 || length > 1024 * 1024) throw new Exception("Cannot size native CPU-set fixture.");
        var data = new byte[length];if (!GetSystemCpuSetInformation(data, length, out length, -1, 0)) throw new Win32Exception(Marshal.GetLastPInvokeError());
        for (var offset = 0; offset < length;) {
            var size = BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(offset));
            if (size < 32 || size > length - offset) throw new Exception("Invalid native CPU-set fixture response.");
            if (BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(offset + 4)) == 0 && BinaryPrimitives.ReadUInt16LittleEndian(data.AsSpan(offset + 12)) == 0 && data[offset + 14] == logical)
                return BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(offset + 8));
            offset += (int)size;
        }
        throw new Exception("Could not find the selected native CPU set.");
    }
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetProcessAffinityMask(nint process, out nuint processMask, out nuint systemMask);
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetProcessAffinityMask(nint process, nuint mask);
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetProcessDefaultCpuSets(nint process, [Out] uint[]? ids, uint count, out uint required);
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetProcessDefaultCpuSets(nint process, uint[] ids, uint count);
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetSystemCpuSetInformation([Out] byte[]? data, uint length, out uint required, nint process, uint flags);
    [DllImport("kernel32.dll", EntryPoint = "CreateJobObjectW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateJobObject(nint security, string? name);
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AssignProcessToJobObject(SafeFileHandle job, nint process);
    [DllImport("kernel32.dll", EntryPoint = "SetInformationJobObject", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetJobLimits(SafeFileHandle job, uint kind, ref JobLimitsInfo info, uint length);
    [DllImport("kernel32.dll", EntryPoint = "SetInformationJobObject", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetJobRate(SafeFileHandle job, uint kind, ref JobRate info, uint length);
}
