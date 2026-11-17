import {createWebDeviceAccess, type WebDeviceAccessOptions} from '@device-readout/web';

export * from '@device-readout/core';
export * from '@device-readout/web';
export {observeReactNativeWebViewport as observeReactNativeViewport, observeReactNativeSensorActivity, ReactNativeSensorActivityPolicy} from './framework-observers.js';
export type {ReactNativeWindowMetrics, ReactNativeDimensionsSource, ReactNativeViewportObservation,
  ReactNativeAppStateSource, ReactNativeSensorActivityObservation} from './framework-observers.js';
export type {WebDeviceAccessOptions as ReactNativeWebDeviceAccessOptions} from '@device-readout/web';

/** Browser entrypoint: construction is inert and collection uses an owned module worker. */
export function createReactNativeDeviceAccess(options: WebDeviceAccessOptions = {}) {
  return createWebDeviceAccess(options);
}
