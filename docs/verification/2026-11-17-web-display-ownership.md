# Web display ownership, inventory ordering and cleanup

Recorded on 2026-11-17 (Asia/Seoul). The final source passes **34/34 common/collector tests** and **64/64 actual-browser tests** using Chrome 158.0.8127.37 and Edge 157.0.4341.60 on Windows. TypeScript 5.0.4 library and consumer compilation also pass. This follows the [initial display adapter](2026-11-11-web-displays.md) and [independent failure-source API](2026-11-17-observer-failure-ownership.md).

## Behavior changes

`observeWebDisplays` now owns its own `failureSource(DisplayEntity)` handle. Successful refresh and disposal clear only this adapter's error. They cannot clear application policy set through `observers.failure`, another provider's failure or a later replacement owner's failure. Application policy takes precedence over the adapter's permission/read errors. Reauthorization publishes fresh state and permits new calls only when every applicable failure has been cleared. Terminated streams remain terminated.

Inventory reads carry a revision. If a newer inventory event runs while an initial `screens` or `currentScreen` getter is executing, the superseded result or exception is ignored. It cannot replace the newer inventory/current selection or close a successfully refreshed observation. SDK get/list/current calls continue to consume observer-fed state without rereading these getters.

Close attempts every listener removal and target retirement, even when an application-provided removal method throws. It also releases the adapter's failure owner. Late callbacks remain gated after closure. During hotplug, a known removed target is retired before attempting external listener cleanup. A leftover callback is associated with its original target generation and cannot read or publish for a later attachment of the same native screen object.

These changes preserve the documented requirement of one active display observer per SDK context. They do not arbitrate competing current-screen or permission publishers.

## Reproduced failures and public-boundary tests

Four new browser scenarios run independently in Chrome and Edge:

| Scenario | Initial failure | Verified outcome |
| --- | --- | --- |
| Application and independent provider ownership | Attachment/recovery cleared application denial; permission loss overwrote app failure; close erased application policy | Original policy survives attachment, permission revoke/regrant, refresh and close; independent failure remains until its own handle closes |
| Faulty host listener removal during close | First thrown cleanup stopped later removals, left targets readable behind ReadFailed and retained the adapter error | All targets become EntityRemoved, inventory becomes empty, own failure clears and late events perform no reads |
| Reentrant initial inventory | A stale getter return replaced the newer screen list/current; a stale exception tore down the successful observation | Both stale-return and stale-error fixtures retain the fresh inventory and current screen; SDK queries perform zero additional getter reads |
| Faulty host detachment during hotplug | Removed handle stayed alive, the collection failed, late callbacks read old state and the old handle recovered on reattachment | Removed stream/handle receive EntityRemoved, the remaining screen stays readable, old callbacks read nothing and only the new attachment receives later screen events |

These scenarios exercise the public adapter plus actual DeviceAccess worker transport, discovery, get and watch. Their failing getters/removers and reentrant callbacks are controlled application-boundary fixtures, not physical monitor events.

The complete browser run also retains native headless monitor addition/removal/rename, current-screen movement, native permission revoke/regrant, actual viewport resize/navigation, virtual motion/orientation/Generic Sensor measurements, resource release, and worker deadline checks. Both browsers retain 30 host timer ticks in the existing blocked-worker responsiveness fixture. Experimental magnetic/light sensor coverage remains explicitly separate from default-browser support.

## Verification commands

The final run used `npm test`, followed by `node --test packages/web/test/browser.test.mjs`, with isolated project browser profiles and an ephemeral local HTTP origin. Both commands completed successfully; all 64 browser scenarios ran without filtering. No existing user browser session or physical display settings were changed.

Focused red/green logs use `.tools/web-display-owner-{red,green}.log`, `.tools/web-display-cleanup-{red,green}.log`, `.tools/web-display-reentrant-{red,green}.log` and `.tools/web-display-detach-{red,green}.log`. Final logs are `.tools/web-display-ownership-core.log` and `.tools/web-display-ownership-browser.log`. Refreshed native monitor evidence remains in `.tools/evidence/displays-chrome.json` and `.tools/evidence/displays-edge.json`. These logs, profiles and generated output are ignored local artifacts.

## Remaining scope

Physical monitor hotplug/rotation/fractional scaling, Firefox/Safari and the latest-two-version matrix, actual visibility and BFCache restoration, mobile keyboard/pinch behavior, unavailable display/viewport fields and additional reentrant stages remain unverified. If the host refuses to remove a listener, the SDK can gate its callback but cannot force the host to release that registration. Competing observers still need application-managed replacement. Callbacks perform bounded state transfer on the app path; worker use does not mean zero main-thread overhead or process isolation.

The .NET, Android, Kotlin, Flutter and React Native implementations were not changed or rerun for this web-only checkpoint. Their existing results retain their own recorded scope. The full 46-entity/all-platform SDK objective remains active.
