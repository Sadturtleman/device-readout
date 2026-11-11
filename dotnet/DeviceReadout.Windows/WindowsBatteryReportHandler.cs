using System.Collections.Concurrent;
using System.Runtime.InteropServices;

namespace DeviceReadout.Windows;

// Native TypedEventHandler<Battery, IInspectable>. It has IUnknown plus Invoke, not IInspectable slots.
internal sealed class WindowsBatteryReportHandler
{
    private static readonly Guid HandlerId = new("4d4aa646-767f-5645-af5c-546464d3ec09");
    private static readonly Guid UnknownId = new("00000000-0000-0000-c000-000000000046");
    private static readonly Guid AgileId = new("94ea2b94-e9cc-49e0-c0ff-ee64ca8f5b90");
    private static readonly ConcurrentDictionary<nint, WindowsBatteryReportHandler> Active = new();
    private static readonly QueryDelegate QueryCallback = Query;
    private static readonly ReferenceDelegate AddCallback = AddReference, ReleaseCallback = Release;
    private static readonly InvokeDelegate InvokeCallback = Invoke;
    private static readonly nint Vtable = CreateVtable();
    private Action? changed;
    private Action<Exception>? fail;
    private int references = 1;
    internal nint Pointer { get; }

    internal WindowsBatteryReportHandler(Action changed, Action<Exception> fail)
    {
        this.changed = changed;this.fail = fail;
        Pointer = Marshal.AllocHGlobal(nint.Size);Marshal.WriteIntPtr(Pointer, Vtable);Active.TryAdd(Pointer, this);
    }
    internal void Stop() {Interlocked.Exchange(ref changed, null);Interlocked.Exchange(ref fail, null);}
    internal void ReleaseOwner() {Stop();Release(Pointer);}
    private static nint CreateVtable()
    {
        var table = Marshal.AllocHGlobal(4 * nint.Size);
        var methods = new Delegate[] {QueryCallback, AddCallback, ReleaseCallback, InvokeCallback};
        for (var slot = 0; slot < methods.Length; slot++) Marshal.WriteIntPtr(table, slot * nint.Size, Marshal.GetFunctionPointerForDelegate(methods[slot]));
        return table;
    }
    private static int Query(nint self, in Guid iid, out nint value)
    {
        value = 0;
        if (!Active.ContainsKey(self) || (iid != HandlerId && iid != UnknownId && iid != AgileId)) return unchecked((int)0x80004002);
        AddReference(self);value = self;return 0;
    }
    private static uint AddReference(nint self)
        => Active.TryGetValue(self, out var handler) ? (uint)Interlocked.Increment(ref handler.references) : 0;
    private static uint Release(nint self)
    {
        if (!Active.TryGetValue(self, out var handler)) return 0;
        var count = Interlocked.Decrement(ref handler.references);
        if (count == 0) {handler.Stop();Active.TryRemove(self, out _);Marshal.FreeHGlobal(self);}
        return (uint)count;
    }
    private static int Invoke(nint self, nint sender, nint args)
    {
        if (!Active.TryGetValue(self, out var handler)) return 0;
        try {Volatile.Read(ref handler.changed)?.Invoke();}
        catch (Exception error) {try {Volatile.Read(ref handler.fail)?.Invoke(error);} catch (Exception) { /* Do not unwind into WinRT. */ }}
        return 0;
    }
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int QueryDelegate(nint self, in Guid iid, out nint value);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] internal delegate uint ReferenceDelegate(nint self);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] internal delegate int InvokeDelegate(nint self, nint sender, nint args);
}
