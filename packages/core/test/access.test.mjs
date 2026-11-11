import test from 'node:test';
import assert from 'node:assert/strict';
import { DeviceAccess, DeviceReadoutError, ErrorCode, Duration, SensorSamplingRate } from '../dist/index.js';
import { RamEntity, DisplayEntity, NetworkPathEntity, StepDetectedEntity, AccelerometerEntity, NetworkTransport, PermissionStatus, serializeSnapshot, OriginStorageEntity, CpuCoreEntity } from '../dist/index.js';
import { fixture } from './fixture.mjs';
import { setTimeout as delay } from 'node:timers/promises';

async function waitUntil(predicate,timeout=1500) {
  const deadline=Date.now()+timeout;
  while(!predicate()){if(Date.now()>deadline)assert.fail('Application sensor state did not settle.');await delay(5);}
}

test('app target names do not alias native targets, discovery or permissions', async t=>{
  const access=fixture(t,{targets:['shared-name'],snapshots:{CpuCore:{logicalIndex:7}}});
  const [native]=await access.cpuCores.list();
  access.observers.current(CpuCoreEntity,native);
  assert.equal((await access.cpuCores.list()).length,1);
  const app=access.observers.target(CpuCoreEntity,'shared-name');
  access.observers.publish(app,{logicalIndex:99});
  access.observers.permission(app,PermissionStatus.Denied);
  access.observers.permission(native,PermissionStatus.Granted);
  assert.equal((await access.get(app)).logicalIndex,99);
  assert.equal((await access.get(native)).logicalIndex,7);
  assert.equal(await access.permissions.check(app),PermissionStatus.Denied);
  assert.equal(await access.permissions.check(native),PermissionStatus.Granted);
  assert.equal((await access.get(await access.cpuCores.current())).logicalIndex,7);
  assert.equal((await access.get((await access.cpuCores.list())[0])).logicalIndex,99);
  const stream=access.withPollInterval(Duration.milliseconds(20)).watch(native)[Symbol.asyncIterator]();
  assert.equal((await stream.next()).value.logicalIndex,7);
  access.observers.failure(app,new DeviceReadoutError(ErrorCode.PermissionDenied,'App observer failed.'));
  assert.equal((await stream.next()).value.logicalIndex,7);
  await stream.return(); // Reopen the worker with both namespaces replayed.
  assert.equal((await access.get(native)).logicalIndex,7);
  await assert.rejects(access.get(app),{code:ErrorCode.PermissionDenied});
  access.observers.remove(app);
  assert.equal((await access.get(native)).logicalIndex,7);
  await assert.rejects(access.get(app),{code:ErrorCode.EntityRemoved});
});

test('native JSON transport preserves exact integer snapshot values', async () => {
  let deliver;
  const access = new DeviceAccess({open: () => ({
    listen(message) {deliver = message; return () => {};}, close() {},
    send(request) {queueMicrotask(() => deliver({id:request.id,type:'result',value:{
      collectedAt:'2026-11-11T00:00:00Z',physicalBytes:'9007199254740993',availableBytes:'0',lowMemory:false,
      usageByCategory:{IndexedDB:'9007199254740993',Caches:'0'}
    }}));}
  })});
  try {
    const ram = await access.get(RamEntity);
    assert.equal(ram.physicalBytes, 9007199254740993n);
    assert.equal(ram.availableBytes, 0n);
    assert.equal(ram.lowMemory, false);
    assert.equal(ram.collectedAt.toISOString(), '2026-11-11T00:00:00.000Z');
    assert.deepEqual((await access.get(OriginStorageEntity)).usageByCategory, {IndexedDB:9007199254740993n,Caches:0n});
  } finally {access.close();}
});

test('a connection owner survives idle disconnect and disposes once with its access context', async () => {
  let disposed=0, connections=0;
  const factory={
    dispose() {disposed++;},
    open() {connections++; let deliver; return {
      listen(message) {deliver=message;return()=>{};}, close() {},
      send(request) {if(request.operation==='watch'||request.operation==='get')queueMicrotask(()=>deliver({
        id:request.id,type:request.operation==='watch'?'snapshot':'result',
        value:{collectedAt:'2026-11-11T00:00:00Z',physicalBytes:'12'}
      }));}
    };}
  };
  const access=new DeviceAccess(factory),configured=access.withPollInterval(Duration.seconds(2));
  const stream=configured.watch(RamEntity)[Symbol.asyncIterator]();
  await stream.next();await stream.return();
  assert.equal(disposed,0);
  assert.equal((await access.get(RamEntity)).physicalBytes,12n);
  assert.equal(connections,2);
  configured.close();access.close();
  assert.equal(disposed,1);
  const unused=new DeviceAccess(factory);unused.close();
  assert.equal(disposed,2);
  assert.equal(connections,2,'Closing an unused owner must not open a transport.');
});

test('sensor source errors, deadlines and context closure release app observations', {timeout:4000}, async t=>{
  const access=fixture(t),target=access.observers.target(AccelerometerEntity,'failing-source');let starts=0;const stopped=[];
  access.observers.sensorSource(target,{subscribe(session){
    const id=++starts;
    if(id===1)session.fail(new DeviceReadoutError(ErrorCode.PermissionDenied,'Native source denied access.'));
    if(id===2)throw Error('Native observer registration failed.');
    return()=>stopped.push(id);
  }});
  await assert.rejects(access.get(target),{code:ErrorCode.PermissionDenied});
  await assert.rejects(access.get(target),{code:ErrorCode.ReadFailed});
  await assert.rejects(access.withReadTimeout(Duration.milliseconds(80)).get(target),{code:ErrorCode.ReadTimeout});
  assert.deepEqual(stopped,[1,3]);
  const pending=access.get(target);const rejected=assert.rejects(pending,{code:ErrorCode.EntityRemoved});
  await waitUntil(()=>starts===4);access.close();await rejected;
  assert.deepEqual(stopped,[1,3,4]);
});

test('paused app sensor requests receive observer failure without starting a native source', {timeout:4000}, async t=>{
  const access=fixture(t),target=access.observers.target(AccelerometerEntity,'paused-sensor');let starts=0;
  access.observers.sensorSource(target,{subscribe(){starts++;}});
  access.observers.sensorActivity(false);
  const iterator=access.watch(target)[Symbol.asyncIterator]();let watchError,readError;
  const watch=iterator.next().then(()=>watchError='unexpected',error=>watchError=error.code);
  const read=access.get(target).then(()=>readError='unexpected',error=>readError=error.code);
  await access.permissions.check(target);
  access.observers.failure(target,new DeviceReadoutError(ErrorCode.PermissionDenied,'Revoked while hidden.'));
  await waitUntil(()=>watchError!==undefined&&readError!==undefined);
  await Promise.all([watch,read]);
  assert.equal(watchError,ErrorCode.PermissionDenied);assert.equal(readError,ErrorCode.PermissionDenied);assert.equal(starts,0);
});

test('sensor source one-shot reads release while inactive and resume with a fresh observation', {timeout:4000}, async t=>{
  const access=fixture(t),target=access.observers.target(AccelerometerEntity,'activity-sensor'),sessions=[];
  access.observers.sensorSource(target,{subscribe(session){sessions.push(session);}});
  const value=access.get(target);
  value.catch(()=>{});
  await waitUntil(()=>sessions.length===1);
  access.observers.sensorActivity(false);
  await waitUntil(()=>sessions[0].signal.aborted);
  sessions[0].publish({value:{x:99,y:0,z:0}});
  access.observers.sensorActivity(true);
  await waitUntil(()=>sessions.length===2);
  sessions[1].publish({value:{x:2,y:0,z:0}});
  assert.equal((await value).value.x,2);
  await waitUntil(()=>sessions[1].signal.aborted);
});

test('app sensor sources start lazily with per-subscription settings and stop after use', {timeout:4000}, async t=>{
  const access=fixture(t),target=access.observers.target(AccelerometerEntity,'application-sensor');
  const sessions=[],stopped=[];
  const remove=access.observers.sensorSource(target,{
    description:{name:'Application accelerometer'},
    subscribe(session){
      sessions.push(session);const id=sessions.length;
      session.publish({value:{x:id,y:0,z:9.8}});
      return()=>stopped.push(id);
    }
  });
  assert.equal(sessions.length,0);
  assert.deepEqual(await access.capabilities.get(AccelerometerEntity),{readable:true,watchable:true});
  assert.equal((await access.describe(target)).name,'Application accelerometer');
  assert.equal(sessions.length,0);
  const configured=access.withSensorSamplingRate(SensorSamplingRate.hertz(60));
  const iterator=configured.watch(target)[Symbol.asyncIterator]();
  assert.equal(sessions.length,0);
  assert.equal((await iterator.next()).value.value.x,1);
  assert.equal(sessions[0].samplingRate.hertz,60);
  assert.equal((await configured.get(target)).value.x,2);
  assert.equal(sessions[1].samplingRate,SensorSamplingRate.PlatformDefault);
  await iterator.return();
  assert.equal(sessions.every(session=>session.signal.aborted),true);
  assert.deepEqual(stopped.sort(),[1,2]);
  remove();
  await assert.rejects(access.get(target),{code:ErrorCode.EntityRemoved});
  assert.throws(()=>access.observers.sensorSource(target,{subscribe(){}}),{code:ErrorCode.EntityRemoved});
});

test('configuration copies preserve the original access and validate typed intervals', () => {
  const access = new DeviceAccess({open(){ throw new Error('configuration must not start collection'); }});
  const fast = access.withPollInterval(Duration.milliseconds(25)).withReadTimeout(Duration.seconds(2));
  assert.equal(access.pollInterval.milliseconds, 1000);
  assert.equal(access.readTimeout.milliseconds, 5000);
  assert.equal(access.sensorSamplingRate, SensorSamplingRate.PlatformDefault);
  assert.equal(fast.pollInterval.milliseconds, 25);
  assert.equal(fast.readTimeout.milliseconds, 2000);
  assert.notEqual(fast, access);
  assert.throws(() => access.withPollInterval(Duration.milliseconds(0)), {name:'InvalidConfiguration'});
});

test('discovery returns typed observed targets and current never picks an arbitrary display', async t=>{
  const access=fixture(t);
  const first=access.observers.target(DisplayEntity,'one');
  const second=access.observers.target(DisplayEntity,'two');
  access.observers.publish(first,{label:'First'});access.observers.publish(second,{label:'Second'});
  assert.equal((await access.displays.list()).length,2);
  assert.equal(await access.displays.current(),null);
  access.observers.remove(first);
  const remaining=await access.displays.list();
  assert.equal(remaining.length,1);
  assert.equal((await access.withPollInterval(Duration.seconds(2)).get(remaining[0])).label,'Second');
  const other=fixture(t);
  await assert.rejects(other.get(remaining[0]),{name:'InvalidConfiguration'});
});

test('current selection follows the host observer and is cleared when that target is removed', async t=>{
  const access=fixture(t);
  const first=access.observers.target(DisplayEntity,'first');
  const second=access.observers.target(DisplayEntity,'second');
  access.observers.publish(first,{label:'First'});
  access.observers.publish(second,{label:'Second'});
  access.observers.current(DisplayEntity,second);
  assert.equal((await access.get(await access.displays.current())).label,'Second');
  access.observers.remove(second);
  assert.equal(await access.displays.current(),null);
  assert.equal((await access.displays.list()).length,1);
});

test('an explicitly observed empty target collection stays empty across worker reconnect', async t=>{
  const access=fixture(t);
  access.observers.current(DisplayEntity,null);
  assert.deepEqual(await access.displays.list(),[]);
  const ram=access.watch(RamEntity)[Symbol.asyncIterator]();await ram.next();await ram.return();
  assert.deepEqual(await access.displays.list(),[]);
  assert.equal(await access.displays.current(),null);
});

test('the last iterator releases its worker, and observer state survives reconnecting', async()=>{
  let opens=0,closes=0,receive;
  const access=new DeviceAccess({open(){opens++;return {
    send(request){if(request.operation==='watch')queueMicrotask(()=>receive({id:request.id,type:'snapshot',value:{physicalBytes:'1',collectedAt:new Date().toISOString()}}));},
    listen(handler){receive=handler;return()=>{};}, close(){closes++;}
  };}});
  const stream=access.watch(RamEntity);
  assert.equal(opens,0);
  const iterator=stream[Symbol.asyncIterator]();
  await iterator.next();await iterator.return();
  assert.equal(closes,1);
  const again=stream[Symbol.asyncIterator]();
  await again.next();await again.return();
  assert.equal(opens,2);assert.equal(closes,2);
  access.close();
});

test('permissions are coordinated by the host observer and user response has no read timeout', {timeout:5000}, async t=>{
  const access=fixture(t);
  access.observers.permission(DisplayEntity,PermissionStatus.NotDetermined);
  assert.equal(await access.permissions.check(DisplayEntity),PermissionStatus.NotDetermined);
  const remove=access.observers.onPermissionRequest(async ({entity,signal})=>{
    assert.equal(entity,DisplayEntity);
    await delay(80,undefined,{signal});
    access.observers.permission(entity,PermissionStatus.Granted);
  });
  t.after(remove);
  const status=await access.withReadTimeout(Duration.milliseconds(15)).permissions.request(DisplayEntity);
  assert.equal(status,PermissionStatus.Granted);
});

test('target permissions inherit kind observations and keep explicit target overrides', {timeout:5000}, async t=>{
  const access=fixture(t),first=access.observers.target(AccelerometerEntity,'permission-first'),second=access.observers.target(AccelerometerEntity,'permission-second');
  access.observers.permission(AccelerometerEntity,PermissionStatus.NotDetermined);
  assert.equal(await access.permissions.check(first),PermissionStatus.NotDetermined);
  let requested;
  const remove=access.observers.onPermissionRequest(({entity})=>{requested=entity;});t.after(remove);
  const response=access.permissions.request(first);await waitUntil(()=>requested===first);
  access.observers.permission(AccelerometerEntity,PermissionStatus.Granted);
  assert.equal(await response,PermissionStatus.Granted);
  access.observers.permission(second,PermissionStatus.Denied);
  access.observers.permission(AccelerometerEntity,PermissionStatus.Restricted);
  assert.equal(await access.permissions.check(first),PermissionStatus.Restricted);
  assert.equal(await access.permissions.check(second),PermissionStatus.Denied);
  access.observers.permission(second,null);requested=undefined;
  let settled=false;const overridden=access.permissions.request(second).then(value=>{settled=true;return value;});
  await waitUntil(()=>requested===second);
  access.observers.permission(AccelerometerEntity,PermissionStatus.Granted);
  await access.permissions.check(first);assert.equal(settled,false);assert.equal(await access.permissions.check(second),null);
  access.observers.permission(second,PermissionStatus.Denied);
  assert.equal(await overridden,PermissionStatus.Denied);
});

test('unknown enum members invalidate the whole collection but empty collections remain empty', async t=>{
  const unknown=fixture(t,{snapshots:{NetworkPath:{transports:['Wifi','FutureTransport'],connectionState:'FutureState'}}});
  const snapshot=await unknown.get(NetworkPathEntity);
  assert.equal(snapshot.transports,null);
  assert.equal(snapshot.connectionState,null);
  const empty=fixture(t,{snapshots:{NetworkPath:{transports:[]}}});
  assert.equal((await empty.get(NetworkPathEntity)).transports.size,0);
  const known=fixture(t,{snapshots:{NetworkPath:{transports:['Wifi','Vpn']}}});
  assert.deepEqual([...(await known.get(NetworkPathEntity)).transports],[NetworkTransport.Wifi,NetworkTransport.Vpn]);
});

test('large integers serialize as decimal strings and snapshots expose immutable instants', async t=>{
  const snapshot=await fixture(t).get(RamEntity);
  const serialized=JSON.parse(serializeSnapshot(snapshot));
  assert.equal(serialized.physicalBytes,'9007199254740993');
  const before=snapshot.collectedAt.toISOString();
  snapshot.collectedAt.toDate().setTime(0);
  assert.equal(snapshot.collectedAt.toISOString(),before);
});

test('event watches wait beyond readTimeout and never manufacture an initial event', {timeout:5000}, async t=>{
  const access=fixture(t);
  const step=access.observers.target(StepDetectedEntity,'pedometer');
  await access.get(RamEntity);
  const iterator=access.withReadTimeout(Duration.milliseconds(20)).watch(step)[Symbol.asyncIterator]();
  let emitted=false;
  const next=iterator.next().then(result=>{emitted=true;return result;});
  await delay(70);
  assert.equal(emitted,false);
  access.observers.publish(step,{value:true});
  assert.equal((await next).value.value,true);
  await iterator.return();
});

test('one-shot event reads time out when there is no real occurrence', {timeout:5000}, async t=>{
  const access=fixture(t).withReadTimeout(Duration.milliseconds(80));
  const step=access.observers.target(StepDetectedEntity,'pedometer');
  await assert.rejects(access.get(step),{name:'ReadTimeout'});
});

test('lifecycle observers suspend sensor collection and resume with a fresh sample', {timeout:5000}, async t=>{
  const access=fixture(t);
  const accelerometer=access.observers.target(AccelerometerEntity,'motion');
  await access.get(RamEntity);
  access.observers.sensorActivity(false);
  const iterator=access.withReadTimeout(Duration.milliseconds(30)).watch(accelerometer)[Symbol.asyncIterator]();
  let delivered=false;
  const next=iterator.next().then(value=>{delivered=true;return value;});
  await delay(75);
  access.observers.publish(accelerometer,{value:{x:999,y:0,z:0}});
  await delay(20);assert.equal(delivered,false);
  access.observers.sensorActivity(true);
  access.observers.publish(accelerometer,{value:{x:1,y:2,z:3}});
  assert.equal((await next).value.value.x,1);
  access.observers.sensorActivity(false);
  const pending=iterator.next();
  await delay(75);await iterator.return();assert.equal((await pending).done,true);
});

test('inactive lifecycle disposes the native sensor session and resume creates a new session', {timeout:5000}, async t=>{
  const access=fixture(t,{nativeSensor:true});
  const [sensor]=await access.sensors.list(AccelerometerEntity);
  access.observers.sensorActivity(false);
  const iterator=access.withReadTimeout(Duration.milliseconds(100)).watch(sensor)[Symbol.asyncIterator]();
  let completed=false;const first=iterator.next().then(value=>{completed=true;return value;});
  await delay(130);assert.equal(completed,false);
  access.observers.sensorActivity(true);
  assert.equal((await first).value.value.x,1);
  access.observers.sensorActivity(false);
  await delay(100);
  completed=false;const resumed=iterator.next().then(value=>{completed=true;return value;});
  await delay(70);assert.equal(completed,false);
  access.observers.sensorActivity(true);
  assert.equal((await resumed).value.value.x,2);
  await iterator.return();
});

test('return cancels an iterator even while next is waiting for an event', {timeout:5000}, async t=>{
  const access=fixture(t);const step=access.observers.target(StepDetectedEntity,'pedometer');
  const iterator=access.watch(step)[Symbol.asyncIterator]();
  const pending=iterator.next();
  await iterator.return();
  assert.equal((await pending).done,true);
});

test('removing an observed target ends its stream with EntityRemoved', {timeout:5000}, async t=>{
  const access=fixture(t);const display=access.observers.target(DisplayEntity,'external');
  access.observers.publish(display,{brightness:0.5});
  const iterator=access.watch(display)[Symbol.asyncIterator]();await iterator.next();
  const pending=iterator.next();const rejected=assert.rejects(pending,{name:'EntityRemoved'});
  access.observers.remove(display);await rejected;
  await assert.rejects(access.get(display),{name:'EntityRemoved'});
});

test('screen state enters through observers and its updates flow without SDK UI work', {timeout:5000}, async t => {
  const access=fixture(t);
  const display=access.observers.target(DisplayEntity,'app-screen');
  access.observers.publish(display,{pixelSize:{width:1920,height:1080}});
  const screen=await access.get(display);
  assert.equal(screen.pixelSize.width,1920);
  assert.equal(screen.brightness,null);
  const stream=access.watch(display)[Symbol.asyncIterator]();
  await stream.next();
  const changed=stream.next();
  access.observers.publish(display,{pixelSize:{width:1080,height:1920}});
  assert.equal((await changed).value.pixelSize.width,1080);
  await stream.return();
});

test('observer failures terminate streams and survive reconnect with target and collection scope', {timeout:5000}, async t=>{
  const access=fixture(t),first=access.observers.target(DisplayEntity,'first'),second=access.observers.target(DisplayEntity,'second');
  access.observers.publish(first,{label:'First'});access.observers.publish(second,{label:'Second'});
  access.observers.current(DisplayEntity,second);
  const iterator=access.watch(first)[Symbol.asyncIterator]();await iterator.next();
  const denied=assert.rejects(iterator.next(),{name:'PermissionDenied'});
  access.observers.failure(first,new DeviceReadoutError(ErrorCode.PermissionDenied,'Application observer lost permission.'));
  await denied;
  await assert.rejects(access.get(first),{name:'PermissionDenied'});
  assert.equal((await access.get(second)).label,'Second');
  access.observers.failure(DisplayEntity,new DeviceReadoutError(ErrorCode.ReadFailed,'Screen inventory unavailable.'));
  await assert.rejects(access.displays.list(),{name:'ReadFailed'});
  await assert.rejects(access.displays.current(),{name:'ReadFailed'});
  await assert.rejects(access.get(second),{name:'ReadFailed'});
  access.observers.permission(DisplayEntity,PermissionStatus.Denied);
  assert.equal(await access.permissions.check(DisplayEntity),PermissionStatus.Denied);
  access.observers.failure(DisplayEntity,null);access.observers.failure(first,null);
  // Clearing an error must not make the pre-failure value current, including after worker reconnect.
  await assert.rejects(access.withReadTimeout(Duration.milliseconds(80)).get(first),{name:'ReadTimeout'});
  await assert.rejects(access.withReadTimeout(Duration.milliseconds(80)).get(first),{name:'ReadTimeout'});
  access.observers.publish(first,{label:'Fresh state'});
  assert.equal((await access.get(first)).label,'Fresh state');
  assert.equal((await access.displays.list()).length,2);
  access.observers.remove(first);
  access.observers.failure(first,new DeviceReadoutError(ErrorCode.ReadFailed,'Late callback'));
  access.observers.publish(first,{label:'Late callback must not revive a removed target'});
  await assert.rejects(access.get(first),{name:'EntityRemoved'});
  const release=access.watch(RamEntity)[Symbol.asyncIterator]();await release.next();await release.return();
  await assert.rejects(access.get(first),{name:'EntityRemoved'});
});

test('fresh state observed after a failure keeps its ordering when the worker reconnects', {timeout:5000}, async t=>{
  const access=fixture(t),display=access.observers.target(DisplayEntity,'display');
  access.observers.publish(display,{label:'Old'});
  access.observers.failure(display,new DeviceReadoutError(ErrorCode.ReadFailed,'Observer unavailable'));
  access.observers.publish(display,{label:'Fresh while unavailable'});
  await assert.rejects(access.get(display),{name:'ReadFailed'});
  access.observers.failure(display,null);
  assert.equal((await access.withReadTimeout(Duration.milliseconds(100)).get(display)).label,'Fresh while unavailable');
});

test('a blocked collector cannot block the host heartbeat or its read deadline', {timeout:5000}, async t => {
  const access=fixture(t,{blockMs:1500}).withReadTimeout(Duration.milliseconds(120));
  let ticks=0;const timer=setInterval(()=>ticks++,5);t.after(()=>clearInterval(timer));
  await assert.rejects(access.get(RamEntity),{name:'ReadTimeout'});
  assert.ok(ticks>=3, `Host made only ${ticks} heartbeat ticks while collector was blocked.`);
  clearInterval(timer);
});

test('watch polls unchanged values and emits fresh snapshots until the consumer cancels', {timeout:5000}, async t => {
  const access = fixture(t).withPollInterval(Duration.milliseconds(20));
  const stream = access.watch(RamEntity);
  const iterator = stream[Symbol.asyncIterator]();
  const first = (await iterator.next()).value;
  const second = (await iterator.next()).value;
  assert.equal(first.physicalBytes, second.physicalBytes);
  assert.ok(second.collectedAt.epochMilliseconds > first.collectedAt.epochMilliseconds);
  await iterator.return();
  assert.equal((await iterator.next()).done, true);
});

test('get returns an immutable complete RAM snapshot without losing 64-bit precision, zero or false', async t => {
  const access = fixture(t);
  const ram = await access.get(RamEntity);
  assert.equal(ram.physicalBytes, 9007199254740993n);
  assert.equal(ram.availableBytes, 0n);
  assert.equal(ram.lowMemory, false);
  assert.equal(ram.freeBytes, null);
  assert.equal(ram.kernelAccessibleBytes, null);
  assert.equal(ram.advertisedBytes, null);
  assert.equal(ram.lowMemoryThresholdBytes, null);
  assert.ok(Number.isFinite(ram.collectedAt.epochMilliseconds));
  assert.throws(() => {ram.physicalBytes = 0n;}, TypeError);
  assert.equal('changedFields' in ram, false);
});
