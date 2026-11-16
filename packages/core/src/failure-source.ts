import type { DeviceReadoutError } from './errors.js';

/** A provider-owned failure slot, independent of application policy and other providers. */
export interface ObserverFailureSource {
  publish(error:DeviceReadoutError|null):void;
  /** Release only this owner's failure. Repeated close and close after context disposal are safe. */
  close():void;
}
