import React, {useEffect, useState} from 'react';
import {AppState, ScrollView, Text, View, useWindowDimensions} from 'react-native';
import {
  createReactNativeDeviceAccess, RamEntity, ViewportEntity,
  AccelerometerEntity, CpuCoreEntity, Duration, Instant, PermissionStatus, ErrorCode,
} from '@device-readout/react-native';

// This verification app owns UI/lifecycle observations. SDK get/watch never call these RN APIs.
const access = createReactNativeDeviceAccess();
const viewport = access.observers.target(ViewportEntity, 'verification-window');
let started = false, ready = false, expectedWindow = {width: 0, height: 0};
let sensorSamples = 0, heartbeat = 0;
let wasInactive = false, resumeAfter: number | null = null;
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
  await scenario('native-sensor-observation', async () => {
    const sensors = await access.sensors.list(AccelerometerEntity);
    check(sensors.length > 0, 'Emulator accelerometer unavailable.');
    const first = await access.get(sensors[0]);
    check(first.value !== null, 'Native sensor sample unavailable.');
    // Keep this native subscription for external Activity pause/resume verification.
    void (async () => {
      try {for await (const sample of access.watch(sensors[0])) {
        if (sample.value) sensorSamples++;
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
    expectedWindow = {width: window.width, height: window.height};
    access.observers.publish(viewport, {size: expectedWindow, textScaleFactor: window.fontScale});
    if (ready) {
      void access.get(viewport).then(value => {
        check(value.size?.width === expectedWindow.width && value.size?.height === expectedWindow.height, 'Observed viewport differs from the app window.');
        report('actual-window-change', 'passed', {size: value.size, app: expectedWindow});
      })
        .catch(error => report('actual-window-change', 'failed', String(error)));
    }
  }, [window.width, window.height, window.fontScale]);
  useEffect(() => {
    const publish = (state: string | null) => {
      if (ready && state !== 'active') wasInactive = true;
      if (ready && state === 'active' && wasInactive) {wasInactive = false;resumeAfter = Date.now();}
      access.observers.sensorActivity(state === 'active');
      if (ready) console.log('DEVICE_READOUT_LIFECYCLE ' + JSON.stringify({state, sensorSamples, heartbeat}));
    };
    const observation = AppState.addEventListener('change', publish);
    publish(AppState.currentState ?? null);
    const ticks = setInterval(() => {heartbeat++;}, 20);
    if (!started) {
      started = true;
      void verify().then(() => setStatus('Baseline passed — awaiting window/lifecycle checks'))
        .catch(error => {report('verification', 'failed', {message: String(error), stack: (error as Error).stack});setStatus(String(error));});
    }
    return () => {observation.remove();clearInterval(ticks);access.close();};
  }, []);
  return <ScrollView contentContainerStyle={{padding: 24}}>
    <Text style={{fontSize: 24}}>DeviceReadout · RN 0.88</Text>
    <Text>{status}</Text>
    <View><Text>{window.width} × {window.height}</Text></View>
  </ScrollView>;
}
