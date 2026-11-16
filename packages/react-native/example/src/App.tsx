import React, {useEffect, useState} from 'react';
import {AppState, Dimensions, ScrollView, Text, View, useWindowDimensions} from 'react-native';
import {
  createReactNativeDeviceAccess, RamEntity, ViewportEntity,
  AccelerometerEntity, CpuCoreEntity, Duration, Instant, PermissionStatus, ErrorCode, DeviceReadoutError, SensorSamplingRate,
  type SensorObserverSession, type AccelerometerSnapshot,
  observeReactNativeViewport, observeReactNativeSensorActivity, type Entity, type ViewportSnapshot,
} from '@device-readout/react-native';

// This verification app owns UI/lifecycle observations. SDK get/watch never call these RN APIs.
const access = createReactNativeDeviceAccess();
let viewport: Entity<ViewportSnapshot>;
let started = false, ready = false, expectedWindow = {width: 0, height: 0};
let sensorSamples = 0, heartbeat = 0;
let wasInactive = false, resumeAfter: number | null = null;
let focusVerified = false, blurAfter: number | null = null, blurSamples = 0;
const results: Array<{name: string; status: string; detail?: unknown}> = [];
function check(condition: unknown, message: string): asserts condition {if (!condition) throw new Error(message);}
function report(name: string, status: string, detail?: unknown) {
  const item = {name, status, detail}; results.push(item);
  console.log('DEVICE_READOUT_TEST ' + JSON.stringify(item));
}
async function scenario(name: string, action: () => Promise<unknown>) {
  const detail = await action(); report(name, 'passed', detail);
}
const delay = (ms: number) => new Promise<void>(resolve => setTimeout(resolve, ms));
async function until(condition: () => boolean, description: string) {
  const limit = Date.now() + 3000;
  while (!condition()) {if (Date.now() > limit) throw new Error('Timed out waiting for ' + description);await delay(10);}
}

async function verify() {
  await scenario('hermes-runtime', async () => {
    check(!!(globalThis as any).HermesInternal, 'The verification app must use Hermes.');
    check(BigInt('9007199254740993').toString() === '9007199254740993', 'Exact integers unavailable.');
    return {engine: 'Hermes', reactNative: '0.88.0'};
  });
  await scenario('native-ram', async () => {
    const value = await access.get(RamEntity);
    check(typeof value.kernelAccessibleBytes === 'bigint' && value.kernelAccessibleBytes > 0n, 'Native RAM unavailable.');
    check(value.collectedAt instanceof Instant && Number.isFinite(value.collectedAt.epochMilliseconds), 'Missing collection timestamp.');
    return {kernelAccessibleBytes: value.kernelAccessibleBytes.toString(), availableBytes: value.availableBytes?.toString()};
  });
  await scenario('immutable-settings-and-native-watch', async () => {
    const configured = access.withPollInterval(Duration.milliseconds(80));
    check(access.pollInterval.milliseconds === 1000, 'Original settings changed.');
    const iterator = configured.watch(RamEntity)[Symbol.asyncIterator]();
    try {
      const first = await iterator.next(), second = await iterator.next();
      check(!first.done && !second.done && second.value.collectedAt.epochMilliseconds > first.value.collectedAt.epochMilliseconds, 'Native watch did not update.');
      return {snapshots: 2, intervalMs: configured.pollInterval.milliseconds};
    } finally {await iterator.return?.();}
  });
  await scenario('native-discovery-and-context-ownership', async () => {
    const cores = await access.cpuCores.list();
    check(cores.length > 0, 'No CPU cores discovered.');
    const core = await access.get(cores[0]);
    check(Number.isInteger(core.logicalIndex), 'Selected CPU core missing.');
    const other = createReactNativeDeviceAccess();
    try {
      let rejected = false;
      try {await other.get(cores[0]);} catch (error) {rejected = (error as any).code === ErrorCode.InvalidConfiguration;}
      check(rejected, 'A foreign context accepted the target.');
    } finally {other.close();}
    return {cores: cores.length, logicalIndex: core.logicalIndex};
  });
  await scenario('mixed-native-and-app-inventory', async () => {
    const mixed = createReactNativeDeviceAccess().withPollInterval(Duration.seconds(60));
    try {
      const cores = await mixed.cpuCores.list();
      check(cores.length > 0, 'No native core available for mixed observation.');
      const native = cores[0], before = await mixed.get(native);
      check(Number.isInteger(before.logicalIndex), 'Native CPU index unavailable.');
      const app = mixed.observers.target(CpuCoreEntity, 'application-core');
      mixed.observers.publish(app, {logicalIndex: 99});
      const inventory = await mixed.cpuCores.list();
      check(inventory.length === 1 && (await mixed.get(inventory[0])).logicalIndex === 99, 'App inventory was replaced by native discovery.');
      const nativeWatch = mixed.watch(native)[Symbol.asyncIterator]();
      const appWatch = mixed.watch(app)[Symbol.asyncIterator]();
      try {
        const nativeFirst = await nativeWatch.next(), appFirst = await appWatch.next();
        check(!nativeFirst.done && nativeFirst.value.logicalIndex === before.logicalIndex, 'Native handle lost its own state.');
        check(!appFirst.done && appFirst.value.logicalIndex === 99, 'App handle lost its own state.');
        mixed.observers.publish(app, {logicalIndex: 100});
        const changed = await appWatch.next();
        check(!changed.done && changed.value.logicalIndex === 100, 'App state change was not delivered.');
        mixed.observers.remove(app);
        let removed = false;
        try {await appWatch.next();} catch (error) {removed = (error as any).code === ErrorCode.EntityRemoved;}
        check(removed, 'App target removal did not terminate its stream.');
        check((await mixed.cpuCores.list()).length === 0, 'An empty app inventory fell back to native devices.');
        check((await mixed.get(native)).logicalIndex === before.logicalIndex, 'Removing the app target invalidated the native handle.');
        return {nativeLogicalIndex: before.logicalIndex, appInitialLogicalIndex: 99, appUpdatedLogicalIndex: 100, observedInventoryEmpty: true};
      } finally {await nativeWatch.return?.();await appWatch.return?.();}
    } finally {mixed.close();}
  });
  await scenario('app-observed-viewport', async () => {
    const snapshot = await access.get(viewport);
    check(snapshot.size?.width === expectedWindow.width && snapshot.size?.height === expectedWindow.height, 'Viewport does not match the app observation.');
    return {size: snapshot.size};
  });
  await scenario('observed-exact-integer-roundtrip', async () => {
    const observed = createReactNativeDeviceAccess();
    try {
      observed.observers.publish(RamEntity, {physicalBytes: 9007199254740993n, availableBytes: 0n, lowMemory: false});
      const value = await observed.get(RamEntity);
      check(value.physicalBytes === 9007199254740993n && value.availableBytes === 0n && value.lowMemory === false, 'Bridge lost exact values.');
      observed.close();
      let removed = false;
      try {await observed.get(RamEntity);} catch (error) {removed = (error as any).code === ErrorCode.EntityRemoved;}
      check(removed, 'Closed context accepted another read.');
      return {physicalBytes: value.physicalBytes.toString()};
    } finally {observed.close();}
  });
  await scenario('app-permission-coordination', async () => {
    access.observers.permission(ViewportEntity, PermissionStatus.NotDetermined);
    let requested = false;
    const detach = access.observers.onPermissionRequest(async ({entity}) => {
      requested = true; await delay(100);
      access.observers.permission(entity, PermissionStatus.Granted);
    });
    try {
      await access.get(viewport);check(!requested, 'get requested permission implicitly.');
      const status = await access.withReadTimeout(Duration.milliseconds(25)).permissions.request(ViewportEntity);
      check(requested && status === PermissionStatus.Granted, 'Permission state did not roundtrip.');
      return {status, source: 'controlled app observer; no OS permission dialog'};
    } finally {detach();}
  });
  await scenario('independent-failure-sources', async () => {
    const observed=createReactNativeDeviceAccess().withReadTimeout(Duration.milliseconds(100));
    const screen=observed.observers.target(ViewportEntity,'failure-owned-screen');
    const first=observed.observers.failureSource(screen),second=observed.observers.failureSource(screen);
    const errorOf=(promise:Promise<unknown>)=>promise.then(()=> 'unexpected',(error:any)=>error.code);
    const errors:unknown[]=[];
    try {
      observed.observers.publish(screen,{size:{width:1,height:2}});
      first.publish(new DeviceReadoutError(ErrorCode.ReadFailed,'First provider'));
      second.publish(new DeviceReadoutError(ErrorCode.UnsupportedEntity,'Second provider'));
      errors.push(await errorOf(observed.get(screen)));
      observed.observers.failure(screen,new DeviceReadoutError(ErrorCode.PermissionDenied,'App policy'));first.close();
      errors.push(await errorOf(observed.get(screen)));
      observed.observers.failure(screen,null);errors.push(await errorOf(observed.get(screen)));
      second.close();errors.push(await errorOf(observed.get(screen)));
      observed.observers.publish(screen,{size:{width:3,height:4}});
      const fresh=(await observed.get(screen)).size;check(fresh?.width===3,'A fresh observed snapshot did not recover.');
      const sensor=observed.observers.target(AccelerometerEntity,'failure-paused-sensor');
      const sensorFailure=observed.observers.failureSource(sensor);
      observed.observers.sensorActivity(false);
      const unregister=observed.observers.sensorSource(sensor,{subscribe(){throw Error('Paused source must not start');}});
      const stream=observed.watch(sensor)[Symbol.asyncIterator]();
      try {
        let ended=false;const waiting=errorOf(stream.next()).then(code=>{ended=true;return code;});
        await delay(180);check(!ended,'Inactive demand ended before a failure was supplied.');
        sensorFailure.publish(new DeviceReadoutError(ErrorCode.PermissionDenied,'Revoked while inactive'));
        errors.push(await waiting);
        check((await observed.get(RamEntity)).kernelAccessibleBytes!>0n,'A scoped failure affected native RAM.');
      } finally {await stream.return?.();sensorFailure.close();unregister();}
      check(JSON.stringify(errors)===JSON.stringify([ErrorCode.ReadFailed,ErrorCode.PermissionDenied,ErrorCode.UnsupportedEntity,ErrorCode.ReadTimeout,ErrorCode.PermissionDenied]),'Failure ownership or inactive error delivery failed.');
      return {errors,fresh,pausedFailureDelivered:true};
    } finally {first.close();second.close();observed.close();}
  });
  await scenario('app-sensor-source-lifecycle', async () => {
    const observed = createReactNativeDeviceAccess();
    const target = observed.observers.target(AccelerometerEntity, 'application-source');
    const sessions: Array<SensorObserverSession<AccelerometerSnapshot>> = [], stopped: number[] = [];
    const sessionCount = () => sessions.length;
    const remove = observed.observers.sensorSource(target, {
      description: {name: 'Application source', minimumInterval: Duration.milliseconds(12.5)},
      subscribe(session) {
        sessions.push(session);const index = sessions.length;
        session.publish({value: {x: index, y: 0, z: 0}});
        return () => {stopped.push(index);};
      },
    });
    try {
      const description = await observed.describe(target);
      check(description.name === 'Application source' && description.minimumInterval?.milliseconds === 12.5, 'Source metadata did not roundtrip.');
      check(sessionCount() === 0 && (await observed.capabilities.get(target)).readable === true, 'Metadata/capabilities started collection.');
      const configured = observed.withSensorSamplingRate(SensorSamplingRate.hertz(60));
      const watch = configured.watch(target)[Symbol.asyncIterator]();
      try {
        const first = await watch.next();
        check(!first.done && first.value.value?.x === 1 && sessions[0].samplingRate.hertz === 60, 'Source watch did not receive its configured rate.');
        check((await configured.get(target)).value?.x === 2 && sessions[1].samplingRate === SensorSamplingRate.PlatformDefault, 'One-shot source did not use an independent default session.');
        await until(() => sessions[1].signal.aborted && stopped.includes(2), 'one-shot source cleanup');
        observed.observers.sensorActivity(false);
        await until(() => sessions[0].signal.aborted && stopped.includes(1), 'source suspension');
        sessions[0].publish({value: {x: 99, y: 0, z: 0}});
        observed.observers.sensorActivity(true);
        const resumed = await watch.next();
        check(!resumed.done && resumed.value.value?.x === 3 && sessions.length === 3, 'Source did not resume with a fresh session.');
        remove();
        let code: unknown;
        try {await watch.next();} catch (error) {code = (error as any).code;}
        check(code === ErrorCode.EntityRemoved, 'Removing a source did not end its watch.');
        await until(() => stopped.length === 3 && sessions.every(session => session.signal.aborted), 'source removal cleanup');
        return {sessions: sessions.length, stopped: stopped.slice().sort(), watchHertz: sessions[0].samplingRate.hertz, oneShotUsesPlatformDefault: true};
      } finally {await watch.return?.();}
    } finally {observed.close();}
  });
  await scenario('app-sensor-source-failure-and-close', async () => {
    const observed = createReactNativeDeviceAccess();
    const target = observed.observers.target(AccelerometerEntity, 'application-failure-source');
    const sessions: Array<SensorObserverSession<AccelerometerSnapshot>> = [], stopped: number[] = [];
    observed.observers.sensorSource(target, {subscribe(session) {
      sessions.push(session);const index = sessions.length;
      if (index === 1) session.fail(new DeviceReadoutError(ErrorCode.PermissionDenied, 'Controlled source failure.'));
      if (index === 2) throw new Error('Controlled subscription failure.');
      return () => {stopped.push(index);};
    }});
    try {
      for (const expected of [ErrorCode.PermissionDenied, ErrorCode.ReadFailed, ErrorCode.ReadTimeout]) {
        let code: unknown;
        try {await observed.withReadTimeout(Duration.milliseconds(500)).get(target);} catch (error) {code = (error as any).code;}
        check(code === expected, 'Source failure/deadline was not propagated: ' + code);
      }
      await until(() => stopped.includes(1) && stopped.includes(3), 'failed and timed-out source cleanup');
      const pending = observed.get(target).then(() => null, error => error.code);
      await until(() => sessions.length === 4, 'source read before close');
      observed.close();
      check(await pending === ErrorCode.EntityRemoved, 'Close did not settle the source read.');
      check(sessions.every(session => session.signal.aborted) && stopped.includes(4), 'Close did not release the app source.');
      return {attempts: sessions.length, stopped: stopped.slice().sort(), errors: ['PermissionDenied', 'ReadFailed', 'ReadTimeout', 'EntityRemoved']};
    } finally {observed.close();}
  });
  await scenario('native-sensor-observation', async () => {
    const sensors = await access.sensors.list(AccelerometerEntity);
    check(sensors.length > 0, 'Emulator accelerometer unavailable.');
    const first = await access.get(sensors[0]);
    check(first.value !== null, 'Native sensor sample unavailable.');
    // Keep this native subscription for external Activity pause/resume verification.
    void (async () => {
      try {for await (const sample of access.watch(sensors[0])) {
        if (sample.value) sensorSamples++;
        if (sample.value && blurAfter !== null && sample.collectedAt.epochMilliseconds >= blurAfter) {
          report('actual-focus-loss-keeps-sensors', 'passed', {before: blurSamples, sensorSamples, collectedAt: sample.collectedAt.toISOString(), blurAfter});
          focusVerified = true;blurAfter = null;
        }
        if (sample.value && resumeAfter !== null && sample.collectedAt.epochMilliseconds >= resumeAfter) {
          report('actual-sensor-resume', 'passed', {sensorSamples, collectedAt: sample.collectedAt.toISOString(), resumeAfter});
          resumeAfter = null;
        }
      }}
      catch (error) {report('live-sensor', 'failed', String(error));}
    })();
    return {count: sensors.length, first: first.value};
  });
  ready = true;
  console.log('DEVICE_READOUT_READY ' + JSON.stringify({passed: results.length, heartbeat}));
}

export default function App() {
  const window = useWindowDimensions();
  const [status, setStatus] = useState('Starting native verification');
  useEffect(() => {
    const viewportObservation = observeReactNativeViewport(access, Dimensions);
    viewport = viewportObservation.entity;
    const lifecycle = observeReactNativeSensorActivity(access, AppState);
    // Independent diagnostics do not publish SDK state; the reusable adapters own that path.
    const track = (state: string | null) => {
      if (ready && state !== 'active') {wasInactive = true;blurAfter = null;}
      if (ready && state === 'active' && wasInactive) {wasInactive = false;resumeAfter = Date.now();}
      if (ready) console.log('DEVICE_READOUT_LIFECYCLE ' + JSON.stringify({state, sensorSamples, heartbeat}));
    };
    const observation = AppState.addEventListener('change', track);
    const blurred = AppState.addEventListener('blur', () => {
      if (ready && !focusVerified && AppState.currentState === 'active') {blurAfter = Date.now();blurSamples = sensorSamples;}
      if (ready) console.log('DEVICE_READOUT_FOCUS ' + JSON.stringify({state: 'blur', appState: AppState.currentState}));
    });
    const focused = AppState.addEventListener('focus', () => {blurAfter = null;});
    const ticks = setInterval(() => {heartbeat++;}, 20);
    if (!started) {
      started = true;
      void verify().then(() => setStatus('Baseline passed — awaiting window/lifecycle checks'))
        .catch(error => {report('verification', 'failed', {message: String(error), stack: (error as Error).stack});setStatus(String(error));});
    }
    return () => {observation.remove();blurred.remove();focused.remove();clearInterval(ticks);lifecycle.close();viewportObservation.close();access.close();};
  }, []);
  useEffect(() => {
    expectedWindow = {width: window.width, height: window.height};
    if (ready) {
      void access.get(viewport).then(value => {
        check(value.size?.width === expectedWindow.width && value.size?.height === expectedWindow.height, 'Observed viewport differs from the app window.');
        report('actual-window-change', 'passed', {size: value.size, app: expectedWindow});
      })
        .catch(error => report('actual-window-change', 'failed', String(error)));
    }
  }, [window.width, window.height, window.fontScale]);
  return <ScrollView contentContainerStyle={{padding: 24}}>
    <Text style={{fontSize: 24}}>DeviceReadout · RN 0.88</Text>
    <Text>{status}</Text>
    <View><Text>{window.width} × {window.height}</Text></View>
  </ScrollView>;
}
