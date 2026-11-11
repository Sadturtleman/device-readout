import {
  DeviceAccess, DeviceReadoutError, DisplayEntity, DisplayOrientation, ErrorCode, PermissionStatus as DevicePermissionStatus,
  type Entity, type DisplaySnapshot
} from '@device-readout/core';

/** Structural Window Management types for consumers whose DOM library predates ScreenDetails. */
export interface WebScreenDetailed extends EventTarget {
  readonly label: string;
  readonly isPrimary: boolean;
  readonly isInternal: boolean;
  readonly left: number;
  readonly top: number;
  readonly width: number;
  readonly height: number;
  readonly availLeft: number;
  readonly availTop: number;
  readonly availWidth: number;
  readonly availHeight: number;
  readonly devicePixelRatio: number;
  readonly colorDepth: number;
}

export interface WebScreenDetails extends EventTarget {
  readonly screens: readonly WebScreenDetailed[];
  readonly currentScreen: WebScreenDetailed | null;
}

export interface WebDisplayObservation {
  /** Detach the application's listeners and permanently retire its display targets. */
  close(): void;
}

export interface WebDisplayObserverOptions {
  /** A PermissionStatus already obtained by the application. This adapter never queries or requests it. */
  readonly permission?: PermissionStatus;
}

type Target = {entity: Entity<DisplaySnapshot>; changed: () => void};
let nextTarget = 0;

/** Connect already-authorized ScreenDetails. This never calls getScreenDetails or requests UI. */
export function observeWebDisplays(access: DeviceAccess, source: Window, details: WebScreenDetails, options: WebDisplayObserverOptions = {}): WebDisplayObservation {
  let screens: readonly WebScreenDetailed[] = [];
  let current: WebScreenDetailed | null = null;
  const permission = options.permission;
  let orientation: ScreenOrientation | undefined;
  try {
    if (!source || source.window !== source) throw new DeviceReadoutError(ErrorCode.InvalidConfiguration, 'Expected an application-owned Window.');
    if (source.closed) throw new DeviceReadoutError(ErrorCode.EntityRemoved, 'The application window is closed.');
    orientation = source.screen.orientation;
  } catch (error) { throw displayError(error); }
  const targets = new Map<WebScreenDetailed, Target>();
  let closed = false;
  let permissionObserved = false;
  let previousPermissionState: PermissionState | undefined;
  const close = () => {
    if (closed) return;
    closed = true;
    source.removeEventListener('pagehide', close);
    details.removeEventListener('screenschange', changed);
    details.removeEventListener('currentscreenchange', changed);
    orientation?.removeEventListener('change', changed);
    permission?.removeEventListener('change', changed);
    for (const [screen, target] of targets) {
      screen.removeEventListener('change', target.changed);
      try { access.observers.remove(target.entity); }
      catch (error) { if (!(error instanceof DeviceReadoutError && error.code === ErrorCode.EntityRemoved)) throw error; }
    }
    targets.clear();
    try { access.observers.failure(DisplayEntity, null); }
    catch (error) { if (!(error instanceof DeviceReadoutError && error.code === ErrorCode.EntityRemoved)) throw error; }
  };
  const report = (error: unknown) => {
    const failure = displayError(error);
    if (failure.code === ErrorCode.EntityRemoved) { close(); return; }
    try { access.observers.failure(DisplayEntity, failure); }
    catch (error) { if (error instanceof DeviceReadoutError && error.code === ErrorCode.EntityRemoved) close(); else throw error; }
  };
  const allowed = () => {
    if (!permission) return true;
    const state = permission.state;
    if (!permissionObserved || state !== previousPermissionState) {
      access.observers.permission(DisplayEntity, state === 'granted' ? DevicePermissionStatus.Granted
        : state === 'denied' ? DevicePermissionStatus.Denied : state === 'prompt' ? DevicePermissionStatus.NotDetermined : null);
      previousPermissionState = state;
      permissionObserved = true;
    }
    if (state === 'granted') return true;
    report(new DeviceReadoutError(ErrorCode.PermissionDenied, 'The application observer has no screen access permission.'));
    return false;
  };
  const publish = (screen: WebScreenDetailed, entity: Entity<DisplaySnapshot>) => {
    if (closed) return false;
    try {
      if (!allowed()) return false;
      const bounds = optional(() => ({x: screen.left, y: screen.top, width: screen.width, height: screen.height}));
      const ratio = optional(() => screen.devicePixelRatio);
      const scale = ratio !== null && Number.isFinite(ratio) && ratio > 0 ? ratio : null;
      const width = bounds && scale !== null ? Math.round(bounds.width * scale) : NaN;
      const height = bounds && scale !== null ? Math.round(bounds.height * scale) : NaN;
      access.observers.publish(entity, {
        label: optional(() => screen.label), primary: optional(() => screen.isPrimary), internal: optional(() => screen.isInternal),
        logicalBounds: bounds,
        workAreaBounds: optional(() => ({x: screen.availLeft, y: screen.availTop, width: screen.availWidth, height: screen.availHeight})),
        pixelSize: Number.isSafeInteger(width) && Number.isSafeInteger(height) && width >= 0 && height >= 0 ? {width, height} : null,
        scaleFactor: scale, colorDepthBits: optional(() => screen.colorDepth),
        // Chromium ScreenDetailed.orientation is window-scoped even for a different display.
        orientation: screen === current ? optional(() => mapOrientation(orientation?.type)) : null,
        rotationDegrees: screen === current ? optional(() => orientation?.angle ?? null) : null
      });
      return true;
    } catch (error) {
      report(error);
      return false;
    }
  };
  const refresh = () => {
    if (closed) return false;
    const present = new Set(screens);
    for (const [screen, target] of targets) {
      if (present.has(screen)) continue;
      screen.removeEventListener('change', target.changed);
      targets.delete(screen);
      access.observers.remove(target.entity);
    }
    for (const screen of screens) {
      let target = targets.get(screen);
      if (!target) {
        const entity = access.observers.target(DisplayEntity, `web-display-${++nextTarget}`);
        const changed = () => publish(screen, entity);
        target = {entity, changed};
        targets.set(screen, target);
        screen.addEventListener('change', changed);
      }
      if (!publish(screen, target.entity)) return false;
    }
    access.observers.current(DisplayEntity, current ? targets.get(current)?.entity ?? null : null);
    return true;
  };
  const refreshInput = () => {
    if (!allowed()) return;
    screens = details.screens;
    current = details.currentScreen;
    if (!Array.isArray(screens)) throw new DeviceReadoutError(ErrorCode.ReadFailed, 'Screen inventory is unavailable.');
    if (!refresh() || !allowed()) return;
    access.observers.failure(DisplayEntity, null);
  };
  const changed = () => {
    if (closed) return;
    try { refreshInput(); } catch (error) { report(error); }
  };
  try {
    source.addEventListener('pagehide', close);
    details.addEventListener('screenschange', changed);
    details.addEventListener('currentscreenchange', changed);
    orientation?.addEventListener('change', changed);
    permission?.addEventListener('change', changed);
    refreshInput();
  } catch (error) { close(); throw displayError(error); }
  return Object.freeze({close});
}

function optional<T>(read: () => T): T | null {
  try { return read(); } catch { return null; }
}

function mapOrientation(value: string | undefined): DisplayOrientation | null {
  switch (value) {
    case 'portrait-primary': return DisplayOrientation.PortraitPrimary;
    case 'portrait-secondary': return DisplayOrientation.PortraitSecondary;
    case 'landscape-primary': return DisplayOrientation.LandscapePrimary;
    case 'landscape-secondary': return DisplayOrientation.LandscapeSecondary;
    default: return null;
  }
}

function displayError(error: unknown): DeviceReadoutError {
  if (error instanceof DeviceReadoutError) return error;
  const denied = typeof error === 'object' && error !== null && 'name' in error && error.name === 'SecurityError';
  return new DeviceReadoutError(denied ? ErrorCode.PermissionDenied : ErrorCode.ReadFailed,
    denied ? 'The application cannot observe these displays.' : 'Cannot observe the application displays.');
}
