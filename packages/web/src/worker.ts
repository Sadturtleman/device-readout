import { serveCollector, type CollectorPort } from '@device-readout/core/collector';
import { BrowserCollector, type BrowserEnvironment } from './browser-collector.js';

const scope = globalThis as unknown as BrowserEnvironment & {
  postMessage(value: unknown): void;
};
const port: CollectorPort = {
  send: response => scope.postMessage(response),
  listen(listener) {
    const message = (event: Event) => listener((event as MessageEvent).data);
    scope.addEventListener('message', message);
    return () => scope.removeEventListener('message', message);
  }
};
serveCollector(new BrowserCollector(scope), port);
