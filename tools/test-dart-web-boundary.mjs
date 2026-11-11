// Executes the compiled browser branch only as a negative import/host-isolation
// check. This is not evidence of a working browser worker or Flutter web binding.
globalThis.self = globalThis;
await import(new URL('../.tools/dart-checks/web-boundary.js', import.meta.url));
