import test from 'node:test';
import assert from 'node:assert/strict';
import {Worker} from 'node:worker_threads';
import {resolve} from 'node:path';
import {DeviceAccess, DeviceReadoutError, Duration, ErrorCode, AccelerometerEntity, ViewportEntity} from '../../core/dist/index.js';
import {observeReactNativeViewport,observeReactNativeSensorActivity,ReactNativeSensorActivityPolicy} from '../dist/framework-observers.js';

function accessFor(t) {
  const access=new DeviceAccess({open(){
    const worker=new Worker(resolve('packages/core/test/worker-fixture.mjs'),{workerData:{}});
    return {send:value=>worker.postMessage(value),listen(message,error){worker.on('message',message);worker.on('error',error);return()=>{worker.off('message',message);worker.off('error',error);};},close(){void worker.terminate();}};
  }});
  t.after(()=>access.close());return access;
}
async function until(predicate){const end=Date.now()+2000;while(!predicate()){if(Date.now()>end)assert.fail('Observer state did not settle.');await new Promise(resolve=>setTimeout(resolve,5));}}
class DimensionsSource {
  metrics={width:100.5,height:200,fontScale:1.25,scale:3};reads=0;removed=0;listeners=new Set();
  get(name){assert.equal(name,'window');this.reads++;return this.metrics;}
  addEventListener(type,listener){assert.equal(type,'change');this.listeners.add(listener);return {remove:()=>{this.removed++;this.listeners.delete(listener);}};}
  emit(window){for(const listener of [...this.listeners])listener({window,screen:{width:9999,height:9999,scale:9,fontScale:9}});}
}
class AppStateSource {
  state='active';reads=0;removed=0;listeners=new Set();
  get currentState(){this.reads++;return this.state;}
  addEventListener(type,listener){assert.equal(type,'change');this.listeners.add(listener);return {remove:()=>{this.removed++;this.listeners.delete(listener);}};}
  emit(state){for(const listener of [...this.listeners])listener(state);}
}

test('RN viewport copies logical window events and never reads Dimensions during SDK queries', {timeout:5000}, async t=>{
  const access=accessFor(t),source=new DimensionsSource(),observation=observeReactNativeViewport(access,source);
  t.after(()=>observation.close());
  const initial=await access.get(observation.entity);
  assert.deepEqual(initial.size,{width:100.5,height:200});assert.equal(initial.textScaleFactor,1.25);
  assert.equal(initial.visualViewportScale,null);assert.equal(initial.visualViewportSize,null);assert.equal(initial.safeAreaInsets,null);
  source.metrics.width=999;
  assert.equal((await access.get(observation.entity)).size.width,100.5,'Published values must not retain the source object.');
  const stream=access.withPollInterval(Duration.seconds(60)).watch(observation.entity)[Symbol.asyncIterator]();
  await stream.next();
  source.emit({width:0,height:10,fontScale:2,scale:4});
  assert.deepEqual((await stream.next()).value.size,{width:0,height:10});
  source.emit({width:0,height:10,fontScale:2,scale:4});
  assert.equal((await stream.next()).value.textScaleFactor,2,'Equal event values must remain observable.');
  assert.equal(source.reads,1);
  const late=[...source.listeners][0];observation.close();observation.close();
  await assert.rejects(stream.next(),{code:ErrorCode.EntityRemoved});
  late({window:source.metrics});
  await assert.rejects(access.get(observation.entity),{code:ErrorCode.EntityRemoved});
  assert.equal(source.removed,1);
});

test('RN lifecycle events suspend and resume app sensors without querying currentState', {timeout:5000}, async t=>{
  const access=accessFor(t),source=new AppStateSource(),sessions=[];
  const lifecycle=observeReactNativeSensorActivity(access,source);t.after(()=>lifecycle.close());
  const sensor=access.observers.target(AccelerometerEntity,'rn-app-source');
  access.observers.sensorSource(sensor,{subscribe(session){sessions.push(session);session.publish({value:{x:sessions.length,y:0,z:0}});}});
  const stream=access.withReadTimeout(Duration.milliseconds(100)).watch(sensor)[Symbol.asyncIterator]();
  assert.equal((await stream.next()).value.value.x,1);
  const late=[...source.listeners][0];source.emit('background');await until(()=>sessions[0].signal.aborted);
  let settled=false;const next=stream.next().then(value=>{settled=true;return value;});
  await new Promise(resolve=>setTimeout(resolve,160));assert.equal(settled,false);
  source.emit('active');assert.equal((await next).value.value.x,2);
  assert.equal(source.reads,1);
  lifecycle.close();lifecycle.close();await until(()=>sessions[1].signal.aborted);
  late('active');await new Promise(resolve=>setTimeout(resolve,30));assert.equal(sessions.length,2);
  assert.equal(source.removed,1);await stream.return();
});

test('RN inactive-state policy is explicit and unknown state suspends sensors', {timeout:5000}, async t=>{
  const access=accessFor(t),source=new AppStateSource();source.state='inactive';
  const lifecycle=observeReactNativeSensorActivity(access,source,ReactNativeSensorActivityPolicy.AllowInactive);t.after(()=>lifecycle.close());
  const sessions=[],sensor=access.observers.target(AccelerometerEntity,'desktop-source');
  access.observers.sensorSource(sensor,{subscribe(session){sessions.push(session);session.publish({value:{x:1,y:0,z:0}});}});
  const stream=access.watch(sensor)[Symbol.asyncIterator]();await stream.next();
  source.emit('inactive');await new Promise(resolve=>setTimeout(resolve,30));assert.equal(sessions[0].signal.aborted,false);
  source.emit('unknown');await until(()=>sessions[0].signal.aborted);
  source.emit('active');await stream.next();await stream.return();
});

test('RN viewport preserves independent nullable fields and application-owned failures', {timeout:5000}, async t=>{
  const access=accessFor(t),source=new DimensionsSource(),observation=observeReactNativeViewport(access,source);t.after(()=>observation.close());
  source.emit({get width(){throw Error('Unavailable width');},height:200,fontScale:1.75});
  const partial=await access.get(observation.entity);assert.equal(partial.size,null);assert.equal(partial.textScaleFactor,1.75);
  access.observers.failure(observation.entity,new DeviceReadoutError(ErrorCode.PermissionDenied,'Application policy.'));
  source.emit({width:12,height:24,fontScale:Infinity});
  await assert.rejects(access.get(observation.entity),{code:ErrorCode.PermissionDenied});
  access.observers.failure(observation.entity,null);
  const recovered=await access.get(observation.entity);assert.deepEqual(recovered.size,{width:12,height:24});assert.equal(recovered.textScaleFactor,null);
});

test('RN setup does not overwrite reentrant events with an older initial value', {timeout:5000}, async t=>{
  const access=accessFor(t),source=new DimensionsSource();
  source.get=function(){this.reads++;this.emit({width:300,height:400,fontScale:2});return this.metrics;};
  const observation=observeReactNativeViewport(access,source);t.after(()=>observation.close());
  assert.deepEqual((await access.get(observation.entity)).size,{width:300,height:400});
  const states=new AppStateSource();
  Object.defineProperty(states,'currentState',{get(){states.emit('background');return 'active';}});
  const lifecycle=observeReactNativeSensorActivity(access,states);t.after(()=>lifecycle.close());
  const sensor=access.observers.target(AccelerometerEntity,'reentrant-source');let starts=0;
  access.observers.sensorSource(sensor,{subscribe(session){starts++;session.publish({value:{x:1,y:0,z:0}});}});
  await access.describe(sensor); // Warm up the worker before a short, intentionally inactive get.
  await assert.rejects(access.withReadTimeout(Duration.milliseconds(80)).get(sensor),{code:ErrorCode.ReadTimeout});
  assert.equal(starts,0);
  states.emit('active');assert.equal((await access.get(sensor)).value.x,1);
});

test('RN failed attachment retires only its own viewport and detaches framework listeners', {timeout:5000}, async t=>{
  const access=accessFor(t),firstSource=new DimensionsSource(),first=observeReactNativeViewport(access,firstSource);t.after(()=>first.close());
  const broken=new DimensionsSource();broken.get=()=>{throw Error('Initial metrics unavailable.');};
  assert.throws(()=>observeReactNativeViewport(access,broken),{code:ErrorCode.ReadFailed});
  assert.equal(broken.listeners.size,0);assert.equal(broken.removed,1);
  assert.equal((await access.list(ViewportEntity)).length,1);assert.equal((await access.get(first.entity)).size.width,100.5);
  const replacement=observeReactNativeViewport(access,new DimensionsSource());t.after(()=>replacement.close());
  first.close();assert.equal((await access.list(ViewportEntity)).length,1);
  assert.equal((await access.get(replacement.entity)).size.width,100.5);
  access.close();assert.doesNotThrow(()=>replacement.close());
  const stateAccess=accessFor(t),stateSource=new AppStateSource();
  Object.defineProperty(stateSource,'currentState',{get(){throw Error('Initial state unavailable.');}});
  assert.throws(()=>observeReactNativeSensorActivity(stateAccess,stateSource),{code:ErrorCode.ReadFailed});
  assert.equal(stateSource.listeners.size,0);assert.equal(stateSource.removed,1);
});

test('RN default policy suspends unknown and inactive states and closes safely after SDK disposal', {timeout:5000}, async t=>{
  const access=accessFor(t),source=new AppStateSource();source.state=null;
  const lifecycle=observeReactNativeSensorActivity(access,source);t.after(()=>lifecycle.close());
  const sensor=access.observers.target(AccelerometerEntity,'initially-unknown'),sessions=[];
  access.observers.sensorSource(sensor,{subscribe(session){sessions.push(session);session.publish({value:{x:sessions.length,y:0,z:0}});}});
  await access.describe(sensor);
  const stream=access.withReadTimeout(Duration.milliseconds(80)).watch(sensor)[Symbol.asyncIterator]();let settled=false;
  const first=stream.next().then(value=>{settled=true;return value;});
  await new Promise(resolve=>setTimeout(resolve,130));assert.equal(settled,false);assert.equal(sessions.length,0);
  source.emit('active');assert.equal((await first).value.value.x,1);
  source.emit('inactive');await until(()=>sessions[0].signal.aborted);
  await stream.return();access.close();assert.doesNotThrow(()=>source.emit('active'));assert.equal(source.removed,1);
});
