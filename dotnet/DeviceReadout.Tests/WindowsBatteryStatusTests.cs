using System.Collections.Concurrent;
using System.ComponentModel;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Threading.Channels;
using Microsoft.Win32.SafeHandles;
using DeviceReadout;
using DeviceReadout.Windows;

internal static partial class WindowsBatteryTests
{
    private static async Task StatusRemovedPeers()
    {
        using var firstStatus = new StatusDeviceFixture();using var secondStatus = new StatusDeviceFixture();
        var devices = new ConcurrentQueue<IWindowsBatteryDevice>([firstStatus, secondStatus]);
        var platform = new BatteryPlatformFixture {StatusDevice = () => devices.TryDequeue(out var device) ? device : throw new Exception("unexpected native subscription")};
        var slot = new BatterySlotFixture();platform.Slots["battery"] = slot;
        using var access = new DeviceAccess(new WindowsCollector(platform, new WindowsPowerTests.PowerPlatformFixture(), new WindowsAggregateBatteryTests.UnavailablePlatform()));
        var target = (await access.Batteries.List())[0];
        await using var first = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(target).GetAsyncEnumerator();
        Check(await first.MoveNextAsync() && await first.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)), "initial and baseline of first watch");
        platform.Slots.Remove("battery");platform.Slots["BATTERY"] = slot;
        Check((await access.Batteries.List())[0] == target, "path casing alone preserves target identity");
        await using var second = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(target).GetAsyncEnumerator();
        Check(await second.MoveNextAsync() && await second.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)), "initial and baseline of second watch");
        secondStatus.Replies.Add(new Win32Exception(433));
        await Error(ErrorCode.EntityRemoved, async () => {await second.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));});
        var firstResult = first.MoveNextAsync().AsTask();
        try {await Error(ErrorCode.EntityRemoved, async () => {await firstResult.WaitAsync(TimeSpan.FromSeconds(1));});}
        finally {
            if (!firstResult.IsCompleted) access.Dispose();
            try {await firstResult;} catch (OperationCanceledException) { } catch (DeviceReadoutException) { }
        }
        await firstStatus.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(1));await secondStatus.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(1));
    }

    private static async Task StatusLifetimes()
    {
        using var firstStatus = new StatusDeviceFixture();using var secondStatus = new StatusDeviceFixture();
        var devices = new ConcurrentQueue<IWindowsBatteryDevice>([firstStatus, secondStatus]);
        var platform = new BatteryPlatformFixture {StatusDevice = () => devices.TryDequeue(out var device) ? device : throw new Exception("unexpected extra native subscription")};
        platform.Slots["battery"] = new BatterySlotFixture();
        using var access = new DeviceAccess(new WindowsCollector(platform, new WindowsPowerTests.PowerPlatformFixture(), new WindowsAggregateBatteryTests.UnavailablePlatform()));
        var target = (await access.Batteries.List())[0];
        var first = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(target).GetAsyncEnumerator();
        var second = access.WithPollInterval(TimeSpan.FromHours(2)).Watch(target).GetAsyncEnumerator();
        try {
            Check(await first.MoveNextAsync(), "first subscription starts");
            _ = await firstStatus.Requests.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
            _ = await firstStatus.Requests.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
            Check(await second.MoveNextAsync(), "second subscription starts independently");
            _ = await secondStatus.Requests.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
            _ = await secondStatus.Requests.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
            await first.DisposeAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
            await firstStatus.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(1));
            Check(!secondStatus.Stopped.Task.IsCompleted, "one subscriber cannot stop another native wait");
            secondStatus.Replies.Add(Words(2, 8000, 12000, unchecked((uint)-6000)));
            do {Check(await second.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)), "remaining subscription event");} while (second.Current.Level == 0.5);
            Check(second.Current.Level == 0.4, "remaining subscriber continues normally");
            access.Dispose();await secondStatus.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(1));
        } finally {await first.DisposeAsync();await second.DisposeAsync();}
    }

    private static async Task StatusNativeKernel()
    {
        using var io = new NativeStatusPipe();
        var platform = new BatteryPlatformFixture {StatusDevice = () => new WindowsBatteryStatusDevice(io)};
        platform.Slots["battery"] = new BatterySlotFixture();
        using var access = new DeviceAccess(new WindowsCollector(platform, new WindowsPowerTests.PowerPlatformFixture(), new WindowsAggregateBatteryTests.UnavailablePlatform()));
        var target = (await access.Batteries.List())[0];
        await io.Client.WriteAsync(Words(4, 10000, 12800, 6400));
        var stream = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(target).GetAsyncEnumerator();
        try {
            Check(await stream.MoveNextAsync(), "initial native read");
            _ = await io.Requests.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(2));
            await io.Client.WriteAsync(Words(2, 8000, 12000, unchecked((uint)-6000)));
            do {Check(await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(2)), "native completed snapshot");} while (stream.Current.Level == 0.5);
            Check(stream.Current.Level == 0.4 && stream.Current.State == BatteryState.Discharging, "native event buffer decoded");
            _ = await io.Requests.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(2));
        } finally {await stream.DisposeAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(2));}
        await io.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(io.CancellationResult == 0 && io.CompletionResult == 995, "actual CancelIoEx followed by ERROR_OPERATION_ABORTED completion");
        Check(io.Threads.Distinct().Count() == 1 && !platform.Threads.Contains(io.Threads[0]), "native completion and cancellation remain on status lane");
        Console.WriteLine("Native overlapped transport: private pipe completion and CancelIoEx/GetOverlappedResult cleanup passed; no physical battery involved.");
    }

    private sealed class NativeStatusPipe : IWindowsBatteryStatusIo
    {
        internal readonly NamedPipeClientStream Client;
        internal readonly Channel<bool> Requests = Channel.CreateUnbounded<bool>();
        internal readonly TaskCompletionSource Stopped = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly List<int> Threads = [];
        internal int? CancellationResult, CompletionResult;
        private readonly SafeFileHandle handle;
        private readonly WindowsBatteryStatusIo native;
        internal NativeStatusPipe()
        {
            var name = "DeviceReadout-status-test-" + Guid.NewGuid().ToString("N");
            handle = CreateNamedPipe(@"\\.\pipe\" + name, 0x40000001, 8, 1, 256, 256, 0, 0);
            if (handle.IsInvalid) {var error = Marshal.GetLastPInvokeError();handle.Dispose();throw new Win32Exception(error);}
            native = new WindowsBatteryStatusIo(handle);
            Client = new NamedPipeClientStream(".", name, PipeDirection.Out, PipeOptions.Asynchronous);
            try {
                Client.Connect(2000);
                var bytes = new byte[3 * IntPtr.Size + 8];var overlapped = Marshal.AllocHGlobal(bytes.Length);
                using var signal = new EventWaitHandle(false, EventResetMode.ManualReset);
                try {
                    Marshal.Copy(bytes, 0, overlapped, bytes.Length);Marshal.WriteIntPtr(overlapped, 2 * IntPtr.Size + 8, signal.SafeWaitHandle.DangerousGetHandle());
                    Check(!ConnectNamedPipe(handle, overlapped) && Marshal.GetLastPInvokeError() == 535, "private pipe already connected by owned client");
                } finally {Marshal.FreeHGlobal(overlapped);}
            } catch {Client.Dispose();handle.Dispose();throw;}
        }
        public int Submit(nint input, int inputSize, nint output, int outputSize, nint overlapped, out uint written)
        {
            Threads.Add(Environment.CurrentManagedThreadId);
            var result = ReadFile(handle, output, outputSize, out written, overlapped) ? 0 : Marshal.GetLastPInvokeError();
            if (Marshal.ReadInt32(input, 4) != 0) {Check(result == 997, "native read remains pending without supplied data");Requests.Writer.TryWrite(true);}
            return result;
        }
        public int Complete(nint overlapped, out uint written)
        {Threads.Add(Environment.CurrentManagedThreadId);var result = native.Complete(overlapped, out written);CompletionResult = result;return result;}
        public int Cancel(nint overlapped)
        {Threads.Add(Environment.CurrentManagedThreadId);var result = native.Cancel(overlapped);CancellationResult = result;return result;}
        public void Dispose()
        {
            if (Stopped.Task.IsCompleted) {Client.Dispose();return;}
            Threads.Add(Environment.CurrentManagedThreadId);native.Dispose();Stopped.TrySetResult();
        }
        [DllImport("kernel32.dll", EntryPoint = "CreateNamedPipeW", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateNamedPipe(string name, uint openMode, uint pipeMode, uint instances, uint outputSize, uint inputSize, uint timeout, nint security);
        [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ConnectNamedPipe(SafeFileHandle pipe, nint overlapped);
        [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ReadFile(SafeFileHandle pipe, nint buffer, int size, out uint written, nint overlapped);
    }

    private static async Task StatusFallback()
    {
        foreach (var unavailable in new[] {1, 50}) {
            using var status = new StatusDeviceFixture {Baseline = Words(2, uint.MaxValue, uint.MaxValue, 0)};
            var platform = new BatteryPlatformFixture {StatusDevice = () => status};platform.Slots["battery"] = new BatterySlotFixture();
            using var access = new DeviceAccess(new WindowsCollector(platform, new WindowsPowerTests.PowerPlatformFixture(), new WindowsAggregateBatteryTests.UnavailablePlatform()));
            var target = (await access.Batteries.List())[0];
            await using var stream = access.WithPollInterval(TimeSpan.FromMilliseconds(25)).Watch(target).GetAsyncEnumerator();
            Check(await stream.MoveNextAsync(), "initial battery");
            _ = await status.Requests.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
            var conditions = await status.Requests.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
            Check(U32(conditions, 8) == 2 && U32(conditions, 12) == 0 && U32(conditions, 16) == uint.MaxValue, "unknown capacity leaves both thresholds disabled");
            var unknownSeen = stream.Current.Level is null;
            while (!unknownSeen) {Check(await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)), "unknown capacity report");unknownSeen = stream.Current.Level is null;}
            Check(stream.Current.State == BatteryState.Discharging && stream.Current.ChargeRateMilliwatts == 0, "unknown capacity does not discard known status or zero rate");
            status.Replies.Add(new Win32Exception(unavailable));
            await status.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(1));
            Check(await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)) && stream.Current.Level == 0.5, "unsupported native wait retains serial polling");
            Check(await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)) && stream.Current.Level == 0.5, "unchanged poll samples continue");
        }
    }

    private static async Task StatusOverlapped()
    {
        using var io = new StatusIoFixture();
        var platform = new BatteryPlatformFixture {StatusDevice = () => new WindowsBatteryStatusDevice(io)};
        platform.Slots["battery"] = new BatterySlotFixture();
        using var access = new DeviceAccess(new WindowsCollector(platform, new WindowsPowerTests.PowerPlatformFixture(), new WindowsAggregateBatteryTests.UnavailablePlatform()));
        var target = (await access.Batteries.List())[0];
        var stream = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(target).GetAsyncEnumerator();
        try {
            Check(await stream.MoveNextAsync(), "initial native battery");
            _ = await io.Requests.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
            Check((await access.Get(target).WaitAsync(TimeSpan.FromSeconds(1))).Level == 0.5, "pending overlapped request leaves collection responsive");
            io.Finish(Words(2, 8000, 12000, unchecked((uint)-6000)));
            do {Check(await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)), "completed native status");} while (stream.Current.Level == 0.5);
            Check(stream.Current.Level == 0.4 && stream.Current.State == BatteryState.Discharging, "unmanaged output becomes typed snapshot");
            var rearmed = await io.Requests.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
            Check(U32(rearmed, 8) == 2 && U32(rearmed, 12) == 8000 && U32(rearmed, 16) == 8000, "next wait uses the delivered state");
            await stream.DisposeAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
            await io.Cancelled.Task.WaitAsync(TimeSpan.FromSeconds(1));
            Check(!io.Stopped.Task.IsCompleted, "cancellation alone cannot release pending native buffers or device");
            Check((await access.Get(target).WaitAsync(TimeSpan.FromSeconds(1))).Level == 0.5, "delayed cancellation completion cannot block other reads");
        } finally {
            await stream.DisposeAsync();io.Finish(null, 995);
        }
        await io.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(1));
        Check(io.Threads.Distinct().Count() == 1 && !platform.Threads.Contains(io.Threads[0]), "native issue, cancel, completion and close share the status lane");
    }

    private sealed class StatusIoFixture : IWindowsBatteryStatusIo
    {
        internal readonly Channel<byte[]> Requests = Channel.CreateUnbounded<byte[]>();
        internal readonly TaskCompletionSource Cancelled = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource Stopped = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly List<int> Threads = [];
        private readonly object gate = new();
        private EventWaitHandle? signal;
        private nint output, pending, input;
        private int error;
        private uint written;
        private void Record() => Threads.Add(Environment.CurrentManagedThreadId);
        public int Submit(nint input, int inputSize, nint output, int outputSize, nint overlapped, out uint written)
        {
            Record();var request = new byte[inputSize];Marshal.Copy(input, request, 0, request.Length);
            Check(inputSize == 20 && outputSize == 16 && U32(request) == 7, "native battery buffer layout");
            Check(Marshal.ReadIntPtr(overlapped) == 0 && Marshal.ReadIntPtr(overlapped, IntPtr.Size) == 0 && Marshal.ReadInt64(overlapped, 2 * IntPtr.Size) == 0, "zero-initialized native OVERLAPPED");
            if (U32(request, 4) == 0) {Marshal.Copy(Words(4, 10000, 12800, 6400), 0, output, 16);written = 16;return 0;}
            lock (gate) {
                Check(pending == 0, "at most one native status wait per device");
                this.input = input;this.output = output;pending = overlapped;this.written = 0;error = 0;
                signal = new EventWaitHandle(false, EventResetMode.ManualReset);
                signal.SafeWaitHandle = new SafeWaitHandle(Marshal.ReadIntPtr(overlapped, 2 * IntPtr.Size + 8), ownsHandle: false);
                Check(!signal.WaitOne(0), "native completion event starts unsignaled");
            }
            Requests.Writer.TryWrite(request);written = 0;return 997;
        }
        internal void Finish(byte[]? bytes, int result = 0)
        {
            lock (gate) {
                if (pending == 0) return;
                if (bytes is not null) Marshal.Copy(bytes, 0, output, bytes.Length);
                written = (uint)(bytes?.Length ?? 0);error = result;signal!.Set();
            }
        }
        public int Complete(nint overlapped, out uint written)
        {
            Record();EventWaitHandle completion;
            lock (gate) {Check(pending == overlapped, "matching pending operation");completion = signal!;}
            completion.WaitOne();
            lock (gate) {written = this.written;pending = 0;signal!.Dispose();signal = null;return error;}
        }
        public int Cancel(nint overlapped)
        {
            Record();lock (gate) {
                Check(pending == overlapped && Marshal.ReadInt32(input) == 7, "cancel targets the still-live operation and input");
                Cancelled.TrySetResult();return 0;
            }
        }
        public void Dispose()
        {
            if (Stopped.Task.IsCompleted) return;
            Record();lock (gate) {Check(pending == 0, "native storage cannot be freed while the driver still owns it");Stopped.TrySetResult();}
        }
    }

    private static async Task StatusFailures()
    {
        foreach (var (nativeError, expected) in new[] {(2, ErrorCode.EntityRemoved), (433, ErrorCode.EntityRemoved), (1167, ErrorCode.EntityRemoved), (5, ErrorCode.PermissionDenied), (87, ErrorCode.ReadFailed)}) {
            using var status = new StatusDeviceFixture();
            var platform = new BatteryPlatformFixture {StatusDevice = () => status};platform.Slots["battery"] = new BatterySlotFixture();
            using var access = new DeviceAccess(new WindowsCollector(platform, new WindowsPowerTests.PowerPlatformFixture(), new WindowsAggregateBatteryTests.UnavailablePlatform()));
            var target = (await access.Batteries.List())[0];
            await using var stream = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(target).GetAsyncEnumerator();
            Check(await stream.MoveNextAsync(), "initial status before driver error");
            _ = await status.Requests.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
            _ = await status.Requests.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
            status.Replies.Add(new Win32Exception(nativeError));
            await Error(expected, async () => {while (await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1))) { }});
            await status.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(1));
            if (expected == ErrorCode.EntityRemoved) {
                await Error(ErrorCode.EntityRemoved, () => access.Get(target));
                var fresh = (await access.Batteries.List())[0];
                Check(fresh != target && (await access.Get(fresh)).Present == true, "same path and tag require a fresh generation after observed removal");
                await Error(ErrorCode.EntityRemoved, () => access.Get(target));
            } else Check((await access.Get(target)).Present == true, "failed observation does not fabricate removal");
        }
    }

    private static async Task StatusEvents()
    {
        using var status = new StatusDeviceFixture();
        var platform = new BatteryPlatformFixture {StatusDevice = () => status};
        platform.Slots["battery"] = new BatterySlotFixture();
        using var access = new DeviceAccess(new WindowsCollector(platform, new WindowsPowerTests.PowerPlatformFixture(), new WindowsAggregateBatteryTests.UnavailablePlatform()));
        var target = (await access.Batteries.List())[0];
        var stream = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(target).GetAsyncEnumerator();
        try {
            Check(await stream.MoveNextAsync(), "initial selected battery snapshot");
            var initial = await status.Requests.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
            Check(U32(initial) == 7 && U32(initial, 4) == 0, "zero-wait baseline precedes change conditions");
            var waiting = await status.Requests.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1));
            Check(U32(waiting, 4) == uint.MaxValue && U32(waiting, 8) == 4 && U32(waiting, 12) == 10000 && U32(waiting, 16) == 10000, "state and exact known-capacity change conditions");
            Check((await access.Get(target).WaitAsync(TimeSpan.FromSeconds(1))).Level == 0.5, "pending native status wait does not monopolize collection worker");
            status.Replies.Add(Words(2, 8000, 12000, unchecked((uint)-6000)));
            status.Replies.Add(Words(4, 12000, 12000, 6000));
            status.Replies.Add(Words(4, 12000, 12000, 6000));
            var observed = new List<BatterySnapshot>();
            while (observed.Count < 3) {
                Check(await stream.MoveNextAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(1)), "native status snapshot");
                if (stream.Current.Level != 0.5) observed.Add(stream.Current);
            }
            Check(observed[0].Level == 0.4 && observed[0].State == BatteryState.Discharging && observed[0].ChargeRateMilliwatts == -6000, "captured discharge survives later driver state");
            Check(observed[1].Level == 0.6 && observed[1].State == BatteryState.Charging && observed[2].Level == 0.6, "ordered equal native reports retained");
            Check((await access.Get(target)).Level == 0.5, "event payload did not replace a fresh get");
        } finally {await stream.DisposeAsync();}
        await status.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(1));
        Check(status.Threads.Distinct().Count() == 1 && !platform.Threads.Contains(status.Threads[0]), "status wait and cleanup have their own lane");
    }

    private sealed class StatusDeviceFixture : IWindowsBatteryDevice
    {
        internal readonly Channel<byte[]> Requests = Channel.CreateUnbounded<byte[]>();
        internal readonly BlockingCollection<object> Replies = [];
        internal readonly TaskCompletionSource Stopped = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly List<int> Threads = [];
        internal byte[] Baseline = Words(4, 10000, 12800, 6400);
        private int reads;
        public byte[] Query(BatteryIoControl control, byte[] input, int outputSize, CancellationToken token)
        {
            Threads.Add(Environment.CurrentManagedThreadId);
            Check(control == BatteryIoControl.QueryStatus && input.Length == 20 && outputSize == 16 && U32(input) == 7, "selected read-only native status query");
            Requests.Writer.TryWrite(input.ToArray());
            if (reads++ == 0) return Baseline.ToArray();
            var reply = Replies.Take(token);return reply is Exception error ? throw error : (byte[])reply;
        }
        public void Dispose() {Threads.Add(Environment.CurrentManagedThreadId);Stopped.TrySetResult();}
    }
}
