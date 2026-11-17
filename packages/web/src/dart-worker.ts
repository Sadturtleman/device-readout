import { serveCollector, normalizeSnapshot, DeviceReadoutError, ErrorCode, type CollectorPort } from '@device-readout/core/collector';
import { BrowserCollector, type BrowserEnvironment } from './browser-collector.js';

// Dart's JS interop boundary consumes decimal strings for exact integers.
// Conversion happens here, after collection and normalization on the worker.
function wire(value: unknown): unknown {
  if (typeof value === 'bigint') return value.toString();
  if (Array.isArray(value)) return value.map(wire);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, wire(item)]));
  }
  return value;
}
const scope = globalThis as unknown as BrowserEnvironment & { postMessage(value: unknown): void };
const port: CollectorPort = {
  send: response => scope.postMessage(wire(response)),
  listen(listener) {
    const message = (event: Event) => {
      const request = (event as MessageEvent).data;
      if (request?.operation !== 'normalize') { listener(request); return; }
      try {
        const description = request.value?.description === true;
        const kind = request.entity?.kind;
        let snapshot = request.value?.snapshot;
        if (description) snapshot = {...snapshot, kind};
        else if ((kind === 'StepDetected' || kind === 'SignificantMotion') && snapshot?.value !== true) {
          throw new DeviceReadoutError(ErrorCode.ReadFailed, 'An occurrence sensor must publish an actual event.');
        }
        port.send({id:request.id,type:'result',value:normalizeSnapshot(description?'SensorDescription':kind,snapshot)});
      } catch (error) {
        port.send({id:request.id,type:'error',error:{code:error instanceof DeviceReadoutError?error.code:ErrorCode.ReadFailed,
          message:error instanceof Error?error.message:'Observed normalization failed.'}});
      }
    };
    scope.addEventListener('message', message);
    return () => scope.removeEventListener('message', message);
  }
};
serveCollector(new BrowserCollector(scope), port);
