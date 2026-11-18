# C# Windows aggregate battery capacity validation

The Windows aggregate collector previously exposed negative design, full-charge and remaining capacity values as usable mWh. The Dart collector already rejected these values. C# now makes each negative capacity null independently and calculates level only from valid capacities. Signed discharge power, zero capacities and other readable fields remain available.

## Reproduction and correction

A public `DeviceAccess` test supplies reports at the existing WinRT ABI boundary, obtains the typed current battery handle and calls `get` and event-driven `watch`. Before the fix, the test failed with `design=-60000, full=-50000, remaining=-20000`. This is an observed returned-value failure, not a compiler failure.

| Native report | Public behavior verified |
| --- | --- |
| Negative design/full/remaining capacities, rate -5000 | All three energy fields and level are null; rate remains -5000 and status remains Discharging. Verified through get and initial watch. |
| Design 60000, full 50000, remaining -20000 | A native report event produces null remaining energy and level, preserving design, full capacity and signed power. |
| All capacities and rate zero | A native event preserves zero values and leaves level null rather than dividing by zero. |
| Design 60000, full 50000, remaining zero, rate -5000 | A native event returns level zero, remaining energy zero and signed discharge power. |

The correction is confined to the Windows aggregate field mapping. Native access and normalization remain on the existing collection worker; public configuration, deadlines and cancellation are unchanged. No unit heuristic or synthetic battery value is added. The API's capacity/level meanings follow [Microsoft's remaining-capacity documentation](https://learn.microsoft.com/en-us/uwp/api/windows.devices.power.batteryreport.remainingcapacityinmilliwatthours?view=winrt-26100); the driver-unit caveat is recorded in the [Dart/Flutter aggregate verification](2026-11-19-dart-windows-aggregate-battery.md).

## Verification

The failing test passes after the fix. `tools/test-dotnet.ps1` then passes **216/216** checks with zero build warnings and errors, including existing native aggregate reads, event registration, worker lifecycle, reference cleanup and the other Windows collector regressions. All 564 non-Markdown inputs remain unchanged between the final-suite capture and the evidence audit. The test fixture confirms reference cleanup on disposal.

The first reproduction build ended in a Roslyn `ILBuilder.BasicBlock.get_TotalSize` NullReferenceException before tests ran. The first post-fix build ended in an internal CLR error while Roslyn processed an immutable dictionary, also before tests ran. Both logs are preserved separately. Unchanged subsequent builds reached the genuine red/green test and the full passing suite; this does not prove a compiler/runtime root fix. The SDK version and compiler settings were not changed.

The physical host has no battery. Controlled native reports validate the capacity correction; positive physical energy values, charge/discharge transitions, unusual drivers and the complete SDK acceptance matrix remain pending. The separate native power gate was not rerun for this aggregate-field-only correction.

Reproduce the focused behavior with `tools/test-dotnet.ps1 -Filter 'Windows aggregate battery rejects negative energy'`. Source hashes and red, green, full-suite and compiler-failure log hashes are recorded in the ignored `.tools/evidence/dotnet-aggregate-capacity-checkpoint.json`.
