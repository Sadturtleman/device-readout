import {
  DeviceAccess, DeviceReadoutError, ErrorCode, ViewportEntity,
  type Entity, type ViewportSnapshot
} from '@device-readout/core';

export interface WebViewportObservation {
  readonly entity: Entity<ViewportSnapshot>;
  /** Detach this application's listeners and permanently retire the target. Idempotent. */
  close(): void;
}

let nextTarget = 0;

/**
 * Explicitly connect an application-owned Window to the SDK's observer input.
 * Only this adapter's initial/event callbacks read Window state; get/watch do not.
 */
export function observeWebViewport(access: DeviceAccess, source: Window): WebViewportObservation {
  let visual: VisualViewport | null;
  try {
    if (!source || source.window !== source) throw new DeviceReadoutError(ErrorCode.InvalidConfiguration, 'Expected an application-owned Window.');
    if (source.closed) throw new DeviceReadoutError(ErrorCode.EntityRemoved, 'The application window is closed.');
    // Check same-origin access before registering a target. Do not leave a phantom viewport on failure.
    visual = source.visualViewport;
  } catch (error) { throw windowError(error); }
  const entity = access.observers.target(ViewportEntity, `web-viewport-${++nextTarget}`);
  let closed = false;
  const close = () => {
    if (closed) return;
    closed = true;
    source.removeEventListener('resize', update);
    source.removeEventListener('pagehide', close);
    visual?.removeEventListener('resize', update);
    try { access.observers.remove(entity); }
    catch (error) { if (!(error instanceof DeviceReadoutError && error.code === ErrorCode.EntityRemoved)) throw error; }
  };
  const update = () => {
    if (closed) return;
    try {
      access.observers.publish(entity, {
        size: optional(() => ({width: source.innerWidth, height: source.innerHeight})),
        visualViewportSize: optional(() => visual ? {width: visual.width, height: visual.height} : null),
        visualViewportScale: optional(() => visual?.scale ?? null),
        safeAreaInsets: null,
        textScaleFactor: null
      });
    } catch (error) {
      if (error instanceof DeviceReadoutError && error.code === ErrorCode.EntityRemoved) close();
      else throw error;
    }
  };
  try {
    source.addEventListener('resize', update);
    source.addEventListener('pagehide', close);
    visual?.addEventListener('resize', update);
    update();
  } catch (error) { close(); throw windowError(error); }
  return Object.freeze({entity, close});
}

function optional<T>(read: () => T): T | null {
  try { return read(); } catch { return null; }
}

function windowError(error: unknown): DeviceReadoutError {
  if (error instanceof DeviceReadoutError) return error;
  const denied = typeof error === 'object' && error !== null && 'name' in error && error.name === 'SecurityError';
  return new DeviceReadoutError(denied ? ErrorCode.PermissionDenied : ErrorCode.ReadFailed,
    denied ? 'The application cannot observe this window.' : 'Cannot observe the application viewport.');
}
