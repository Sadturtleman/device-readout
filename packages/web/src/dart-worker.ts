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
let nextDeliveryId = 0;
const deliveries = new Map<number, Map<number, () => void>>();
function releaseDeliveries(id: number): void {
  const pending = deliveries.get(id);
  deliveries.delete(id);
  for (const release of pending?.values() ?? []) release();
}
const port: CollectorPort = {
  send(response) {
    if (response.type === 'error' || response.type === 'end') releaseDeliveries(response.id);
    scope.postMessage(wire(response));
  },
  deliver(response, signal) {
    if (signal.aborted) return Promise.resolve();
    const pending = deliveries.get(response.id) ?? new Map<number, () => void>();
    if (pending.size >= 2048 || nextDeliveryId >= Number.MAX_SAFE_INTEGER) {
      throw new DeviceReadoutError(ErrorCode.ReadFailed, 'The Dart worker delivery queue is full.');
    }
    const deliveryId = ++nextDeliveryId;
    let release!: () => void;
    const delivered = new Promise<void>(resolve => {
      release = () => {
        signal.removeEventListener('abort', release);
        if (!pending.delete(deliveryId)) return;
        if (pending.size === 0) deliveries.delete(response.id);
        resolve();
      };
    });
    pending.set(deliveryId, release);
    deliveries.set(response.id, pending);
    signal.addEventListener('abort', release, {once: true});
    try { scope.postMessage(wire({...response, deliveryId})); }
    catch (error) { releaseDeliveries(response.id); throw error; }
    return delivered;
  },
  listen(listener) {
    const message = (event: Event) => {
      const request = (event as MessageEvent).data;
      if (request?.operation === 'ack') {
        deliveries.get(request.id)?.get(request.deliveryId)?.();
        return;
      }
      if (request?.operation === 'cancel') releaseDeliveries(request.id);
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
