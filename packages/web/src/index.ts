import { DeviceAccess, DeviceReadoutError, ErrorCode, type ConnectionFactory } from '@device-readout/core';
export { observeWebViewport } from './viewport-observer.js';
export type { WebViewportObservation } from './viewport-observer.js';
export { observeWebDisplays } from './display-observer.js';
export type { WebDisplayObservation, WebDisplayObserverOptions, WebScreenDetails, WebScreenDetailed } from './display-observer.js';
export { observeWebMotion } from './motion-observer.js';
export type { WebMotionEventSource, WebMotionObservation } from './motion-observer.js';
export { observeWebOrientation } from './orientation-observer.js';
export type { WebOrientationEventSource, WebOrientationObservation } from './orientation-observer.js';
export { observeWebSensorActivity } from './sensor-activity.js';
export type { WebSensorActivitySource, WebSensorActivityObservation } from './sensor-activity.js';

export interface WebDeviceAccessOptions {
  /** Override when the bundler serves the module worker at another URL. */
  readonly workerUrl?: URL;
}

/** Construction is inert. A dedicated worker starts on the first read or subscription. */
export function createWebDeviceAccess(options: WebDeviceAccessOptions = {}): DeviceAccess {
  const workerUrl = options.workerUrl ?? new URL('./worker.js', import.meta.url);
  const connection: ConnectionFactory = {
    open() {
      if (typeof Worker === 'undefined') {
        throw new DeviceReadoutError(ErrorCode.UnsupportedEntity, 'This environment cannot start a browser worker.');
      }
      const worker = new Worker(workerUrl, {type: 'module', name: 'DeviceReadout'});
      return {
        send: request => worker.postMessage(request),
        listen(onMessage, onError) {
          const message = (event: MessageEvent) => onMessage(event.data);
          const error = (event: ErrorEvent) => {
            event.preventDefault();
            onError(new DeviceReadoutError(ErrorCode.ReadFailed, event.message || 'Browser collector failed.'));
          };
          const messageError = () => onError(new DeviceReadoutError(ErrorCode.ReadFailed, 'Cannot decode collector response.'));
          worker.addEventListener('message', message);
          worker.addEventListener('error', error);
          worker.addEventListener('messageerror', messageError);
          return () => {
            worker.removeEventListener('message', message);
            worker.removeEventListener('error', error);
            worker.removeEventListener('messageerror', messageError);
          };
        },
        close: () => worker.terminate()
      };
    }
  };
  return new DeviceAccess(connection);
}
