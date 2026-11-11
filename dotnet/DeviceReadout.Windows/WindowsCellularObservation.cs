namespace DeviceReadout.Windows;

internal enum WindowsCellularAccountChangeKind { Added, Removed, Updated }
internal sealed record WindowsCellularAccountChange(string AccountId, WindowsCellularAccountChangeKind Kind);

internal sealed partial class WindowsConnectivity
{
    private sealed record CellularTarget(string Id, long Version);
    private sealed record CellularListener(CellularTarget Target, Action Changed, Action<Exception> Fail);
    private readonly object cellularGate = new();
    private readonly Dictionary<string, long> cellularRemovals = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> cellularAbsent = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, CellularTarget> cellularTargets = [];
    private readonly List<CellularListener> cellularListeners = [];
    private IDisposable? cellularObservation;
    private Exception? cellularObservationFailure;
    private bool cellularObserving, cellularDisposed;

    private void AssertCellularHealthy()
    {
        if (cellularDisposed) throw new DeviceReadoutException(ErrorCode.EntityRemoved, "Cellular observation is closed.");
        if (cellularObservationFailure is { } error) throw error;
    }
    private void EnsureCellularObservation()
    {
        lock (cellularGate) AssertCellularHealthy();
        if (cellularObserving) return;
        cellularObserving = true;
        try {cellularObservation = runtime.ObserveCellularAccounts(CellularAccountChanged, CellularObservationFailed);}
        catch (Exception error) {CellularObservationFailed(error);throw;}
        lock (cellularGate) AssertCellularHealthy();
    }
    private void CellularAccountChanged(WindowsCellularAccountChange change)
    {
        CellularListener[] affected;
        lock (cellularGate) {
            if (cellularDisposed || cellularObservationFailure is not null) return;
            if (change.Kind == WindowsCellularAccountChangeKind.Removed) {
                cellularAbsent.Add(change.AccountId);
                cellularRemovals[change.AccountId] = checked(cellularRemovals.GetValueOrDefault(change.AccountId) + 1);
            } else if (change.Kind == WindowsCellularAccountChangeKind.Added) cellularAbsent.Remove(change.AccountId);
            affected = cellularListeners.Where(listener => StringComparer.OrdinalIgnoreCase.Equals(listener.Target.Id, change.AccountId)).ToArray();
        }
        foreach (var listener in affected) try {
            if (change.Kind == WindowsCellularAccountChangeKind.Removed)
                listener.Fail(new DeviceReadoutException(ErrorCode.EntityRemoved, "The selected cellular account was removed."));
            else listener.Changed();
        } catch (Exception error) {try {listener.Fail(error);} catch (Exception) { /* Contain native callbacks. */ }}
    }
    private void CellularObservationFailed(Exception error)
    {
        CellularListener[] affected;
        lock (cellularGate) {
            if (cellularDisposed) return;
            cellularObservationFailure ??= error;affected = cellularListeners.ToArray();
        }
        foreach (var listener in affected) try {listener.Fail(error);} catch (Exception) { /* Contain native callbacks. */ }
    }
    // Catalog mutation occurs only on the collection worker, under the callback-state lock.
    private void RetireCellularRemovals()
    {
        foreach (var pair in cellularTargets.ToArray()) if (cellularRemovals.GetValueOrDefault(pair.Value.Id) != pair.Value.Version) {
            cellular.Retire(pair.Key);cellularTargets.Remove(pair.Key);
        }
    }
    private string ResolveCellular(string? target)
    {
        lock (cellularGate) {AssertCellularHealthy();RetireCellularRemovals();return cellular.Resolve(target);}
    }
    private Dictionary<string, long> BeginCellularInventory()
    {
        lock (cellularGate) {AssertCellularHealthy();RetireCellularRemovals();return new(cellularRemovals, StringComparer.OrdinalIgnoreCase);}
    }
    private IReadOnlyList<string> UpdateCellularInventory(IEnumerable<string> ids, Dictionary<string, long> before)
    {
        lock (cellularGate) {
            AssertCellularHealthy();RetireCellularRemovals();
            var stable = ids.Where(id => !cellularAbsent.Contains(id) && cellularRemovals.GetValueOrDefault(id) == before.GetValueOrDefault(id));
            var result = cellular.Update(stable);
            foreach (var target in cellularTargets.Keys.ToArray()) if (!result.Contains(target)) cellularTargets.Remove(target);
            foreach (var target in result) {
                var id = cellular.Resolve(target);cellularTargets.TryAdd(target, new(id, cellularRemovals.GetValueOrDefault(id)));
            }
            return result;
        }
    }
    internal ICollectorSubscription ObserveCellular(string? target, Action<Func<CancellationToken, DeviceSnapshot>> changed, Action<Exception> fail, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();EnsureCellularFactory();EnsureCellularObservation();
        CellularListener listener;
        lock (cellularGate) {
            _ = ResolveCellular(target);listener = new(cellularTargets[target!], () => changed(cancellation => ReadCellular(target, cancellation)), fail);
            cellularListeners.Add(listener);
        }
        ICollectorSubscription? status = null;
        try {
            status = Observe(cancellation => ReadCellular(target, cancellation), changed, fail, token);
            return new Subscription(() => {lock (cellularGate) cellularListeners.Remove(listener);status?.Dispose();});
        } catch {lock (cellularGate) cellularListeners.Remove(listener);status?.Dispose();throw;}
    }
    private void DisposeCellularObservation()
    {
        lock (cellularGate) {cellularDisposed = true;cellularListeners.Clear();}
        try {cellularObservation?.Dispose();} finally {cellularObservation = null;}
    }
}
