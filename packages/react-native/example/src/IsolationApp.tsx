import React, {useEffect, useState} from 'react';
import {Text, View} from 'react-native';
import {createReactNativeDeviceAccess, Duration, ErrorCode, RamEntity, RuntimeEntity} from '@device-readout/react-native';

const delay = (ms: number) => new Promise<void>(resolve => setTimeout(resolve, ms));
function check(value: unknown, message: string): asserts value {if (!value) throw new Error(message);}

export default function IsolationApp({isolationCase}: {isolationCase: string}) {
  const [ticks, setTicks] = useState(0);
  const [status, setStatus] = useState('Verifying blocked native collection');
  useEffect(() => {
    let heartbeat = 0;
    const timer = setInterval(() => {heartbeat++;setTicks(heartbeat);}, 20);
    const access = createReactNativeDeviceAccess();
    const run = async () => {
      check(!!(globalThis as any).HermesInternal, 'Hermes is required.');
      check(['get', 'watch', 'close'].includes(isolationCase), 'Unknown isolation scenario.');
      // Complete module/context/worker startup before measuring a held collection.
      check((await access.get(RuntimeEntity)).processBitness === 64, 'Fixture warmup failed.');
      const configured = access.withReadTimeout(Duration.milliseconds(isolationCase === 'close' ? 5000 : 800));
      const initialTicks = heartbeat;
      let code: unknown, closeMs = 0;
      const started = Date.now();
      if (isolationCase === 'watch') {
        const stream = configured.watch(RamEntity)[Symbol.asyncIterator]();
        try {await stream.next();} catch (error) {code = (error as any).code;}
        finally {await stream.return?.();}
      } else if (isolationCase === 'close') {
        const result = configured.get(RamEntity).then(() => null, error => error.code);
        await delay(300);
        const closing = Date.now();access.close();closeMs = Date.now() - closing;
        code = await result;
      } else {
        try {await configured.get(RamEntity);} catch (error) {code = (error as any).code;}
      }
      const elapsedMs = Date.now() - started;
      const jsTicksDuringRead = heartbeat - initialTicks;
      check(code === (isolationCase === 'close' ? ErrorCode.EntityRemoved : ErrorCode.ReadTimeout), 'Unexpected terminal result: ' + code);
      check(jsTicksDuringRead >= 3, 'JS event loop stalled during native collection.');
      if (isolationCase !== 'close') {const closing = Date.now();access.close();closeMs = Date.now() - closing;}
      check(closeMs < 250, 'close waited for blocked collection.');
      console.log('DEVICE_READOUT_ISOLATION_CLOSED ' + JSON.stringify({case: isolationCase, closeMs}));
      const afterClose = heartbeat;
      await delay(250);
      const jsTicksAfterClose = heartbeat - afterClose;
      check(jsTicksAfterClose >= 3, 'JS event loop stalled after close.');
      const result = {case: isolationCase, status: 'passed', code, elapsedMs, closeMs, jsTicksDuringRead, jsTicksAfterClose};
      console.log('DEVICE_READOUT_ISOLATION_RESULT ' + JSON.stringify(result));
      setStatus('Passed; awaiting external collector release');
    };
    void run().catch(error => {
      console.log('DEVICE_READOUT_ISOLATION_RESULT ' + JSON.stringify({case: isolationCase, status: 'failed', error: String(error)}));
      setStatus(String(error));access.close();
    });
    return () => {clearInterval(timer);access.close();};
  }, [isolationCase]);
  return <View style={{padding: 24}}><Text>{status}</Text><Text>JS heartbeat: {ticks}</Text></View>;
}
