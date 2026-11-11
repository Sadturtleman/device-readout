import type { Instant, Duration } from './values.js';
export interface DeviceSnapshot { readonly collectedAt: Instant; }
export type CalendarId = string;
export type NumberingSystemId = string;
export interface Size<T = number> { readonly width: T; readonly height: T; }
export interface Rect { readonly x: number; readonly y: number; readonly width: number; readonly height: number; }
export interface Insets { readonly top: number; readonly right: number; readonly bottom: number; readonly left: number; }
export interface Vector3 { readonly x: number; readonly y: number; readonly z: number; }
export interface Quaternion extends Vector3 { readonly w: number; }
export interface DisplayMode { readonly pixelSize: Size | null; readonly refreshRateHz: number | null; }
export type IpAddress = string;
export interface IpAddressInfo { readonly address: IpAddress; readonly prefixLength: number | null; }
export interface NetworkRoute { readonly destination: IpAddress; readonly prefixLength: number | null; readonly gateway: IpAddress | null; }
export class ImmutableSet<T> implements ReadonlySet<T> {
  readonly #values: Set<T>;
  constructor(values: Iterable<T>) { this.#values = new Set(values); Object.freeze(this); }
  get size(): number { return this.#values.size; }
  has(value: T): boolean { return this.#values.has(value); }
  entries(): IterableIterator<[T,T]> { return this.#values.entries(); }
  keys(): IterableIterator<T> { return this.#values.keys(); }
  values(): IterableIterator<T> { return this.#values.values(); }
  [Symbol.iterator](): IterableIterator<T> { return this.values(); }
  forEach(callback: (value:T,value2:T,set:ReadonlySet<T>)=>void, thisArg?: unknown): void { this.#values.forEach(value=>callback.call(thisArg,value,value,this)); }
  toJSON(): readonly T[] { return [...this.#values]; }
}
export type { Instant, Duration };
