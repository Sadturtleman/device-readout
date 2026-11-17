// Explicit app-owned sources used by the browser integration consumer.
import {AppState} from 'react-native';
import {createReactNativeDeviceAccess, CpuEntity, RamEntity, ViewportEntity,
  RelativeOrientationEntity, Duration, DeviceReadoutError, ErrorCode, PermissionStatus} from '@device-readout/react-native';

const outcome = async action => {try {await action(); return null;} catch (error) {return error.code ?? error.name;}};

export function attachContracts(access, viewport) {
  const state = {starts: 0, stops: 0, samples: 0, errors: [], last: null, requests: 0};
  let sensor, unregister, iterator, failure, closed = false;
  const methods = {
    state: () => ({...state, appState: AppState.currentState, visibility: document.visibilityState}),
    async startSensor() {
      sensor = access.observers.target(RelativeOrientationEntity, 'app-rotation');
      failure = access.observers.failureSource(sensor);
      unregister = access.observers.sensorSource(sensor, {
        description: {name: 'App rotation'},
        subscribe(session) {
          state.starts++;
          const timer = setInterval(() => session.publish({value: {x: 0, y: 0, z: 3, w: 4}}), 20);
          return () => {clearInterval(timer); state.stops++;};
        },
      });
      const description = await access.describe(sensor);
      if (state.starts !== 0) throw Error('Metadata activated its sensor source.');
      iterator = access.watch(sensor)[Symbol.asyncIterator]();
      (async () => {
        try {
          while (!closed) {
            const next = await iterator.next();
            if (next.done) break;
            state.samples++; state.last = next.value.value;
          }
        } catch (error) {if (!closed) state.errors.push(error.code ?? error.name);}
      })();
      return description.name;
    },
    async inactiveRead() {
      const error = await outcome(() => access.withReadTimeout(Duration.milliseconds(80)).get(sensor));
      const cpu = await access.get(CpuEntity);
      return {error, cpu: cpu.availableLogicalProcessorCount, ...methods.state()};
    },
    async permission() {
      access.observers.permission(sensor, PermissionStatus.Denied);
      failure.publish(new DeviceReadoutError(ErrorCode.PermissionDenied, 'Application permission was denied.'));
      const denied = await outcome(() => access.get(sensor));
      const status = await access.permissions.check(sensor);
      const implicit = state.requests;
      const detach = access.observers.onPermissionRequest(async () => {
        state.requests++;
        await new Promise(resolve => setTimeout(resolve, 150));
        failure.publish(null);
        access.observers.permission(sensor, PermissionStatus.Granted);
      });
      const started = performance.now();
      try {
        const granted = await access.withReadTimeout(Duration.milliseconds(30)).permissions.request(sensor);
        const elapsed = performance.now() - started;
        const fresh = await access.get(sensor);
        return {denied, status, implicit, granted, elapsed, requests: state.requests, value: fresh.value};
      } finally {detach();}
    },
    async heldWorker() {
      const other = createReactNativeDeviceAccess({workerUrl: new URL('./held-worker.js', location.href)});
      let frames = 0, ticks = 0, frame;
      const animate = () => {frames++; frame = requestAnimationFrame(animate);};
      try {
        await other.get(CpuEntity);
        frame = requestAnimationFrame(animate);
        const timer = setInterval(() => ticks++, 10);
        const started = performance.now();
        try {
          const error = await outcome(() => other.withReadTimeout(Duration.milliseconds(160)).get(RamEntity));
          return {error, frames, ticks, elapsed: performance.now() - started};
        } finally {clearInterval(timer);}
      } finally {cancelAnimationFrame(frame); other.close();}
    },
    async retireViewport() {
      viewport.close();
      return {error: await outcome(() => access.get(viewport.entity)), count: (await access.list(ViewportEntity)).length};
    },
  };
  return {
    methods,
    close() {
      if (closed) return; closed = true;
      void iterator?.return?.().catch(() => {});
      failure?.close(); unregister?.();
    },
  };
}
