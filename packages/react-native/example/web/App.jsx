import React, {useEffect, useState} from 'react';
import {AppRegistry, AppState, Dimensions, Text, View, useWindowDimensions} from 'react-native';
import {
  createReactNativeDeviceAccess, CpuEntity, ViewportEntity,
  observeReactNativeViewport, observeReactNativeSensorActivity,
} from '@device-readout/react-native';
import {attachContracts} from './contracts.js';

function App() {
  const dimensions = useWindowDimensions();
  const [snapshot, setSnapshot] = useState(null);
  const [cpu, setCpu] = useState(null);
  const [error, setError] = useState(null);
  const [heartbeat, setHeartbeat] = useState(0);
  useEffect(() => {const timer = setInterval(() => setHeartbeat(value => value + 1), 16); return () => clearInterval(timer);}, []);
  useEffect(() => {
    const access = createReactNativeDeviceAccess();
    const viewport = observeReactNativeViewport(access, Dimensions);
    const activity = observeReactNativeSensorActivity(access, AppState);
    const contracts = attachContracts(access, viewport);
    access.observers.current(ViewportEntity, viewport.entity);
    let closed = false;
    const stream = access.watch(viewport.entity)[Symbol.asyncIterator]();
    access.get(CpuEntity).then(value => {if (!closed) setCpu(value);}, failure => {if (!closed) setError(String(failure));});
    (async () => {
      try {
        while (!closed) {
          const next = await stream.next();
          if (next.done) break;
          if (!closed) setSnapshot(next.value);
        }
      } catch (failure) {if (!closed) setError(String(failure));}
    })();
    globalThis.readoutWebExample = {
      access, entity: viewport.entity,
      snapshot: () => access.get(viewport.entity),
      ...contracts.methods,
    };
    return () => {
      closed = true;
      void stream.return?.().catch(() => {});
      contracts.close();
      activity.close();
      viewport.close();
      access.close();
      delete globalThis.readoutWebExample;
    };
  }, []);
  return <View style={{padding: 24, gap: 12}}>
    <Text accessibilityRole="header" style={{fontSize: 24}}>DeviceReadout</Text>
    <Text testID="status">{error ?? (snapshot && cpu ? 'Ready' : 'Loading')}</Text>
    <Text testID="viewport">{snapshot?.size ? `${snapshot.size.width} × ${snapshot.size.height}` : '—'}</Text>
    <Text testID="framework-size">{dimensions.width} × {dimensions.height}</Text>
    <Text testID="cpu">{cpu?.availableLogicalProcessorCount ?? '—'}</Text>
    <Text testID="heartbeat">{heartbeat}</Text>
  </View>;
}

AppRegistry.registerComponent('DeviceReadoutWeb', () => App);
const root = AppRegistry.runApplication('DeviceReadoutWeb', {rootTag: document.getElementById('root')});
globalThis.unmountReadoutWebExample = () => root.unmount();
