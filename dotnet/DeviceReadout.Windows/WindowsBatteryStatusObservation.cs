using System.Buffers.Binary;
using System.ComponentModel;

namespace DeviceReadout.Windows;

// An outstanding driver wait must not occupy the shared collection lane.
internal sealed class WindowsBatteryStatusObservation : IDisposable
{
    private readonly CancellationTokenSource lifetime;
    private readonly object gate = new();
    private bool finished;
    internal WindowsBatteryStatusObservation(Func<IWindowsBatteryDevice?> open, uint tag, Action<byte[]> changed,
        Action<Exception> fail, CancellationToken token)
    {
        lifetime = CancellationTokenSource.CreateLinkedTokenSource(token);
        var thread = new Thread(() => {
            try {
                lifetime.Token.ThrowIfCancellationRequested();
                using var device = open();
                if (device is null) return;
                var request = new byte[20];BinaryPrimitives.WriteUInt32LittleEndian(request, tag);
                while (!lifetime.IsCancellationRequested) {
                    var status = device.Query(BatteryIoControl.QueryStatus, request, 16, lifetime.Token);
                    lifetime.Token.ThrowIfCancellationRequested();
                    if (status.Length != 16) throw new DeviceReadoutException(ErrorCode.ReadFailed, "Invalid battery status response length.");
                    changed(status.ToArray());
                    var capacity = BinaryPrimitives.ReadUInt32LittleEndian(status.AsSpan(4));
                    BinaryPrimitives.WriteUInt32LittleEndian(request.AsSpan(4), uint.MaxValue);
                    status.AsSpan(0, 4).CopyTo(request.AsSpan(8));
                    BinaryPrimitives.WriteUInt32LittleEndian(request.AsSpan(12), capacity == uint.MaxValue ? 0 : capacity);
                    BinaryPrimitives.WriteUInt32LittleEndian(request.AsSpan(16), capacity);
                }
            } catch (OperationCanceledException) when (lifetime.IsCancellationRequested) { }
            catch (Win32Exception error) when (error.NativeErrorCode is 1 or 50) { /* Unsupported driver notification: retain polling. */ }
            catch (Exception error) {
                if (!lifetime.IsCancellationRequested) try {fail(error);} catch (Exception) { /* Never unwind on a background lane. */ }
            } finally {lock (gate) {finished = true;lifetime.Dispose();}}
        }) {IsBackground = true, Name = "DeviceReadout battery status"};
        try {thread.Start();} catch {lifetime.Dispose();throw;}
    }
    public void Dispose()
    {
        lock (gate) {if (!finished) lifetime.Cancel();}
    }
}
