using DeviceReadout;
using DeviceReadout.Windows;

internal static partial class WindowsConnectivityTests
{
    private static async Task PerformanceFields()
    {
        var runtime = new ConnectivityFixture();var caller = Environment.CurrentManagedThreadId;
        using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime));
        Check(runtime.Initializations == 0 && runtime.PlanReads == 0, "construction performs no network query");
        var value = await access.Get(Entities.NetworkPerformance);
        Check(value.DownlinkBps == 1234567890123d && value.UplinkBps == 32000000d, "64-bit inbound/outbound values stay in bits per second");
        Check(value.RoundTripTime is null && value.EffectiveType is null && value.BrowserOnline is null, "no RTT, radio-derived performance class or browser state is invented");
        runtime.InboundRate = runtime.OutboundRate = 0;
        value = await access.Get(Entities.NetworkPerformance);
        Check(value.DownlinkBps == 0 && value.UplinkBps == 0, "reported zero remains zero");
        runtime.InboundRate = null;runtime.OutboundRate = 1;
        value = await access.Get(Entities.NetworkPerformance);
        Check(value.DownlinkBps is null && value.UplinkBps == 1, "nullable downlink retains readable uplink");
        runtime.OutboundRate = null;
        value = await access.Get(Entities.NetworkPerformance);
        Check(value.DownlinkBps is null && value.UplinkBps is null, "known absent rates remain null");
        runtime.NoPlan = true;
        Check((await access.Get(Entities.NetworkPerformance)).DownlinkBps is null, "missing plan has no inferred transfer rate");
        runtime.NoPlan = false;runtime.NoProfile = true;
        value = await access.Get(Entities.NetworkPerformance);
        Check(value.DownlinkBps is null && value.UplinkBps is null, "missing preferred profile is not a measured zero rate");
        Check((await access.Capabilities.Get(Entities.NetworkPerformance)).Readable == true, "performance API availability does not depend on present rate values");
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.References.Values.All(count => count == 0) && runtime.Initializations == 1 && runtime.Uninitializations == 1, "all native report/reference lifetimes balance");
        Check(runtime.Threads.Distinct().Count() == 1 && !runtime.Threads.Contains(caller), "native plan queries, conversion and cleanup stay on the worker");
    }
    private static async Task PerformanceEvents()
    {
        var runtime = new ConnectivityFixture();
        using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime));
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        var reads = runtime.PlanReads;
        await using (var polled = access.WithPollInterval(TimeSpan.FromMilliseconds(25)).Watch(Entities.NetworkPerformance, deadline.Token).GetAsyncEnumerator()) {
            Check(await polled.MoveNextAsync() && polled.Current.DownlinkBps == 1234567890123d, "initial performance value");
            Check(await polled.MoveNextAsync() && polled.Current.DownlinkBps == 1234567890123d, "equal performance poll is retained");
        }
        Check(runtime.PlanReads >= reads + 2, "polling obtains fresh plans");
        var slow = access.WithPollInterval(TimeSpan.FromHours(1));
        await using var path = slow.Watch(Entities.NetworkPath, deadline.Token).GetAsyncEnumerator();
        await using var performance = slow.Watch(Entities.NetworkPerformance, deadline.Token).GetAsyncEnumerator();
        Check(await path.MoveNextAsync() && await performance.MoveNextAsync(), "mixed entity initial values");
        Check(runtime.HandlerCount == 2, "both entity watches register native change sources");
        runtime.InboundRate = 0;runtime.OutboundRate = 75000000;runtime.Level = 1;runtime.Fire();
        Check(await performance.MoveNextAsync() && performance.Current.DownlinkBps == 0 && performance.Current.UplinkBps == 75000000, "performance event reads the native rates before its next poll");
        Check(await path.MoveNextAsync() && path.Current.InternetValidated == false, "path event remains a path snapshot");
        runtime.Fire();
        Check(await performance.MoveNextAsync() && performance.Current.UplinkBps == 75000000 && await path.MoveNextAsync(), "equal native updates reach both streams");
        runtime.NoPlan = true;runtime.Fire();
        Check(await performance.MoveNextAsync() && performance.Current.DownlinkBps is null && performance.Current.UplinkBps is null, "plan disappearance does not reuse old rates");
        Check(await path.MoveNextAsync(), "drain matching path notification");
        await performance.DisposeAsync();
        runtime.Level = 3;runtime.Fire();
        Check(await path.MoveNextAsync() && path.Current.InternetValidated == true, "remaining path stream keeps updating");
        await path.DisposeAsync();access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.Initializations == 1 && runtime.Uninitializations == 1 && runtime.Registrations == runtime.Removals
            && runtime.References.Values.All(count => count == 0), "mixed entity views share and balance the owning runtime");
    }
    private static async Task PerformanceFailures()
    {
        var runtime = new ConnectivityFixture();
        using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime));
        runtime.InboundResult = unchecked((int)0x80070005);
        var value = await access.Get(Entities.NetworkPerformance);
        Check(value.DownlinkBps is null && value.UplinkBps == 32000000, "failed inbound reference does not discard readable outbound rate");
        runtime.InboundResult = 0;runtime.OutboundResult = unchecked((int)0x80004005);
        value = await access.Get(Entities.NetworkPerformance);
        Check(value.DownlinkBps == 1234567890123d && value.UplinkBps is null, "failed outbound reference does not discard readable inbound rate");
        runtime.OutboundResult = 0;runtime.InboundValueResult = unchecked((int)0x80004005);
        value = await access.Get(Entities.NetworkPerformance);
        Check(value.DownlinkBps is null && value.UplinkBps == 32000000, "failed boxed inbound value remains field-local");
        runtime.InboundValueResult = 0;runtime.OutboundValueResult = unchecked((int)0x80070005);
        value = await access.Get(Entities.NetworkPerformance);
        Check(value.DownlinkBps == 1234567890123d && value.UplinkBps is null, "failed boxed outbound value remains field-local");
        runtime.InboundValueResult = unchecked((int)0x80004005);
        await Error(ErrorCode.PermissionDenied, () => access.Get(Entities.NetworkPerformance));
        runtime.OutboundValueResult = unchecked((int)0x80004005);
        await Error(ErrorCode.ReadFailed, () => access.Get(Entities.NetworkPerformance));
        runtime.InboundValueResult = runtime.OutboundValueResult = 0;
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        await using (var stream = access.WithPollInterval(TimeSpan.FromHours(1)).Watch(Entities.NetworkPerformance, deadline.Token).GetAsyncEnumerator()) {
            Check(await stream.MoveNextAsync(), "initial performance before plan failure");
            runtime.PlanResult = unchecked((int)0x80070005);runtime.Fire();
            await Error(ErrorCode.PermissionDenied, async () => {await stream.MoveNextAsync();});
        }
        await TestCompletion.Until(() => runtime.HandlerCount == 0, "failed performance registration removed");
        Check(runtime.HandlerCount == 0 && runtime.Registrations == runtime.Removals, "whole-plan failure closes the stream registration");
        runtime.PlanResult = 0;
        Check((await access.Get(Entities.NetworkPerformance)).UplinkBps == 32000000, "fresh explicit get after recovery");
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.References.Values.All(count => count == 0), "failure paths release all nonnull out-interfaces and boxed values");
    }
    private static async Task ActualPerformance()
    {
        var runtime = new NativeConnectivityProbe();var caller = Environment.CurrentManagedThreadId;
        using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime));
        var value = await access.Get(Entities.NetworkPerformance);
        Check(value.DownlinkBps is null || double.IsFinite(value.DownlinkBps.Value) && value.DownlinkBps.Value >= 0, "native downlink is absent or a finite unsigned rate");
        Check(value.UplinkBps is null || double.IsFinite(value.UplinkBps.Value) && value.UplinkBps.Value >= 0, "native uplink is absent or a finite unsigned rate");
        Check(value.RoundTripTime is null && value.EffectiveType is null && value.BrowserOnline is null, "native query does not fabricate RTT/class/browser state");
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        await using (var stream = access.WithPollInterval(TimeSpan.FromMilliseconds(25)).Watch(Entities.NetworkPerformance, deadline.Token).GetAsyncEnumerator()) {
            Check(await stream.MoveNextAsync() && runtime.Active == 1 && runtime.Registrations == 1, "actual performance watch registers native status observation");
            Check(await stream.MoveNextAsync(), "actual performance poll completes even when rates are unavailable");
        }
        await TestCompletion.Until(() => Volatile.Read(ref runtime.Active) == 0, "actual performance registration removed");
        Check(runtime.Active == 0 && runtime.Removals == 1 && runtime.RemovalResult == 0, "actual native registration removed successfully");
        _ = await access.Get(Entities.NetworkPath);
        access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(runtime.Initializations == 1 && runtime.Uninitializations == 1 && runtime.FactoryReleases == 1, "mixed native entities share and balance their runtime");
        Check(runtime.Threads.Distinct().Count() == 1 && !runtime.Threads.Contains(caller), "native performance reads and cleanup stay on the worker");
        Console.WriteLine($"Native Windows plan rates: downlink={value.DownlinkBps?.ToString("R", System.Globalization.CultureInfo.InvariantCulture) ?? "null"}, uplink={value.UplinkBps?.ToString("R", System.Globalization.CultureInfo.InvariantCulture) ?? "null"}; actual get/poll/status registration/removal and cleanup verified.");
    }
    private static async Task PerformanceDeadlines()
    {
        foreach (var eventRead in new[] {false, true}) {
            var runtime = new ConnectivityFixture();var caller = Environment.CurrentManagedThreadId;
            using var access = new DeviceAccess(new WindowsCollector(connectivityRuntime: runtime));
            var configured = access.WithReadTimeout(TimeSpan.FromMilliseconds(250)).WithPollInterval(TimeSpan.FromHours(1));
            IAsyncEnumerator<NetworkPerformanceSnapshot>? stream = null;
            var previousInbound = 0;var previousOutbound = 0;
            try {
                if (eventRead) {
                    stream = configured.Watch(Entities.NetworkPerformance).GetAsyncEnumerator();
                    Check(await stream.MoveNextAsync(), "initial performance before a blocked event read");
                }
                previousInbound = runtime.InboundReads;previousOutbound = runtime.OutboundReads;runtime.PausePlan();
                if (eventRead) runtime.Fire();
                Task pending = eventRead ? stream!.MoveNextAsync().AsTask() : configured.Get(Entities.NetworkPerformance);
                await runtime.PlanStarted.Task.WaitAsync(TimeSpan.FromSeconds(2));
                await Task.Delay(10);Check(!pending.IsCompleted, "host continuation proceeds while native plan collection is blocked");
                await Error(ErrorCode.ReadTimeout, () => pending.WaitAsync(TimeSpan.FromSeconds(2)));
                access.Dispose();Check(!runtime.Stopped.Task.IsCompleted, "context closure does not join a borrowed plan call");
            } finally {
                runtime.ContinuePlan.Set();access.Dispose();await runtime.Stopped.Task.WaitAsync(TimeSpan.FromSeconds(2));
                if (stream is not null) await stream.DisposeAsync();
                runtime.ContinuePlan.Dispose();
            }
            Check(runtime.InboundReads == previousInbound && runtime.OutboundReads == previousOutbound, "late canceled plans cause no further rate property reads");
            Check(runtime.Registrations == runtime.Removals && runtime.HandlerCount == 0 && runtime.References.Values.All(count => count == 0), "late plan, profile, subscription and factory are released");
            Check(runtime.Uninitializations == 1 && runtime.Threads.Distinct().Count() == 1 && !runtime.Threads.Contains(caller), "late cleanup remains worker-owned");
        }
    }
}
