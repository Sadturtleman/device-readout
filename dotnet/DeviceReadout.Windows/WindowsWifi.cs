using System.Runtime.InteropServices;

namespace DeviceReadout.Windows;

[UnmanagedFunctionPointer(CallingConvention.StdCall)]
internal delegate int WinRtGetAt(nint self, uint index, out nint value);
[UnmanagedFunctionPointer(CallingConvention.StdCall)]
internal delegate int WinRtGetBoolean(nint self, out byte value);
[UnmanagedFunctionPointer(CallingConvention.StdCall)]
internal delegate int WinRtGetGuid(nint self, out Guid value);

internal sealed partial class WindowsConnectivity
{
    private readonly ResourceCatalog wifi = new();
    private static readonly Guid Profile2Iid = new("e2045145-4c9f-400c-9150-7ec7d6e2888a");

    internal EntityCapabilities WifiCapabilities(string? target)
    {
        if (target is not null) _ = wifi.Resolve(target);
        return Capabilities;
    }
    internal IReadOnlyList<string> ListWifi(CancellationToken token)
        => RefreshWifi(token, null, out _);
    internal string? CurrentWifi(CancellationToken token)
    {
        ListWifi(token);token.ThrowIfCancellationRequested();
        nint profile = 0;
        try {
            Check(Method<WinRtGetInterface>(factory, 7)(factory, out profile), "GetInternetConnectionProfile");
            token.ThrowIfCancellationRequested();
            var key = profile == 0 ? null : WifiKey(profile, token);
            return key is null ? null : wifi.Find(key);
        } finally {if (profile != 0) runtime.Release(profile);}
    }
    internal WifiConnectionSnapshot ReadWifi(string? target, CancellationToken token)
    {
        var key = wifi.Resolve(target);
        try {
            RefreshWifi(token, key, out var snapshot);
            // Re-query the inventory: WinRT profile instances are not live objects.
            ListWifi(token);_ = wifi.Resolve(target);token.ThrowIfCancellationRequested();
            return snapshot ?? throw new DeviceReadoutException(ErrorCode.EntityRemoved, "The selected Wi-Fi connection was removed.");
        } catch (DeviceReadoutException error) when (error.Code == ErrorCode.EntityRemoved) {wifi.Retire(target!);throw;}
    }
    private IReadOnlyList<string> RefreshWifi(CancellationToken token, string? readKey, out WifiConnectionSnapshot? snapshot)
    {
        snapshot = null;token.ThrowIfCancellationRequested();EnsureFactory();token.ThrowIfCancellationRequested();
        nint vector = 0;
        try {
            Check(Method<WinRtGetInterface>(factory, 6)(factory, out vector), "GetConnectionProfiles");
            token.ThrowIfCancellationRequested();
            if (vector == 0) throw WifiInvalid("Missing connection profile inventory.");
            Check(Method<WinRtGetUInt32>(vector, 7)(vector, out var size), "ConnectionProfiles.Size");
            if (size > 4096) throw WifiInvalid("Connection profile inventory exceeds the collection bound.");
            var keys = new HashSet<string>(StringComparer.Ordinal);
            for (uint index = 0; index < size; index++) {
                token.ThrowIfCancellationRequested();nint profile = 0;
                try {
                    Check(Method<WinRtGetAt>(vector, 6)(vector, index, out profile), "ConnectionProfiles.GetAt");
                    token.ThrowIfCancellationRequested();
                    if (profile == 0) throw WifiInvalid("Missing connection profile.");
                    var key = WifiKey(profile, token);
                    if (key is null) continue;
                    if (!keys.Add(key)) throw WifiInvalid("Ambiguous active Wi-Fi profiles.");
                    if (key == readKey) snapshot = WifiFields(profile, Guid.ParseExact(key.AsSpan(0, 32), "N"), token);
                } finally {if (profile != 0) runtime.Release(profile);}
            }
            token.ThrowIfCancellationRequested();
            // A failed or interrupted enumeration must not tombstone existing targets.
            return wifi.Update(keys);
        } finally {if (vector != 0) runtime.Release(vector);}
    }
    private string? WifiKey(nint profile, CancellationToken token)
    {
        nint extended = 0, adapter = 0, network = 0;
        try {
            Check(Marshal.QueryInterface(profile, in Profile2Iid, out extended), "IConnectionProfile2.QueryInterface");
            token.ThrowIfCancellationRequested();
            if (extended == 0) throw WifiInvalid("Missing WLAN profile interface.");
            Check(Method<WinRtGetBoolean>(extended, 7)(extended, out var wlan), "IsWlanConnectionProfile");
            token.ThrowIfCancellationRequested();
            if (wlan == 0) return null;
            if (wlan != 1) throw WifiInvalid("Invalid WLAN profile flag.");
            Check(Method<WinRtGetInt32>(profile, 7)(profile, out var level), "GetNetworkConnectivityLevel");
            token.ThrowIfCancellationRequested();
            if (level == 0) return null;
            if (level is < 1 or > 3) throw WifiInvalid("Unknown connection activity.");
            Check(Method<WinRtGetInterface>(profile, 11)(profile, out adapter), "ConnectionProfile.NetworkAdapter");
            token.ThrowIfCancellationRequested();
            if (adapter == 0) throw WifiInvalid("Connected Wi-Fi has no network adapter.");
            Check(Method<WinRtGetGuid>(adapter, 10)(adapter, out var adapterId), "NetworkAdapterId");
            token.ThrowIfCancellationRequested();
            Check(Method<WinRtGetInterface>(adapter, 9)(adapter, out network), "NetworkAdapter.NetworkItem");
            token.ThrowIfCancellationRequested();
            if (network == 0) throw WifiInvalid("Connected Wi-Fi has no network identity.");
            Check(Method<WinRtGetGuid>(network, 6)(network, out var networkId), "NetworkItem.NetworkId");
            token.ThrowIfCancellationRequested();
            if (adapterId == Guid.Empty || networkId == Guid.Empty) throw WifiInvalid("Missing Wi-Fi resource identity.");
            return $"{adapterId:N}/{networkId:N}";
        } finally {
            try {if (network != 0) runtime.Release(network);}
            finally {try {if (adapter != 0) runtime.Release(adapter);} finally {if (extended != 0) runtime.Release(extended);}}
        }
    }
    private WifiConnectionSnapshot WifiFields(nint profile, Guid adapter, CancellationToken token)
    {
        var successes = 0;DeviceReadoutException? failure = null;
        void Failed(DeviceReadoutException error) {if (failure is null || error.Code == ErrorCode.PermissionDenied) failure = error;}
        string? ssid = null;WifiSecurity? security = null;double? rssi = null;
        nint extended = 0, details = 0, text = 0;
        try {
            Check(Marshal.QueryInterface(profile, in Profile2Iid, out extended), "IConnectionProfile2.QueryInterface");
            token.ThrowIfCancellationRequested();
            if (extended == 0) throw WifiInvalid("Missing WLAN profile interface.");
            Check(Method<WinRtGetInterface>(extended, 9)(extended, out details), "WlanConnectionProfileDetails");
            token.ThrowIfCancellationRequested();
            if (details != 0) {
                Check(Method<WinRtGetInterface>(details, 6)(details, out text), "GetConnectedSsid");
                token.ThrowIfCancellationRequested();
                var buffer = WindowsGetStringRawBuffer(text, out var length);
                if (length > 65536 || (length != 0 && buffer == 0)) throw WifiInvalid("Invalid SSID string.");
                ssid = length == 0 ? "" : Marshal.PtrToStringUni(buffer, (int)length);
            }
            successes++;
        } catch (DeviceReadoutException error) {Failed(error);}
        finally {
            try {if (text != 0) WindowsDeleteString(text);}
            finally {try {if (details != 0) runtime.Release(details);} finally {if (extended != 0) runtime.Release(extended);}}
        }
        token.ThrowIfCancellationRequested();nint settings = 0;
        try {
            Check(Method<WinRtGetInterface>(profile, 14)(profile, out settings), "NetworkSecuritySettings");
            token.ThrowIfCancellationRequested();
            if (settings != 0) {
                Check(Method<WinRtGetInt32>(settings, 6)(settings, out var authentication), "NetworkAuthenticationType");
                token.ThrowIfCancellationRequested();
                int? encryption = null;
                if (authentication is 0 or 2) {
                    Check(Method<WinRtGetInt32>(settings, 7)(settings, out var value), "NetworkEncryptionType");
                    token.ThrowIfCancellationRequested();encryption = value;
                }
                security = authentication switch {
                    0 or 2 => encryption switch {0 => WifiSecurity.Open, 2 or 3 or 4 => WifiSecurity.Wep, _ => null},
                    3 => WifiSecurity.Wep, 4 or 7 => WifiSecurity.Eap, 5 or 8 => WifiSecurity.Psk,
                    10 => WifiSecurity.EapWpa3Enterprise192Bit, 11 => WifiSecurity.Sae,
                    12 => WifiSecurity.Owe, 13 => WifiSecurity.EapWpa3Enterprise, _ => null
                };
            }
            successes++;
        } catch (DeviceReadoutException error) {Failed(error);}
        finally {if (settings != 0) runtime.Release(settings);}
        token.ThrowIfCancellationRequested();
        try {rssi = ReadWlanRssi(adapter, token);successes++;}
        catch (DeviceReadoutException error) when (error.Code != ErrorCode.EntityRemoved) {Failed(error);}
        token.ThrowIfCancellationRequested();
        if (successes == 0) throw failure!;
        return new WifiConnectionSnapshot {Ssid = ssid, Security = security, RssiDbm = rssi};
    }
    private static DeviceReadoutException WifiInvalid(string message) => new(ErrorCode.ReadFailed, message);
    [DllImport("combase.dll")] private static extern nint WindowsGetStringRawBuffer(nint value, out uint length);
    [DllImport("combase.dll")] private static extern int WindowsDeleteString(nint value);
}
