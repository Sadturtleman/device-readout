using System.Runtime.InteropServices;

namespace DeviceReadout.Windows;

internal sealed partial class WindowsConnectivity
{
    private readonly ResourceCatalog cellular = new();
    private static readonly Guid Account2Iid = new("38f52f1c-1136-4257-959f-b658a352b6d4");
    private static readonly Guid Device4Iid = new("263f3152-7b9d-582c-b17c-f80a60b50031");
    private void EnsureCellularFactory()
    {
        EnsureRuntime();
        if (cellularUnavailable) throw new DeviceReadoutException(ErrorCode.UnsupportedEntity, "Windows mobile broadband accounts are unavailable.");
        if (cellularFactory != 0) return;
        cellularFactory = runtime.ActivateCellularFactory();
        if (cellularFactory == 0) {cellularUnavailable = true;throw new DeviceReadoutException(ErrorCode.UnsupportedEntity, "Windows mobile broadband accounts are unavailable.");}
    }
    internal EntityCapabilities CellularCapabilities(string? target)
    {
        if (target is not null) _ = ResolveCellular(target);
        return new(!cellularUnavailable && !closed, !cellularUnavailable && !closed);
    }
    internal IReadOnlyList<string> ListCellular(CancellationToken token)
    {
        token.ThrowIfCancellationRequested();EnsureCellularFactory();token.ThrowIfCancellationRequested();
        EnsureCellularObservation();var before = BeginCellularInventory();token.ThrowIfCancellationRequested();
        nint vector = 0;
        try {
            Check(Method<WinRtGetInterface>(cellularFactory, 6)(cellularFactory, out vector), "AvailableNetworkAccountIds");
            token.ThrowIfCancellationRequested();
            if (vector == 0) throw CellularInvalid("Missing account inventory.");
            Check(Method<WinRtGetUInt32>(vector, 7)(vector, out var size), "NetworkAccountIds.Size");
            if (size > 4096) throw CellularInvalid("Account inventory exceeds the collection bound.");
            var ids = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            for (uint index = 0; index < size; index++) {
                token.ThrowIfCancellationRequested();nint text = 0;
                try {
                    Check(Method<WinRtGetAt>(vector, 6)(vector, index, out text), "NetworkAccountIds.GetAt");
                    token.ThrowIfCancellationRequested();var id = CellularString(text);
                    if (id.Length == 0 || !ids.Add(id)) throw CellularInvalid("Missing or duplicate account identity.");
                } finally {if (text != 0) WindowsDeleteString(text);}
            }
            token.ThrowIfCancellationRequested();return UpdateCellularInventory(ids, before);
        } finally {if (vector != 0) runtime.Release(vector);}
    }
    internal string? CurrentCellular(CancellationToken token)
    {
        var targets = ListCellular(token);token.ThrowIfCancellationRequested();EnsureFactory();
        var preferred = PreferredCellularAdapter(token);if (preferred is null) return null;
        var matches = new List<string>();
        foreach (var target in targets) {
            token.ThrowIfCancellationRequested();nint account = 0;
            try {
                account = OpenCellularAccount(ResolveCellular(target), token);
                if (CellularProfiles(account, token, (profile, _) => ActiveCellularAdapter(profile, token)).Contains(preferred)) matches.Add(target);
            } finally {if (account != 0) runtime.Release(account);}
        }
        // A profile's adapter alone is insufficient when several accounts claim the same active path.
        ListCellular(token);
        if (matches.Count != 1 || PreferredCellularAdapter(token) != preferred) return null;
        _ = ResolveCellular(matches[0]);return matches[0];
    }
    private Guid? PreferredCellularAdapter(CancellationToken token)
        => CellularInterface<Guid?>(factory, 7, "GetInternetConnectionProfile", token, profile => profile == 0 ? null
            : CellularQuery<Guid?>(profile, Profile2Iid, token, extended => CellularWwan(extended, token) ? ActiveCellularAdapter(profile, token) : null));
    private Guid? ActiveCellularAdapter(nint profile, CancellationToken token)
    {
        var level = CellularInteger(profile, 7, "GetNetworkConnectivityLevel", token);
        if (level == 0) return null;
        if (level is < 1 or > 3) throw CellularInvalid("Unknown cellular connection activity.");
        return CellularInterface<Guid?>(profile, 11, "ConnectionProfile.NetworkAdapter", token, adapter => {
            if (adapter == 0) throw CellularInvalid("Active cellular profile has no adapter.");
            Check(Method<WinRtGetGuid>(adapter, 10)(adapter, out var id), "NetworkAdapterId");token.ThrowIfCancellationRequested();
            if (id == Guid.Empty) throw CellularInvalid("Active cellular profile has no adapter identity.");
            return id;
        });
    }
    internal CellularSubscriptionSnapshot ReadCellular(string? target, CancellationToken token)
    {
        _ = ResolveCellular(target);ListCellular(token);var id = ResolveCellular(target);
        nint account = 0;
        try {
            account = OpenCellularAccount(id, token);
            var snapshot = CellularFields(account, token);
            ListCellular(token);_ = ResolveCellular(target);token.ThrowIfCancellationRequested();return snapshot;
        } catch (DeviceReadoutException error) when (error.Code == ErrorCode.EntityRemoved) {cellular.Retire(target!);throw;}
        finally {if (account != 0) runtime.Release(account);}
    }
    private CellularSubscriptionSnapshot CellularFields(nint account, CancellationToken token)
    {
        var successes = 0;DeviceReadoutException? failure = null;
        T Field<T>(Func<T> read, T absent)
        {
            token.ThrowIfCancellationRequested();
            try {var result = read();token.ThrowIfCancellationRequested();successes++;return result;}
            catch (DeviceReadoutException error) {if (failure is null || error.Code == ErrorCode.PermissionDenied) failure = error;return absent;}
        }
        var name = Field<string?>(() => CellularText(account, 8, "ServiceProviderName", token), null);
        var slot = Field<int?>(() => CellularInterface(account, 10, "CurrentDeviceInformation", token, device =>
            device == 0 ? null : CellularQuery<int?>(device, Device4Iid, token, extended =>
                extended == 0 ? null : CellularInterface<int?>(extended, 6, "SlotManager", token, manager => {
                    if (manager == 0) return null;
                    var value = CellularInteger(manager, 7, "CurrentSlotIndex", token);return value >= 0 ? value : null;
                }), optional: true)), null);
        var roaming = Field<bool?>(() => CellularInterface<bool?>(account, 9, "CurrentNetwork", token, network =>
            network == 0 ? null : CellularInteger(network, 7, "NetworkRegistrationState", token) switch {3 => false, 4 or 5 => true, _ => null}), null);
        var home = Field<string?>(() => CellularInterface<string?>(account, 10, "CurrentDeviceInformation", token, device => {
            if (device == 0 || CellularInteger(device, 10, "CellularClass", token) != 1) return null;
            var providers = CellularProfiles(account, token, (profile, extended) => CellularInterface<string?>(extended, 8, "WwanConnectionProfileDetails", token,
                details => details == 0 ? null : CellularText(details, 6, "HomeProviderId", token)));
            if (providers.Count == 0 || providers[0] is not {Length: 5 or 6} id || id.Any(c => c is < '0' or > '9')
                || providers.Any(value => value != id)) return null;
            return id;
        }), null);
        var radio = Field<RadioTechnology?>(() => {
            var profiles = CellularProfiles(account, token, (profile, extended) => {
                var level = CellularInteger(profile, 7, "GetNetworkConnectivityLevel", token);
                if (level == 0) return (Active: false, Radio: (RadioTechnology?)null);
                if (level is < 1 or > 3) throw CellularInvalid("Unknown cellular connection activity.");
                var technology = CellularInterface<RadioTechnology?>(extended, 8, "WwanConnectionProfileDetails", token, details => {
                    if (details == 0) return null;
                    Check(Method<WinRtGetUInt32>(details, 9)(details, out var value), "GetCurrentDataClass");
                    token.ThrowIfCancellationRequested();
                    return value switch {
                        1 => RadioTechnology.Gprs, 2 => RadioTechnology.Edge, 4 => RadioTechnology.Umts,
                        8 => RadioTechnology.Hsdpa, 16 => RadioTechnology.Hsupa, 32 => RadioTechnology.Lte,
                        64 => RadioTechnology.NrNsa, 128 => RadioTechnology.NrSa, 65536 => RadioTechnology.Cdma1x,
                        131072 => RadioTechnology.Evdo0, 262144 => RadioTechnology.EvdoA, 2097152 => RadioTechnology.EvdoB, _ => null
                    };
                });
                return (Active: true, Radio: technology);
            }).Where(value => value.Active).ToArray();
            return profiles.Length != 0 && profiles.All(value => value.Radio == profiles[0].Radio) ? profiles[0].Radio : null;
        }, null);
        token.ThrowIfCancellationRequested();if (successes == 0) throw failure!;
        return new CellularSubscriptionSnapshot {CarrierName = name, SlotIndex = slot, Roaming = roaming,
            MobileCountryCode = home?[..3], MobileNetworkCode = home?[3..], RadioTechnology = radio};
    }
    private List<T> CellularProfiles<T>(nint account, CancellationToken token, Func<nint, nint, T> read)
        => CellularQuery(account, Account2Iid, token, extended => CellularInterface(extended, 6, "MobileBroadbandAccount.GetConnectionProfiles", token, vector => {
            if (vector == 0) throw CellularInvalid("Missing account connection profiles.");
            Check(Method<WinRtGetUInt32>(vector, 7)(vector, out var size), "AccountConnectionProfiles.Size");
            if (size > 4096) throw CellularInvalid("Account profile inventory exceeds the collection bound.");
            var results = new List<T>();
            for (uint index = 0; index < size; index++) {
                token.ThrowIfCancellationRequested();nint profile = 0;
                try {
                    Check(Method<WinRtGetAt>(vector, 6)(vector, index, out profile), "AccountConnectionProfiles.GetAt");
                    token.ThrowIfCancellationRequested();if (profile == 0) throw CellularInvalid("Missing account connection profile.");
                    CellularQuery(profile, Profile2Iid, token, profile2 => {
                        if (CellularWwan(profile2, token)) results.Add(read(profile, profile2));
                        return true;
                    });
                } finally {if (profile != 0) runtime.Release(profile);}
            }
            token.ThrowIfCancellationRequested();return results;
        }));
    private bool CellularWwan(nint extended, CancellationToken token)
    {
        Check(Method<WinRtGetBoolean>(extended, 6)(extended, out var value), "IsWwanConnectionProfile");
        token.ThrowIfCancellationRequested();
        return value switch {0 => false, 1 => true, _ => throw CellularInvalid("Invalid WWAN profile flag.")};
    }
    private T CellularInterface<T>(nint instance, int slot, string operation, CancellationToken token, Func<nint, T> read)
    {
        token.ThrowIfCancellationRequested();nint value = 0;
        try {
            Check(Method<WinRtGetInterface>(instance, slot)(instance, out value), operation);
            token.ThrowIfCancellationRequested();return read(value);
        } finally {if (value != 0) runtime.Release(value);}
    }
    private T CellularQuery<T>(nint instance, Guid iid, CancellationToken token, Func<nint, T> read, bool optional = false)
    {
        token.ThrowIfCancellationRequested();nint value = 0;
        try {
            var hr = Marshal.QueryInterface(instance, in iid, out value);token.ThrowIfCancellationRequested();
            if (optional && hr == unchecked((int)0x80004002)) return read(0);
            Check(hr, "Mobile broadband QueryInterface");
            if (value == 0) throw CellularInvalid("Missing mobile broadband interface.");
            return read(value);
        } finally {if (value != 0) runtime.Release(value);}
    }
    private static int CellularInteger(nint instance, int slot, string operation, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();Check(Method<WinRtGetInt32>(instance, slot)(instance, out var value), operation);
        token.ThrowIfCancellationRequested();return value;
    }
    private nint OpenCellularAccount(string id, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();nint text = 0, account = 0;
        try {
            Check(WindowsCreateString(id, id.Length, out text), "WindowsCreateString");
            Check(Method<WinRtCreateAccount>(cellularFactory, 7)(cellularFactory, text, out account), "CreateFromNetworkAccountId");
            token.ThrowIfCancellationRequested();
            if (account == 0) throw new DeviceReadoutException(ErrorCode.EntityRemoved, "The selected cellular account was removed.");
            if (!string.Equals(CellularText(account, 6, "NetworkAccountId", token), id, StringComparison.OrdinalIgnoreCase))
                throw CellularInvalid("Account identity changed during collection.");
            var result = account;account = 0;return result;
        } finally {try {if (account != 0) runtime.Release(account);} finally {if (text != 0) WindowsDeleteString(text);}}
    }
    private string CellularText(nint instance, int slot, string operation, CancellationToken token)
    {
        nint text = 0;
        try {
            Check(Method<WinRtGetInterface>(instance, slot)(instance, out text), operation);
            token.ThrowIfCancellationRequested();return CellularString(text);
        } finally {if (text != 0) WindowsDeleteString(text);}
    }
    private static string CellularString(nint text)
    {
        var raw = WindowsGetStringRawBuffer(text, out var length);
        if (length > 65536 || (length != 0 && raw == 0)) throw CellularInvalid("Invalid mobile broadband string.");
        return length == 0 ? "" : Marshal.PtrToStringUni(raw, (int)length)!;
    }
    private static DeviceReadoutException CellularInvalid(string message) => new(ErrorCode.ReadFailed, message);
    [DllImport("combase.dll", CharSet = CharSet.Unicode)] private static extern int WindowsCreateString(string text, int length, out nint value);
}
