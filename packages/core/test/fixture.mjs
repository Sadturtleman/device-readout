import { Worker } from 'node:worker_threads';
import { DeviceAccess } from '../dist/index.js';
export function fixture(t, options = {}) {
  const access = new DeviceAccess({open() {
    const worker = new Worker(new URL('./worker-fixture.mjs', import.meta.url), {workerData:options});
    return {
      send(message) { worker.postMessage(message); },
      listen(message, error) {
        worker.on('message', message); worker.on('error', error);
        const exit = code => error(new Error(`Collector exited (${code}).`));
        worker.on('exit', exit);
        return () => {worker.off('message',message);worker.off('error',error);worker.off('exit',exit);};
      },
      close() { void worker.terminate().catch(()=>{}); }
    };
  }});
  t.after(() => access.close());
  return access;
}
