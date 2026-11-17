import test from 'node:test';
import assert from 'node:assert/strict';
import {createReactNativeDeviceAccess, CpuEntity, ErrorCode} from '@device-readout/react-native/web';

test('explicit web import and construction remain inert without DOM or Worker', async () => {
  assert.equal(typeof window, 'undefined');
  assert.equal(typeof Worker, 'undefined');
  const access = createReactNativeDeviceAccess();
  try {
    const stream = access.watch(CpuEntity);
    assert.ok(stream[Symbol.asyncIterator]);
    await assert.rejects(access.get(CpuEntity), error => error.code === ErrorCode.UnsupportedEntity);
  } finally {access.close();}
});
