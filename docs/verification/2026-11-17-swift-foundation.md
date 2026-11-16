# Swift foundation verification — 2026-11-17

Scope: generated models and the initial public one-shot read API. This checkpoint does not establish Apple platform support.

## Environment and result

- Official Swift 5.9.2 Ubuntu 22.04 x86_64 toolchain, running in Ubuntu 22.04 under WSL.
- All three `DeviceAccessTests` pass; test process exits successfully.
- The package and consumers import `DeviceReadout` without test-only access.
- All 46 generated snapshot types and enum declarations compile.

## Verified behavior

1. A RAM read executes its controlled collector off the main thread, returns typed nullable values without losing zero/false, and stamps a collection-completion time.
2. A derived 60 ms read timeout leaves the original five-second configuration unchanged. A held collector does not delay the deadline or a main-actor task. Its late result cannot satisfy the next read.
3. Caller cancellation returns `CancellationError` before the held collector returns. Releasing that collector permits a subsequent independent read.

The held collectors have a one-second fail-safe release so a regression cannot hang the test indefinitely. Both deadline and cancellation assertions require completion in less than 500 ms while the collector has not returned.

## Reproduction

```sh
node tools/generate-swift.mjs
sh tools/test-swift.sh
```

Use `SWIFT_BIN` when the desired Swift toolchain is not on PATH. No Apple SDK is required for these portable foundation tests.

## Remaining work

`watch`, typed targets/discovery, app-owned observers and permission coordination, capabilities, sampling/poll configuration, value normalization and context lifetime/overload controls remain unimplemented. No Apple native collectors exist yet. iOS/macOS compilation, exact minimum-version validation, actual UI responsiveness, native measurements and the complete platform/acceptance matrix remain required. Generated entity declarations are not evidence that a platform can collect their fields.
