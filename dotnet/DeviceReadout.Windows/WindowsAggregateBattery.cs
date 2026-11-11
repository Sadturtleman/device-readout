namespace DeviceReadout.Windows;

internal sealed record WindowsAggregateReport(int? Status, int? ChargeRate, int? DesignCapacity, int? FullChargeCapacity, int? RemainingCapacity);

internal interface IWindowsAggregateBatteryPlatform : IDisposable
{
    WindowsAggregateReport? Read();
    IDisposable? Observe(Action changed, Action<Exception> fail) => null;
    void IDisposable.Dispose() { }
}
