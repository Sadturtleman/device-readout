using DeviceReadout;
using DeviceReadout.Windows;
using System.Runtime.InteropServices;

internal static partial class WindowsConnectivityTests
{
    private static async Task CellularRemovalHistory()
    {
        var runtime = new ConnectivityFixture();runtime.EnableCellular();var account = runtime.AddAccount("Original");
        using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime));
        var target = (await access.List(Entities.CellularSubscription)).Single();
        runtime.CellularChange(account.Id, WindowsCellularAccountChangeKind.Removed);
        runtime.CellularChange(account.Id, WindowsCellularAccountChangeKind.Added);
        var names = runtime.AccountNameReads;
        await Error(ErrorCode.EntityRemoved, () => access.Get(target));
        Check(runtime.AccountNameReads == names, "observed removal between reads prevents another field query on the old handle");
        var fresh = (await access.List(Entities.CellularSubscription)).Single();Check(!fresh.Equals(target), "same native account gets a new generation after observed removal");
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        await using (var stream = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(fresh, deadline.Token).GetAsyncEnumerator()) {
            Check(await stream.MoveNextAsync(), "initial current generation");account.Name = "Updated";
            runtime.CellularChange(account.Id, WindowsCellularAccountChangeKind.Updated);
            Check(await stream.MoveNextAsync() && stream.Current.CarrierName == "Updated", "account update supplies a native event without waiting for polling");
            runtime.CellularChange(account.Id, WindowsCellularAccountChangeKind.Removed);
            runtime.CellularChange(account.Id, WindowsCellularAccountChangeKind.Added);
            await Error(ErrorCode.EntityRemoved, async () => {await stream.MoveNextAsync();});
        }
        var next = (await access.List(Entities.CellularSubscription)).Single();
        runtime.OnAccountName = () => {
            runtime.CellularChange(account.Id, WindowsCellularAccountChangeKind.Removed);
            runtime.CellularChange(account.Id, WindowsCellularAccountChangeKind.Added);
        };
        await Error(ErrorCode.EntityRemoved, () => access.Get(next));runtime.OnAccountName = null;
        var final = (await access.List(Entities.CellularSubscription)).Single();
        Check(!final.Equals(next) && (await access.Get(final)).CarrierName == "Updated", "in-flight result crossing removal is discarded permanently");
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.CellularObservations == 1 && runtime.CellularObservationDisposals == 1 && runtime.CellularListener is null
            && runtime.References.Values.All(count => count == 0), "one context observation persists across reads and watches until worker disposal");
    }

    private static async Task CellularSharedWatcher()
    {
        using var native = new CellularWatcherFixture();var source = new WindowsCellularWatcher(native);
        var first = new ConnectivityFixture {CellularSource = source};first.EnableCellular();var firstAccount = first.AddAccount("One");
        var second = new ConnectivityFixture {CellularSource = source};second.EnableCellular();var secondAccount = second.AddAccount("Two");
        secondAccount.Id = firstAccount.Id;
        var caller = Environment.CurrentManagedThreadId;
        using var a = new DeviceAccess(new WindowsCollector(connectivityRuntime: first));
        using var b = new DeviceAccess(new WindowsCollector(connectivityRuntime: second));
        Check(native.Creates == 0, "context construction does not activate the native watcher");
        var ta = (await a.List(Entities.CellularSubscription)).Single();var tb = (await b.List(Entities.CellularSubscription)).Single();
        Check(native.Creates == 1 && native.Starts == 1 && native.ActiveHandlers == 5, "contexts share one started native watcher with all five event registrations");
        native.Fire(10, firstAccount.Id);native.Fire(6, firstAccount.Id);
        await Error(ErrorCode.EntityRemoved, () => a.Get(ta));await Error(ErrorCode.EntityRemoved, () => b.Get(tb));
        var fresh = (await b.List(Entities.CellularSubscription)).Single();
        a.Dispose();await first.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(native.Stops == 0 && native.ActiveHandlers == 5, "closing the creating context leaves the second context's source active");
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        await using (var stream = b.WithPollInterval(TimeSpan.FromHours(1)).Watch(fresh, deadline.Token).GetAsyncEnumerator()) {
            Check(await stream.MoveNextAsync(), "remaining context initial snapshot");secondAccount.Name = "Updated";
            native.Fire(8, secondAccount.Id);Check(await stream.MoveNextAsync() && stream.Current.CarrierName == "Updated", "native typed update event reaches the remaining context");
        }
        b.Dispose();await second.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(native.Stops == 1 && native.ActiveHandlers == 0 && native.References == 0 && native.Removes == 5
            && !native.Threads.Contains(caller), "last context stops/unregisters/releases on a collection worker");
    }

    private static async Task CellularWatcherFailures()
    {
        foreach (var addSlot in new[] {6, 8, 10, 12, 14, -1}) {
            using var native = new CellularWatcherFixture {AddFailureSlot = addSlot, StartResult = addSlot == -1 ? unchecked((int)0x80004005) : 0};
            var runtime = new ConnectivityFixture {CellularSource = new WindowsCellularWatcher(native)};runtime.EnableCellular();runtime.AddAccount("Denied");
            using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime));
            var expected = addSlot == -1 ? ErrorCode.ReadFailed : ErrorCode.PermissionDenied;
            await Error(expected, () => access.List(Entities.CellularSubscription));
            await Error(expected, () => access.List(Entities.CellularSubscription));
            Check(native.Creates == 1 && native.References == 0 && native.ActiveHandlers == 0 && runtime.AccountInventories == 0,
                "partial registration/start failure cleans up and context does not silently retry or enumerate");
            Check(native.Stops == 0 && native.Removes == (addSlot == -1 ? 5 : (addSlot - 6) / 2), "failed activation never reached an active state, so cleanup does not issue invalid Stop");
            access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        }
        foreach (var malformed in new[] {false, true}) {
            using var native = new CellularWatcherFixture();var runtime = new ConnectivityFixture {CellularSource = new WindowsCellularWatcher(native)};
            runtime.EnableCellular();var account = runtime.AddAccount("Before failure");
            using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime));
            var target = (await access.List(Entities.CellularSubscription)).Single();
            using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(3));
            await using (var stream = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(target, deadline.Token).GetAsyncEnumerator()) {
                Check(await stream.MoveNextAsync(), "initial value before event source failure");
                native.Fire(malformed ? 8 : 14, "");
                await Error(ErrorCode.ReadFailed, async () => {await stream.MoveNextAsync();});
            }
            await Error(ErrorCode.ReadFailed, () => access.Get(target));
            access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
            Check(native.Stops == (malformed ? 1 : 0) && native.Removes == 5 && native.References == 0 && native.ActiveHandlers == 0, "already stopped source is unregistered without an invalid second Stop");
        }
        using (var native = new CellularWatcherFixture {Unsupported = true}) {
            var runtime = new ConnectivityFixture {CellularSource = new WindowsCellularWatcher(native)};runtime.EnableCellular();runtime.AddAccount("Polled");
            using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime));var target = (await access.List(Entities.CellularSubscription)).Single();
            using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(3));
            await using (var stream = access.WithPollInterval(TimeSpan.FromMilliseconds(25)).Watch(target, deadline.Token).GetAsyncEnumerator())
                Check(await stream.MoveNextAsync() && await stream.MoveNextAsync() && stream.Current.CarrierName == "Polled", "unavailable native watcher retains supported polling");
            access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
            Check(native.Creates == 1 && native.Starts == 0 && native.References == 0, "unavailable watcher has no leaked source or repeated activation");
        }
    }

    private static async Task CellularInventoryObservationRaces()
    {
        var runtime = new ConnectivityFixture();runtime.EnableCellular();var account = runtime.AddAccount("Stable");
        using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime));
        var old = (await access.List(Entities.CellularSubscription)).Single();
        runtime.CellularChange(account.Id, WindowsCellularAccountChangeKind.Removed);
        Check((await access.List(Entities.CellularSubscription)).Length == 0, "stale inventory cannot rediscover an observed absent account");
        runtime.CellularChange(account.Id, WindowsCellularAccountChangeKind.Added);
        var fresh = (await access.List(Entities.CellularSubscription)).Single();Check(!old.Equals(fresh), "arrival permits fresh discovery");
        runtime.OnAccountInventory = () => {
            runtime.CellularChange(account.Id, WindowsCellularAccountChangeKind.Removed);
            runtime.CellularChange(account.Id, WindowsCellularAccountChangeKind.Added);
        };
        Check((await access.List(Entities.CellularSubscription)).Length == 0, "inventory crossing a removal does not publish a stale generation");
        runtime.OnAccountInventory = null;await Error(ErrorCode.EntityRemoved, () => access.Get(fresh));
        var latest = (await access.List(Entities.CellularSubscription)).Single();
        runtime.CellularChange(account.Id, WindowsCellularAccountChangeKind.Removed);runtime.AccountInventoryResult = unchecked((int)0x80070005);
        await Error(ErrorCode.PermissionDenied, () => access.List(Entities.CellularSubscription));
        runtime.AccountInventoryResult = 0;runtime.CellularChange(account.Id, WindowsCellularAccountChangeKind.Added);
        await Error(ErrorCode.EntityRemoved, () => access.Get(latest));
        var final = (await access.List(Entities.CellularSubscription)).Single();
        runtime.OnAccountName = () => runtime.CellularFailure?.Invoke(new DeviceReadoutException(ErrorCode.ReadFailed, "Source stopped during read."));
        await Error(ErrorCode.ReadFailed, () => access.Get(final));runtime.OnAccountName = null;
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.References.Values.All(count => count == 0), "racing and failed inventories/reads release their interfaces");
    }

    private static async Task CellularWatcherDeadlines()
    {
        foreach (var stage in new[] {0, 1, 2}) {
            using var native = new CellularWatcherFixture();var runtime = new ConnectivityFixture {CellularSource = new WindowsCellularWatcher(native)};
            runtime.EnableCellular();runtime.AddAccount("Held source");
            using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime));
            using var release = new ManualResetEventSlim(false);var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            Action hold = () => {started.TrySetResult();if (!release.Wait(TimeSpan.FromSeconds(3))) throw new Exception("Native watcher test gate timed out.");};
            try {
                if (stage == 0) native.OnAdd = hold;else if (stage == 1) native.OnStart = hold;else {
                    _ = await access.List(Entities.CellularSubscription);native.OnStop = hold;access.Dispose();
                }
                var pending = stage == 2 ? null : access.WithReadTimeout(TimeSpan.FromMilliseconds(250)).List(Entities.CellularSubscription);
                await started.Task.WaitAsync(TimeSpan.FromSeconds(2));await Task.Delay(10);
                if (pending is not null) await Error(ErrorCode.ReadTimeout, () => pending.WaitAsync(TimeSpan.FromSeconds(2)));
                access.Dispose();Check(!runtime.Stopped.Task.IsCompleted, "host runs and disposal does not join blocked native watcher work");
            } finally {release.Set();access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));}
            Check(native.ActiveHandlers == 0 && native.References == 0 && native.Stops == 1 && native.Removes == 5
                && runtime.AccountInventories == (stage == 2 ? 1 : 0), "late registration/start/stop cleanup completes without canceled inventory reads");
        }
    }

    private static async Task CellularLateSourceCallbacks()
    {
        foreach (var malformed in new[] {false, true}) {
            using var native = new CellularWatcherFixture();var source = new WindowsCellularWatcher(native);
            var first = new ConnectivityFixture {CellularSource = source};first.EnableCellular();var old = first.AddAccount("Old");
            var second = new ConnectivityFixture {CellularSource = source};second.EnableCellular();var fresh = second.AddAccount("Fresh");fresh.Id = old.Id;
            using var a = new DeviceAccess(new WindowsCollector(connectivityRuntime: first));
            using var b = new DeviceAccess(new WindowsCollector(connectivityRuntime: second));
            using var release = new ManualResetEventSlim(false);var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            Task? callback = null;
            try {
                _ = await a.List(Entities.CellularSubscription);
                native.OnEventRead = () => {entered.TrySetResult();if (!release.Wait(TimeSpan.FromSeconds(3))) throw new Exception("Late event gate timed out.");};
                callback = Task.Run(() => native.Fire(10, malformed ? "" : old.Id));
                await entered.Task.WaitAsync(TimeSpan.FromSeconds(2));
                a.Dispose();await first.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
                native.OnEventRead = null;var target = (await b.List(Entities.CellularSubscription)).Single();
                release.Set();await callback.WaitAsync(TimeSpan.FromSeconds(2));
                Check((await b.Get(target)).CarrierName == "Fresh", "late removed/error payload from an old native source cannot affect a new source generation");
            } finally {
                release.Set();if (callback is not null) await callback.WaitAsync(TimeSpan.FromSeconds(2));
                a.Dispose();b.Dispose();await first.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));await second.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
            }
            Check(native.Creates == 2 && native.Stops == 2 && native.Removes == 10 && native.ActiveHandlers == 0 && native.References == 0,
                "both source generations release all registrations and native references");
        }
    }

    private static async Task CellularWatcherPollingFallback()
    {
        foreach (var slot in new[] {6, 8, 10, 12, 14, -1}) {
            using var native = new CellularWatcherFixture {AddFailureSlot = slot, AddFailureResult = unchecked((int)0x80004001), StartResult = slot == -1 ? unchecked((int)0x80004001) : 0};
            var runtime = new ConnectivityFixture {CellularSource = new WindowsCellularWatcher(native)};runtime.EnableCellular();runtime.AddAccount("Supported read");
            using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime));
            var target = (await access.List(Entities.CellularSubscription)).Single();
            Check((await access.Get(target)).CarrierName == "Supported read", "unsupported event operation does not disable native account reads");
            using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(3));
            await using (var stream = access.WithPollInterval(TimeSpan.FromMilliseconds(25)).Watch(target, deadline.Token).GetAsyncEnumerator())
                Check(await stream.MoveNextAsync() && await stream.MoveNextAsync(), "initial and equal polled snapshots remain available");
            access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
            Check(native.Creates == 1 && native.References == 0 && native.ActiveHandlers == 0 && native.Stops == 0,
                "unsupported event activation cleans up without retrying or stopping an inactive watcher");
        }
    }

    private static async Task ActualCellularWatcher()
    {
        var native = new NativeCellularWatcherProbe();var source = new WindowsCellularWatcher(native);
        var first = new NativeConnectivityProbe(source);var second = new NativeConnectivityProbe(source);
        var caller = Environment.CurrentManagedThreadId;
        using var a = new DeviceAccess(new WindowsCollector(connectivityRuntime: first));
        using var b = new DeviceAccess(new WindowsCollector(connectivityRuntime: second));
        _ = await a.List(Entities.CellularSubscription);_ = await b.List(Entities.CellularSubscription);
        Check(native.Creates == 1 && native.Starts == 1 && native.Registrations == 5 && native.Active == 5 && native.StartedStatus is 1 or 2,
            "actual shared native watcher registers all event types and starts successfully");
        a.Dispose();await first.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(3));
        Check(native.Stops == 0 && native.Active == 5, "actual watcher outlives its creating context's apartment initialization");
        _ = await b.List(Entities.CellularSubscription);
        b.Dispose();await second.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(3));
        Check(native.Stops == 1 && native.Removals == 5 && native.Active == 0 && native.Releases == 1 && native.StoppedStatus == 3
            && !native.Threads.Contains(caller), "actual shared watcher stops and removes all handlers on the last collection worker");
        Console.WriteLine($"Native Windows cellular watcher: registrations={native.Registrations}, removals={native.Removals}, started status={native.StartedStatus}, stopped status={native.StoppedStatus}; two contexts share one native source.");
    }

    private sealed class NativeCellularWatcherProbe : IWindowsConnectivityRuntime
    {
        private readonly WindowsConnectivity.ConnectivityRuntime native = new();
        private readonly List<Delegate> delegates = [];
        private nint watcher, pointer, table;
        internal int Creates, Starts, Stops, Registrations, Removals, Active, Releases, StartedStatus, StoppedStatus;
        internal readonly List<int> Threads = [];
        private void Record() => Threads.Add(Environment.CurrentManagedThreadId);
        private static T Method<T>(nint instance, int slot) where T : Delegate
            => Marshal.GetDelegateForFunctionPointer<T>(Marshal.ReadIntPtr(Marshal.ReadIntPtr(instance), slot * nint.Size));
        private void Set(int slot, Delegate method) {delegates.Add(method);Marshal.WriteIntPtr(table, slot * nint.Size, Marshal.GetFunctionPointerForDelegate(method));}
        public nint CreateCellularWatcher()
        {
            Record();Creates++;watcher = native.CreateCellularWatcher();if (watcher == 0) return 0;
            pointer = Marshal.AllocHGlobal(nint.Size);table = Marshal.AllocHGlobal(19 * nint.Size);Marshal.WriteIntPtr(pointer, table);
            foreach (var slot in new[] {6, 8, 10, 12, 14}) {
                Set(slot, new WinRtAddReportEvent((nint self, nint handler, out long token) => {
                    Record();Registrations++;var result = Method<WinRtAddReportEvent>(watcher, slot)(watcher, handler, out token);if (result >= 0) Active++;return result;
                }));
                Set(slot + 1, new WinRtRemoveReportEvent((nint self, long token) => {
                    Record();Removals++;var result = Method<WinRtRemoveReportEvent>(watcher, slot + 1)(watcher, token);if (result >= 0) Active--;return result;
                }));
            }
            Set(17, new WinRtNoArguments(self => {
                Record();Starts++;var result = Method<WinRtNoArguments>(watcher, 17)(watcher);
                if (result >= 0) Check(Method<WinRtGetInt32>(watcher, 16)(watcher, out StartedStatus) >= 0, "native started status");return result;
            }));
            Set(16, new WinRtGetInt32((nint self, out int value) => {Record();return Method<WinRtGetInt32>(watcher, 16)(watcher, out value);}));
            Set(18, new WinRtNoArguments(self => {
                Record();Stops++;var result = Method<WinRtNoArguments>(watcher, 18)(watcher);
                if (result >= 0) Check(Method<WinRtGetInt32>(watcher, 16)(watcher, out StoppedStatus) >= 0, "native stopped status");return result;
            }));
            return pointer;
        }
        public int Initialize() => throw new Exception("Caller initializes its runtime.");
        public nint ActivateFactory() => throw new NotSupportedException();
        public void Uninitialize() => throw new Exception("Caller balances its runtime.");
        public void Release(nint value)
        {
            Record();Check(value == pointer, "native watcher reference");Releases++;
            try {native.Release(watcher);} finally {Marshal.FreeHGlobal(pointer);Marshal.FreeHGlobal(table);pointer = watcher = table = 0;}
        }
    }

    private sealed class CellularWatcherFixture : IWindowsConnectivityRuntime, IDisposable
    {
        private readonly nint pointer, table, args, argsTable;
        private readonly List<Delegate> delegates = [];
        private readonly object gate = new();
        private readonly Dictionary<int, Dictionary<long, nint>> handlers = [];
        private long sequence;
        private string accountId = "";
        private int status;
        internal int Creates, Starts, Stops, Removes, References;
        internal int AddFailureSlot = -1, AddFailureResult = unchecked((int)0x80070005), StartResult = 0;
        internal bool Unsupported = false;
        internal Action? OnAdd, OnStart, OnStop, OnEventRead;
        internal readonly List<int> Threads = [];
        internal int ActiveHandlers {get {lock (gate) return handlers.Values.Sum(values => values.Count);}}
        internal CellularWatcherFixture()
        {
            pointer = Marshal.AllocHGlobal(nint.Size);table = Marshal.AllocHGlobal(19 * nint.Size);Marshal.WriteIntPtr(pointer, table);
            args = Marshal.AllocHGlobal(nint.Size);argsTable = Marshal.AllocHGlobal(7 * nint.Size);Marshal.WriteIntPtr(args, argsTable);
            Set(argsTable, 6, new WinRtGetInterface((nint self, out nint value) => {var result = WindowsCreateString(accountId, accountId.Length, out value);OnEventRead?.Invoke();return result;}));
            foreach (var slot in new[] {6, 8, 10, 12, 14}) {
                handlers[slot] = [];
                Set(table, slot, new WinRtAddReportEvent((nint self, nint handler, out long token) => {
                    Threads.Add(Environment.CurrentManagedThreadId);
                    token = 0;OnAdd?.Invoke();if (slot == AddFailureSlot) return AddFailureResult;
                    var iid = new Guid(slot is 6 or 10 ? "423cc41e-fe8c-5a7d-9fee-aae04ef85700" : slot == 8 ? "0e865096-1ffa-5792-8d4f-8623e3c77f56" : "e4dc9cfc-f462-5afd-856d-04ace229d00e");
                    var hr = Marshal.QueryInterface(handler, in iid, out var typed);if (typed != 0) Marshal.Release(typed);
                    token = 0;if (hr < 0) return hr;
                    lock (gate) {token = ++sequence;Marshal.AddRef(handler);handlers[slot].Add(token, handler);}return 0;
                }));
                Set(table, slot + 1, new WinRtRemoveReportEvent((nint self, long token) => {
                    Threads.Add(Environment.CurrentManagedThreadId);Removes++;nint handler;
                    lock (gate) {handler = handlers[slot][token];handlers[slot].Remove(token);}Marshal.Release(handler);return 0;
                }));
            }
            Set(table, 16, new WinRtGetInt32((nint self, out int value) => {Threads.Add(Environment.CurrentManagedThreadId);value = status;return 0;}));
            Set(table, 17, new WinRtNoArguments(self => {Threads.Add(Environment.CurrentManagedThreadId);Starts++;OnStart?.Invoke();status = StartResult < 0 ? 0 : 1;return StartResult;}));
            Set(table, 18, new WinRtNoArguments(self => {Threads.Add(Environment.CurrentManagedThreadId);Stops++;OnStop?.Invoke();if (status is not (1 or 2)) return unchecked((int)0x8007139f);status = 3;return 0;}));
        }
        internal void Fire(int slot, string id)
        {
            if (slot == 14) status = 3;
            nint[] current;lock (gate) {accountId = id;current = handlers[slot].Values.ToArray();foreach(var handler in current) Marshal.AddRef(handler);}
            foreach (var handler in current) try {
                var invoke = Marshal.GetDelegateForFunctionPointer<WinRtCellularEventInvoke>(Marshal.ReadIntPtr(Marshal.ReadIntPtr(handler), 3 * nint.Size));
                Check(invoke(handler, pointer, slot is 12 or 14 ? 0 : args) == 0, "native delegate contains managed errors");
            } finally {Marshal.Release(handler);}
        }
        private void Set(nint target, int slot, Delegate method) {delegates.Add(method);Marshal.WriteIntPtr(target, slot * nint.Size, Marshal.GetFunctionPointerForDelegate(method));}
        public int Initialize() => throw new Exception("Watcher shares the caller's initialized MTA.");
        public nint ActivateFactory() => throw new NotSupportedException();
        public nint CreateCellularWatcher() {Threads.Add(Environment.CurrentManagedThreadId);Creates++;if (Unsupported) return 0;References++;return pointer;}
        public void Release(nint value) {Check(value == pointer, "watcher release");Threads.Add(Environment.CurrentManagedThreadId);References--;}
        public void Uninitialize() => throw new Exception("Watcher does not uninitialize its caller's runtime.");
        public void Dispose() {Marshal.FreeHGlobal(pointer);Marshal.FreeHGlobal(table);Marshal.FreeHGlobal(args);Marshal.FreeHGlobal(argsTable);}
        [DllImport("combase.dll", CharSet = CharSet.Unicode)] private static extern int WindowsCreateString(string text, int length, out nint value);
    }

    private sealed partial class ConnectivityFixture
    {
        internal Action<WindowsCellularAccountChange>? CellularListener;
        internal Action<Exception>? CellularFailure;
        internal int CellularObservations, CellularObservationDisposals;
        internal WindowsCellularWatcher? CellularSource;
        public IDisposable? ObserveCellularAccounts(Action<WindowsCellularAccountChange> changed, Action<Exception> fail)
        {
            if (CellularSource is not null) return CellularSource.Subscribe(changed, fail);
            Record();CellularObservations++;CellularListener = changed;CellularFailure = fail;
            return new CellularSubscriptionCleanup(() => {Record();CellularObservationDisposals++;CellularListener = null;CellularFailure = null;});
        }
        internal void CellularChange(string id, WindowsCellularAccountChangeKind kind) => CellularListener?.Invoke(new(id, kind));
        private sealed class CellularSubscriptionCleanup(Action dispose) : IDisposable
        {public void Dispose() => dispose();}
    }
}
