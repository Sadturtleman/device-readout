# Windows publisher identity — 2026-11-11

WindowsPublisherIdentity now reads the native publisher-context system identifier through the public typed get/watch API. All 72 .NET checks pass in the normal-user Windows process, with zero build warnings/errors. This adds the fourteenth Windows entity collector; the full SDK remains incomplete.

```csharp
using var access = WindowsDeviceAccess.Create();
WindowsPublisherIdentitySnapshot identity =
    await access.Get(Entities.WindowsPublisherIdentity, cancellationToken);

await foreach (var snapshot in access.Watch(Entities.WindowsPublisherIdentity, cancellationToken)) {
    Consume(snapshot);
}
```

## Identifier meaning and field mapping

[SystemIdentification.GetSystemIdForPublisher](https://learn.microsoft.com/en-us/uwp/api/windows.system.profile.systemidentification.getsystemidforpublisher?view=winrt-26100) provides the native value. Its source depends on the available TPM, UEFI or registry path; it is not a cross-platform permanent hardware serial. Persistence depends on the native source and app context.

The [class documentation](https://learn.microsoft.com/en-us/uwp/api/windows.system.profile.systemidentification?view=winrt-26100) specifies that unpackaged Win32 apps and packaged apps without a publisher ID share the same system ID. The SDK preserves that behavior. Its name does not imply separate identifiers for every unpackaged executable, installation or SDK context. This implementation does not call GetSystemIdForUser, derive a replacement identifier or persist its own ID.

| Snapshot field | Mapping |
|---|---|
| PublisherId | Native IBuffer bytes, represented as lowercase hexadecimal without separators. Leading and all-zero bytes in a nonempty buffer are retained. Null or empty native buffers become null. |
| Source | Explicit native mapping: 1 → Tpm, 2 → Uefi, 3 → Registry. Native None (0), unknown values or an unreadable source become null. |
| CollectedAt | The common runtime stamps snapshot collection completion. It is not an identifier creation time. |

The numeric mapping follows [SystemIdentificationSource](https://learn.microsoft.com/en-us/uwp/api/windows.system.profile.systemidentificationsource?view=winrt-26100); SDK enum ordinals are not cast from native values. Source is this entity's domain field, not metadata attached to every SDK field.

One unreadable field becomes null while the other remains available. If both field reads actually fail, the whole query throws PermissionDenied when either reports E_ACCESSDENIED, otherwise ReadFailed. A successful read of an unknown source or absent buffer is still a successful field read, even though its public value is null. Failure of GetSystemIdForPublisher itself is a whole-query error. No report pointer after a successful call is ReadFailed. Unavailable class/interface activation is UnsupportedEntity. ReadTimeout and cancellation use the common runtime contract.

## Native lifetime and execution

Construction performs no native query. First use initializes WinRT and activates the native factory on the collection worker. The factory belongs to the DeviceAccess context; every get and poll requests a fresh report. Watch performs its initial read and serial polling, retaining equal values. It uses the existing immutable poll interval setting, initially one second. No native change-event source is registered for this entity.

Native report, buffer and byte-access interfaces are released after every read, including failed getters returning nonzero output pointers. The byte pointer belongs to the buffer and is not separately freed. Buffer length must not exceed capacity or the collector's 65,536-byte copy limit. Invalid length, missing byte access or failed buffer access leaves PublisherId null when Source remains readable.

The ABI mapping was checked against the installed Windows SDK 10.0.26100.0 headers: `windows.system.profile.h` declares ISystemIdentificationStatics and ISystemIdentificationInfo, `windows.storage.streams.h` declares IBuffer, and `robuffer.h` declares IBufferByteAccess. The latter inherits IUnknown, so its Buffer method is slot 3; the WinRT property interfaces inherit IInspectable.

Initialization, activation, getters, byte copying and all reference/runtime cleanup stay on the worker. Context closure releases the factory and balances successful WinRT initialization there. Deadline or cancellation releases the caller without joining native work; once a pending report call returns, its result is discarded and released without further property collection. Native calls cannot be forcibly interrupted by this implementation, and a permanently blocked call can delay cleanup and other operations on that worker. This is scheduling isolation, not native process-crash isolation.

No UI lookup, screen access or permission prompt is added. The app-owned observer requirements continue to apply to UI and permission state.

## Evidence

Five public-API cases extend the preceding 67-check suite:

* Controlled native COM interfaces verify exact bytes `00 01 02 ff` → `000102ff`, explicit TPM/UEFI/registry mapping, fresh report reads, equal-value polling and one worker distinct from the caller. Reference counts return to zero on context closure.
* Partial-field inputs verify independent null behavior, unknown sources, empty/null buffers, nonempty zero bytes, typed whole-query errors and successful subsequent explicit reads. The first regression reproduced an unreadable ID incorrectly failing the otherwise readable snapshot.
* Controlled invalid lengths, capacity/getter failures, failed QueryInterface with a nonzero returned interface, missing byte access, null data and whole-query report failures verify field isolation and native reference cleanup.
* A held native report call verifies independent deadlines, caller cancellation and context closure. Host continuation runs while the native call is pending. A reproduced defect caused follow-up property reads after cancellation; those reads are now suppressed, and the late report/factory are released on the worker.
* Actual Windows native reads return a 32-byte identifier and Tpm source in the normal-user process. Repeated get and initial/equal watch values agree within that process. Native initialization, activation and reference release are worker-owned and runtime initialization is balanced. The test prints byte length and source only, never the identifier value.

The actual positive case fails inside this tool's restricted process: GetSystemIdForPublisher returns E_INVALIDARG (`0x80070057`), exposed as ReadFailed. A separate Windows PowerShell WinRT projection, without SDK code, reproduces the same restricted-process error. Its normal-user invocation succeeds and reports Tpm. The SDK test is not weakened to accept arbitrary native errors; the final complete suite is run in the normal-user environment. This evidence does not identify the internal OS condition causing the restricted-process error.

The final build/run is recorded in `.tools/windows-publisher-identity-cancellation-green.log`: 72/72 passed, zero warnings/errors. Earlier normal-user evidence is in `.tools/windows-publisher-identity-native-normal-user.log` and `.tools/windows-publisher-identity-buffers.log`. Reproduced failures are in `.tools/windows-publisher-identity-red.log`, `.tools/windows-publisher-identity-partial-red.log` and `.tools/windows-publisher-identity-cancellation-red.log`; the restricted native result is in `.tools/windows-publisher-identity-native.log`.

```powershell
# Run in a normal-user Windows process for the actual identity-positive case.
./tools/test-dotnet.ps1
```

No other language/browser suites were rerun for this Windows-only change.

## Remaining evidence and scope

Packaged apps with different publishers, UEFI/registry-only physical systems, TPM or firmware changes, reinstall/reset persistence, enterprise restrictions and the Windows architecture/version matrix remain unverified. Controlled sources establish mapping behavior, not physical identity persistence. The current native result is one host's TPM-backed value, not proof of universal availability or permanence.

Remaining Windows collectors, UI observer adapters, physical device transitions, Apple/Swift, Flutter/RN and the full cross-platform acceptance matrix remain in scope. See the [implementation ledger](../implementation-status.md).
