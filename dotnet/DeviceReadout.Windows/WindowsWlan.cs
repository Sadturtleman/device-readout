using System.Runtime.InteropServices;

namespace DeviceReadout.Windows;

internal enum WindowsWlanQuery : uint { Rssi = 0x10000102 }

internal interface IWindowsWlanApi
{
    uint Open(out uint negotiatedVersion, out nint client);
    uint Query(nint client, in Guid adapter, WindowsWlanQuery kind, out uint size, out nint data);
    void Free(nint data);
    uint Close(nint client);
}

internal sealed partial class WindowsConnectivity
{
    private int ReadWlanRssi(Guid adapter, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();var api = WlanApi;
        nint client = 0, data = 0;uint closeResult = 0;int value;
        try {
            CheckWlan(api.Open(out var version, out client), "WlanOpenHandle");
            token.ThrowIfCancellationRequested();
            if (client == 0) throw WifiInvalid("WLAN returned no client handle.");
            if (version < 2) throw new DeviceReadoutException(ErrorCode.UnsupportedEntity, "WLAN RSSI requires native client version 2.");
            var result = api.Query(client, in adapter, WindowsWlanQuery.Rssi, out var size, out data);
            token.ThrowIfCancellationRequested();CheckWlan(result, "WlanQueryInterface.Rssi", connection: true);
            if (data == 0 || size != sizeof(int)) throw WifiInvalid("Invalid WLAN RSSI result.");
            value = Marshal.ReadInt32(data);token.ThrowIfCancellationRequested();
        } catch (DllNotFoundException error) {throw new DeviceReadoutException(ErrorCode.UnsupportedEntity, "Native WLAN API is unavailable.", error);}
        catch (EntryPointNotFoundException error) {throw new DeviceReadoutException(ErrorCode.UnsupportedEntity, "Native WLAN entry point is unavailable.", error);}
        finally {
            try {if (data != 0) api.Free(data);}
            finally {if (client != 0) closeResult = api.Close(client);}
        }
        // A close failure must not mask a primary read/removal/cancellation exception.
        CheckWlan(closeResult, "WlanCloseHandle");token.ThrowIfCancellationRequested();return value;
    }
    private static void CheckWlan(uint result, string operation, bool connection = false)
    {
        if (result == 0) return;
        var code = result switch {
            5 => ErrorCode.PermissionDenied,
            50 or 120 or 1062 => ErrorCode.UnsupportedEntity,
            1168 or 5023 when connection => ErrorCode.EntityRemoved,
            _ => ErrorCode.ReadFailed
        };
        throw new DeviceReadoutException(code, $"{operation} failed (Win32 {result}).");
    }
}

internal sealed class WindowsWlanApi : IWindowsWlanApi
{
    public uint Open(out uint negotiatedVersion, out nint client) => WlanOpenHandle(2, 0, out negotiatedVersion, out client);
    public uint Query(nint client, in Guid adapter, WindowsWlanQuery kind, out uint size, out nint data)
        => WlanQueryInterface(client, in adapter, kind, 0, out size, out data, 0);
    public void Free(nint data) => WlanFreeMemory(data);
    public uint Close(nint client) => WlanCloseHandle(client, 0);
    [DllImport("wlanapi.dll")] private static extern uint WlanOpenHandle(uint version, nint reserved, out uint negotiatedVersion, out nint client);
    [DllImport("wlanapi.dll")] private static extern uint WlanQueryInterface(nint client, in Guid adapter, WindowsWlanQuery kind, nint reserved, out uint size, out nint data, nint valueType);
    [DllImport("wlanapi.dll")] private static extern void WlanFreeMemory(nint data);
    [DllImport("wlanapi.dll")] private static extern uint WlanCloseHandle(nint client, nint reserved);
}
