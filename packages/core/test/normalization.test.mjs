import test from 'node:test';
import assert from 'node:assert/strict';
import { RelativeOrientationEntity, AbsoluteOrientationEntity, NetworkPerformanceEntity } from '../dist/index.js';
import { fixture } from './fixture.mjs';

test('collectedAt follows lazy native field preparation on the collection worker', async t => {
  const access=fixture(t,{completionBoundary:true});
  const snapshot=await access.get(NetworkPerformanceEntity);
  assert.ok(snapshot.collectedAt.epochMilliseconds >= snapshot.downlinkBps,
    'The completion timestamp must follow the last field access');
  assert.ok(snapshot.collectedAt.epochMilliseconds <= Date.now());
  assert.equal(snapshot.browserOnline,false);
});

test('orientation get and watch return unit quaternions with finite extremes and preserved signs', {timeout:10000}, async t => {
  const samples = [
    {x:NaN,y:0,z:0,w:1}, {x:0,y:Infinity,z:0,w:1},
    {x:0,y:0,z:-Infinity,w:1}, {x:0,y:0,z:0,w:NaN}, null,
    {x:0,y:0,z:0,w:0}, {x:0,y:0,z:0,w:1}, {x:0,y:0,z:0,w:-1},
    {x:0,y:0,z:3,w:4}, {x:0,y:0,z:-3,w:-4},
    {x:Number.MAX_VALUE,y:Number.MAX_VALUE,z:0,w:0}, {x:Number.MIN_VALUE,y:0,z:0,w:0}
  ];
  const expected = [null,null,null,null,null,null,
    {x:0,y:0,z:0,w:1}, {x:0,y:0,z:0,w:-1},
    {x:0,y:0,z:0.6,w:0.8}, {x:0,y:0,z:-0.6,w:-0.8},
    {x:0.7071067811865475,y:0.7071067811865475,z:0,w:0}, {x:1,y:0,z:0,w:0}];
  for (const kind of [RelativeOrientationEntity, AbsoluteOrientationEntity]) {
    const access = fixture(t), target = access.observers.target(kind,'rotation');
    const remove = access.observers.sensorSource(target, {subscribe(session) {
      for (const value of samples) session.publish({value});
    }});
    const stream = access.watch(target)[Symbol.asyncIterator]();
    try {
      assert.equal((await access.get(target)).value,null);
      for (const value of expected) {
        const snapshot = (await stream.next()).value;
        assert.ok(snapshot);
        if (value === null) assert.equal(snapshot.value,null);
        else for (const axis of ['x','y','z','w']) {
          assert.ok(Math.abs(snapshot.value[axis]-value[axis]) <= 1e-15, `${kind.kind} ${axis}`);
        }
      }
    } finally {await stream.return();remove();access.close();}
  }
});
