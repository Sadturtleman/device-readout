using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using DeviceReadout;
using DeviceReadout.Windows;

[SupportedOSPlatform("windows")]
internal static class WindowsIdentityTests
{
    internal static IEnumerable<(string Name, Func<Task> Run)> Cases() => [
        ("Windows publisher identity preserves native bytes/source and polls on the worker without caching snapshots", IdentityFields),
        ("Windows identity fields preserve partial availability and unknown sources without inventing identifiers", IdentityPartialFields),
        ("Windows identity rejects invalid native buffers and releases failure-path interface references", IdentityBuffers),
        ("Windows identity deadlines, cancellation and context closure leave the caller responsive and discard late reports", IdentityCancellation),
        ("real Windows publisher identity reads and polls with balanced worker-owned WinRT lifetime", ActualIdentity)
    ];
    private static async Task IdentityFields()
    {
        var runtime = new IdentityRuntimeFixture();var caller = Environment.CurrentManagedThreadId;
        using var access = new DeviceAccess(new WindowsCollector(identityRuntime: runtime));
        Check(runtime.Initializations == 0 && runtime.Reads == 0, "identity construction is inert");
        var snapshot = await access.Get(Entities.WindowsPublisherIdentity);
        Check(snapshot.PublisherId == "000102ff" && snapshot.Source == WindowsIdentitySource.Tpm, "native buffer bytes use lossless lowercase hex and native source mapping");
        Check((await access.Capabilities.Get(Entities.WindowsPublisherIdentity)).Readable == true, "publisher identity is readable");
        await using (var stream = access.WithPollInterval(TimeSpan.FromMilliseconds(25)).Watch(Entities.WindowsPublisherIdentity).GetAsyncEnumerator()) {
            Check(await stream.MoveNextAsync() && stream.Current.PublisherId == "000102ff", "identity initial watch state");
            Check(await stream.MoveNextAsync() && stream.Current.PublisherId == "000102ff", "equal polled identity is retained");
            runtime.Source = 2;
            using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(2));
            do {Check(await stream.MoveNextAsync().AsTask().WaitAsync(deadline.Token), "identity watch remains open");} while (stream.Current.Source != WindowsIdentitySource.Uefi);
        }
        Check(runtime.Reads >= 4 && runtime.References.Where(pair => pair.Key != runtime.Factory).All(pair => pair.Value == 0), "each read releases report and buffer references");
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.Initializations == 1 && runtime.Uninitializations == 1 && runtime.References.Values.All(value => value == 0), "runtime and factory are balanced at context closure");
        Check(runtime.Threads.Distinct().Count() == 1 && !runtime.Threads.Contains(caller), "identity calls and release stay on one worker");
    }
    private static async Task IdentityPartialFields()
    {
        var runtime = new IdentityRuntimeFixture();
        using var access = new DeviceAccess(new WindowsCollector(identityRuntime: runtime));
        runtime.IdResult = unchecked((int)0x80070005);
        var partial = await access.Get(Entities.WindowsPublisherIdentity);
        Check(partial.PublisherId is null && partial.Source == WindowsIdentitySource.Tpm, "denied ID does not erase readable source");
        runtime.IdResult = 0;runtime.SourceResult = unchecked((int)0x80004005);
        partial = await access.Get(Entities.WindowsPublisherIdentity);
        Check(partial.PublisherId == "000102ff" && partial.Source is null, "unreadable source does not erase readable ID");
        runtime.SourceResult = 0;
        foreach (var source in new[] {0, 99, -1}) {
            runtime.Source = source;partial = await access.Get(Entities.WindowsPublisherIdentity);
            Check(partial.PublisherId == "000102ff" && partial.Source is null, "unknown native source stays null");
        }
        runtime.Source = 3;
        Check((await access.Get(Entities.WindowsPublisherIdentity)).Source == WindowsIdentitySource.Registry, "native Registry is 3, independent of SDK enum ordinals");
        runtime.Bytes = [];
        Check((await access.Get(Entities.WindowsPublisherIdentity)).PublisherId is null, "empty ID is absent, not an invented identifier");
        runtime.NullBuffer = true;
        Check((await access.Get(Entities.WindowsPublisherIdentity)).PublisherId is null, "null buffer is absent");
        runtime.NullBuffer = false;runtime.Bytes = [0, 0];
        Check((await access.Get(Entities.WindowsPublisherIdentity)).PublisherId == "0000", "nonempty zero bytes are preserved");
        runtime.IdResult = unchecked((int)0x80070005);runtime.SourceResult = unchecked((int)0x80004005);
        await Error(ErrorCode.PermissionDenied, () => access.Get(Entities.WindowsPublisherIdentity));
        runtime.IdResult = unchecked((int)0x80004005);
        await Error(ErrorCode.ReadFailed, () => access.Get(Entities.WindowsPublisherIdentity));
        runtime.IdResult = 0;runtime.SourceResult = 0;
        Check((await access.Get(Entities.WindowsPublisherIdentity)).PublisherId == "0000", "a new explicit read can succeed after an error");
        Check(runtime.References.Where(pair => pair.Key != runtime.Factory).All(pair => pair.Value == 0), "partial and failed reads release every returned interface");
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.References.Values.All(value => value == 0), "all identity references released");
    }
    private static async Task IdentityBuffers()
    {
        var runtime = new IdentityRuntimeFixture();
        using var access = new DeviceAccess(new WindowsCollector(identityRuntime: runtime));
        async Task UnavailableId()
        {
            var value = await access.Get(Entities.WindowsPublisherIdentity);
            Check(value.PublisherId is null && value.Source == WindowsIdentitySource.Tpm, "unusable ID buffer preserves independent source");
            Check(runtime.References.Where(pair => pair.Key != runtime.Factory).All(pair => pair.Value == 0), "failure returned interface references are released");
        }
        runtime.Capacity = 1;await UnavailableId();runtime.Capacity = null;
        runtime.Length = 65537;runtime.Capacity = 65537;await UnavailableId();runtime.Length = runtime.Capacity = null;
        runtime.LengthResult = unchecked((int)0x80004005);await UnavailableId();runtime.LengthResult = 0;
        runtime.CapacityResult = unchecked((int)0x80004005);await UnavailableId();runtime.CapacityResult = 0;
        runtime.QueryResult = unchecked((int)0x80004002);await UnavailableId();runtime.QueryResult = 0;
        runtime.NullByteAccess = true;await UnavailableId();runtime.NullByteAccess = false;
        runtime.ByteResult = unchecked((int)0x80004005);await UnavailableId();runtime.ByteResult = 0;
        runtime.NullBytes = true;await UnavailableId();runtime.NullBytes = false;
        runtime.ReportResult = unchecked((int)0x80070005);
        await Error(ErrorCode.PermissionDenied, () => access.Get(Entities.WindowsPublisherIdentity));
        runtime.ReportResult = unchecked((int)0x80004005);
        await Error(ErrorCode.ReadFailed, () => access.Get(Entities.WindowsPublisherIdentity));
        runtime.ReportResult = 0;runtime.NullInfo = true;
        await Error(ErrorCode.ReadFailed, () => access.Get(Entities.WindowsPublisherIdentity));
        runtime.NullInfo = false;
        Check((await access.Get(Entities.WindowsPublisherIdentity)).PublisherId == "000102ff", "fresh valid data after native failures");
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.References.Values.All(value => value == 0), "invalid buffers and whole-query failures leak no references");
    }
    private enum StopRead {Deadline, Cancellation, ContextClosure}
    private static async Task IdentityCancellation()
    {
        foreach (var stop in Enum.GetValues<StopRead>()) {
            var runtime = new IdentityRuntimeFixture();runtime.ContinueRead.Reset();
            var caller = Environment.CurrentManagedThreadId;
            using var access = new DeviceAccess(new WindowsCollector(identityRuntime: runtime));
            using var cancellation = new CancellationTokenSource();
            var configured = stop == StopRead.Deadline ? access.WithReadTimeout(TimeSpan.FromMilliseconds(100)) : access;
            var pending = configured.Get(Entities.WindowsPublisherIdentity, cancellation.Token);
            try {
                await runtime.ReadStarted.Task.WaitAsync(TimeSpan.FromSeconds(2));
                await Task.Delay(10);Check(!pending.IsCompleted, "host heartbeat progresses during pending native work");
                if (stop == StopRead.Deadline) await Error(ErrorCode.ReadTimeout, () => pending.WaitAsync(TimeSpan.FromSeconds(2)));
                else {
                    if (stop == StopRead.Cancellation) cancellation.Cancel();else access.Dispose();
                    var canceled = false;
                    try {await pending.WaitAsync(TimeSpan.FromSeconds(2));} catch (OperationCanceledException) {canceled = true;}
                    Check(canceled, "cancel/close completes before native work is released");
                }
                access.Dispose();Check(!runtime.Stopped.Task.IsCompleted, "native lifetime is retained until the borrowed call returns");
            } finally {runtime.ContinueRead.Set();access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));}
            Check(runtime.IdReads == 0, "late canceled reports cause no follow-up property collection");
            Check(runtime.Uninitializations == 1 && runtime.References.Values.All(value => value == 0), "late report/factory resources are balanced");
            Check(runtime.Threads.Distinct().Count() == 1 && !runtime.Threads.Contains(caller), "late cleanup stays on the worker");
            runtime.ContinueRead.Dispose();
        }
    }
    private static async Task ActualIdentity()
    {
        var runtime = new ActualIdentityRuntime();var caller = Environment.CurrentManagedThreadId;
        using var access = new DeviceAccess(new WindowsCollector(identityRuntime: runtime));
        var first = await access.Get(Entities.WindowsPublisherIdentity);
        Check(first.PublisherId is {Length: > 0} && first.PublisherId.Length % 2 == 0
            && first.PublisherId.All(value => value is >= '0' and <= '9' or >= 'a' and <= 'f'), "native ID is nonempty lossless hex");
        Check(first.Source is not null, "native source is recognized on this host");
        var next = await access.Get(Entities.WindowsPublisherIdentity);
        Check(next.PublisherId == first.PublisherId && next.Source == first.Source, "same context native ID remains stable across immediate reads");
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        await using (var stream = access.WithPollInterval(TimeSpan.FromMilliseconds(25)).Watch(Entities.WindowsPublisherIdentity, deadline.Token).GetAsyncEnumerator()) {
            for (var index = 0; index < 2; index++) Check(await stream.MoveNextAsync() && stream.Current.PublisherId == first.PublisherId, "actual initial/equal polled native identity");
        }
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.Initializations == 1 && runtime.Activations == 1 && runtime.Uninitializations == 1 && runtime.Releases >= 13, "native factory, reports, buffers and byte-access references released");
        Check(runtime.Threads.Distinct().Count() == 1 && !runtime.Threads.Contains(caller), "native WinRT calls/releases stay on the worker");
        Console.WriteLine($"Native Windows publisher identity: {first.PublisherId!.Length / 2} bytes, source={first.Source}; repeated get and equal polling verified; no ID value logged.");
    }
    private sealed class ActualIdentityRuntime : IWindowsIdentityRuntime
    {
        private readonly WindowsPublisherIdentity.IdentityRuntime runtime = new();
        internal readonly List<int> Threads = [];
        internal readonly TaskCompletionSource Stopped = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal int Initializations, Activations, Uninitializations, Releases;
        private void Record() => Threads.Add(Environment.CurrentManagedThreadId);
        public int Initialize() {Record();Initializations++;return runtime.Initialize();}
        public nint ActivateFactory() {Record();Activations++;return runtime.ActivateFactory();}
        public void Release(nint instance) {Record();Releases++;runtime.Release(instance);}
        public void Uninitialize() {Record();Uninitializations++;runtime.Uninitialize();Stopped.TrySetResult();}
    }
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int Query(nint instance, ref Guid iid, out nint result);
    private sealed class IdentityRuntimeFixture : IWindowsIdentityRuntime
    {
        private readonly List<Delegate> delegates = [];
        private readonly List<nint> allocations = [];
        internal readonly Dictionary<nint, int> References = [];
        internal readonly List<int> Threads = [];
        internal readonly TaskCompletionSource Stopped = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly nint Factory;
        internal readonly TaskCompletionSource ReadStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly ManualResetEventSlim ContinueRead = new(true);
        private readonly nint info, buffer, bytesAccess, data;
        internal int Initializations, Uninitializations, Reads, IdReads;
        internal int Source = 1;
        internal int IdResult, SourceResult, ReportResult, LengthResult, CapacityResult, QueryResult, ByteResult;
        internal bool NullBuffer, NullByteAccess, NullBytes, NullInfo;
        internal uint? Length, Capacity;
        internal byte[] Bytes = [0, 1, 2, 255];
        internal IdentityRuntimeFixture()
        {
            Factory = Interface(7);info = Interface(8);buffer = Interface(9);bytesAccess = Interface(4);
            data = Allocate(65536);
            Set(Factory, 6, new WinRtGetInterface((nint instance, out nint result) => {
                Record();Reads++;result = NullInfo ? 0 : Take(info);ReadStarted.TrySetResult();
                return ContinueRead.Wait(TimeSpan.FromSeconds(3)) ? ReportResult : unchecked((int)0x80004005);
            }));
            Set(info, 6, new WinRtGetInterface((nint instance, out nint result) => {Record();IdReads++;result = NullBuffer ? 0 : Take(buffer);return IdResult;}));
            Set(info, 7, new WinRtGetInt32((nint instance, out int result) => {Record();result = Source;return SourceResult;}));
            Set(buffer, 6, new WinRtGetUInt32((nint instance, out uint result) => {Record();result = Capacity ?? (uint)Bytes.Length;return CapacityResult;}));
            Set(buffer, 7, new WinRtGetUInt32((nint instance, out uint result) => {Record();result = Length ?? (uint)Bytes.Length;return LengthResult;}));
            Set(buffer, 0, new Query((nint instance, ref Guid iid, out nint result) => {
                Record();result = 0;
                if (iid != new Guid("905a0fef-bc53-11df-8c49-001e4fc686da")) return unchecked((int)0x80004002);
                result = NullByteAccess ? 0 : Take(bytesAccess);return QueryResult;
            }));
            Set(bytesAccess, 3, new WinRtGetInterface((nint instance, out nint result) => {Record();Marshal.Copy(Bytes, 0, data, Bytes.Length);result = NullBytes ? 0 : data;return ByteResult;}));
        }
        private nint Allocate(int size) {var memory = Marshal.AllocHGlobal(size);Marshal.Copy(new byte[size], 0, memory, size);allocations.Add(memory);return memory;}
        private nint Interface(int slots) {var pointer = Allocate(nint.Size);Marshal.WriteIntPtr(pointer, Allocate(slots * nint.Size));References[pointer] = 0;return pointer;}
        private void Set(nint instance, int slot, Delegate callback) {delegates.Add(callback);Marshal.WriteIntPtr(Marshal.ReadIntPtr(instance), slot * nint.Size, Marshal.GetFunctionPointerForDelegate(callback));}
        private nint Take(nint instance) {References[instance]++;return instance;}
        private void Record() => Threads.Add(Environment.CurrentManagedThreadId);
        public int Initialize() {Record();Initializations++;return 0;}
        public nint ActivateFactory() {Record();return Take(Factory);}
        public void Release(nint instance) {Record();if (--References[instance] < 0) throw new Exception("Identity reference released twice.");}
        public void Uninitialize() {Record();Uninitializations++;foreach(var memory in allocations) Marshal.FreeHGlobal(memory);allocations.Clear();Stopped.TrySetResult();}
    }
    private static async Task Error(ErrorCode code, Func<Task> action)
    {
        try {await action();} catch (DeviceReadoutException error) when (error.Code == code) {return;}
        throw new Exception($"Expected {code}.");
    }
    private static void Check(bool condition, string message) {if (!condition) throw new Exception(message);}
}
