import { DeviceReadoutError, ErrorCode, type Collector, type EntityAddress, type Settings } from '@device-readout/core/collector';

interface Connection extends EventTarget {
  readonly downlink?: number;
  readonly rtt?: number;
  readonly effectiveType?: string;
  readonly saveData?: boolean;
}
interface UserAgentData {
  readonly platform?: string;
  getHighEntropyValues?(hints: string[]): Promise<Record<string, unknown>>;
}
export interface BrowserEnvironment extends EventTarget {
  readonly navigator: {
    readonly hardwareConcurrency?: number;
    readonly deviceMemory?: number;
    readonly language?: string;
    readonly languages?: readonly string[];
    readonly onLine?: boolean;
    readonly connection?: Connection;
    readonly userAgentData?: UserAgentData;
    readonly storage?: {
      estimate(): Promise<{quota?: number; usage?: number; usageDetails?: Record<string, number>}>;
      persisted(): Promise<boolean>;
    };
  };
}

const attempt = <T>(read: () => T): T | null => {try {return read();} catch {return null;}};
const optional = async <T>(read: () => Promise<T>): Promise<T | null> => {try {return await read();} catch {return null;}};
const enumValue = (mapping: Readonly<Record<string, string>>, value: unknown): string | null =>
  typeof value === 'string' && Object.hasOwnProperty.call(mapping, value) ? mapping[value]! : null;
const osFamilies = {Android: 'Android', iOS: 'IOS', Windows: 'Windows', macOS: 'MacOS', Linux: 'Linux', 'Chrome OS': 'ChromeOS'};
// The browser's Desktop category includes laptops, so it cannot identify either physical form factor.
const formFactors = {Mobile: 'Phone', Tablet: 'Tablet', Automotive: 'Automotive', Watch: 'Watch', XR: 'Headset'};
const effectiveTypes = {'slow-2g': 'Slow2G', '2g': 'Type2G', '3g': 'Type3G', '4g': 'Type4G'};
const storageCategories = {indexedDB: 'IndexedDB', caches: 'Caches', serviceWorkerRegistrations: 'ServiceWorker', fileSystem: 'FileSystem'};
const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/** This collector runs exclusively inside a dedicated worker. It never accesses Window or prompts. */
export class BrowserCollector implements Collector {
  constructor(private readonly environment: BrowserEnvironment) {}

  supports(entity: EntityAddress): boolean {
    const nav = this.environment.navigator;
    switch (entity.kind) {
      case 'DeviceInfo': case 'Os': case 'Runtime': return !!nav.userAgentData;
      case 'Cpu': return typeof nav.hardwareConcurrency === 'number';
      case 'Ram': return typeof nav.deviceMemory === 'number';
      case 'Locale': case 'TimeZone': return true;
      case 'NetworkPath': return !!nav.connection;
      case 'NetworkPerformance': return !!nav.connection || typeof nav.onLine === 'boolean';
      case 'OriginStorage': return !!nav.storage;
      default: return false;
    }
  }

  async read(entity: EntityAddress, signal: AbortSignal, _settings: Settings): Promise<unknown> {
    signal.throwIfAborted();
    if (!this.supports(entity)) throw new DeviceReadoutError(ErrorCode.UnsupportedEntity, `${entity.kind} is unavailable in the browser worker; window-owned state needs an application observer.`);
    const nav = this.environment.navigator;
    switch (entity.kind) {
      case 'DeviceInfo': {
        const hints = await this.hints(['model', 'formFactors']);
        const factors = hints?.formFactors;
        return {
          modelCode: typeof hints?.model === 'string' && hints.model ? hints.model : null,
          formFactor: Array.isArray(factors) && factors.length === 1 ? enumValue(formFactors, factors[0]) : null
        };
      }
      case 'Os': return {family: enumValue(osFamilies, nav.userAgentData?.platform), name: nav.userAgentData?.platform || null};
      case 'Runtime': {
        const hints = await this.hints(['architecture', 'bitness']);
        const architecture = hints?.architecture, bits = hints?.bitness;
        return {hostArchitecture: architecture === 'arm' ? (bits === '64' ? 'Arm64' : bits === '32' ? 'Arm32' : null)
          : architecture === 'x86' ? (bits === '64' ? 'X64' : bits === '32' ? 'X86' : null) : null};
      }
      case 'Cpu': return {availableLogicalProcessorCount: nav.hardwareConcurrency};
      case 'Ram': return {advertisedBytes: nav.deviceMemory === undefined ? null : nav.deviceMemory * 1024 ** 3};
      case 'Locale': return this.locale();
      case 'TimeZone': return {ianaId: new Intl.DateTimeFormat().resolvedOptions().timeZone, utcOffsetSeconds: -new Date().getTimezoneOffset() * 60};
      case 'NetworkPath': return {saveData: nav.connection?.saveData};
      case 'NetworkPerformance': return this.networkPerformance();
      case 'OriginStorage': {
        const [estimate, persistent] = await Promise.all([
          optional(() => nav.storage!.estimate()), optional(() => nav.storage!.persisted())
        ]);
        if (estimate === null && persistent === null) throw new DeviceReadoutError(ErrorCode.ReadFailed, 'Origin storage information is unavailable.');
        const details = estimate?.usageDetails;
        let usageByCategory: Record<string, number> | null = null;
        if (details) {
          usageByCategory = {};
          for (const [category, bytes] of Object.entries(details)) {
            const mapped = enumValue(storageCategories, category);
            if (mapped === null) {usageByCategory = null; break;}
            usageByCategory[mapped] = bytes;
          }
        }
        return {quotaBytes: estimate?.quota, usageBytes: estimate?.usage, usageByCategory, persistent};
      }
    }
    throw new DeviceReadoutError(ErrorCode.UnsupportedEntity, 'No browser collector for this entity.');
  }

  private hints(names: string[]): Promise<Record<string, unknown> | null> {
    const ua = this.environment.navigator.userAgentData;
    return ua?.getHighEntropyValues ? optional(() => ua.getHighEntropyValues!(names)) : Promise.resolve(null);
  }

  private locale(): unknown {
    const nav = this.environment.navigator;
    const date = new Intl.DateTimeFormat(undefined, {hour: 'numeric'}).resolvedOptions() as Intl.ResolvedDateTimeFormatOptions & {hourCycle?: string};
    const locale = attempt(() => new Intl.Locale(nav.language || date.locale)) as (Intl.Locale & {
      getWeekInfo?: () => {firstDay: number}; weekInfo?: {firstDay: number};
    }) | null;
    const week = attempt(() => locale?.getWeekInfo ? locale.getWeekInfo() : locale?.weekInfo);
    return {
      currentLanguageTag: nav.language || date.locale,
      preferredLanguageTags: nav.languages ? [...nav.languages] : null,
      regionCode: locale?.region ?? null, scriptCode: locale?.script ?? null,
      calendar: date.calendar, numberingSystem: date.numberingSystem,
      hourCycle: date.hourCycle?.toUpperCase() ?? null,
      firstWeekday: week ? weekdays[week.firstDay - 1] ?? null : null
    };
  }

  private networkPerformance(): unknown {
    const nav = this.environment.navigator, connection = nav.connection;
    return {browserOnline: nav.onLine, downlinkBps: connection?.downlink === undefined ? null : connection.downlink * 1_000_000,
      roundTripTime: connection?.rtt, effectiveType: enumValue(effectiveTypes, connection?.effectiveType)};
  }

  observe(entity: EntityAddress, emit: (value: unknown) => void, _fail: (error: unknown) => void, signal: AbortSignal, _settings: Settings): () => void {
    if (!this.supports(entity)) throw new DeviceReadoutError(ErrorCode.UnsupportedEntity, 'Browser entity is unavailable.');
    const detach: Array<() => void> = [];
    const listen = (target: EventTarget, type: string, listener: () => void) => {
      target.addEventListener(type, listener); detach.push(() => target.removeEventListener(type, listener));
    };
    // Event handlers read only synchronous worker properties; there are no overlapping async reads.
    if (entity.kind === 'NetworkPerformance' || entity.kind === 'NetworkPath') {
      const connection = this.environment.navigator.connection;
      const changed = () => {if (!signal.aborted) emit(entity.kind === 'NetworkPath' ? {saveData: connection?.saveData} : this.networkPerformance());};
      if (connection) listen(connection, 'change', changed);
      if (entity.kind === 'NetworkPerformance') {
        listen(this.environment, 'online', changed); listen(this.environment, 'offline', changed);
      }
    } else if (entity.kind === 'Locale') {
      listen(this.environment, 'languagechange', () => {if (!signal.aborted) emit(this.locale());});
    }
    return () => {for (const remove of detach) remove();};
  }

  pollingRequired(entity: EntityAddress): boolean {
    return !['NetworkPath', 'NetworkPerformance', 'Locale'].includes(entity.kind);
  }
}
