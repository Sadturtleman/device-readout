import test from 'node:test';
import assert from 'node:assert/strict';
import { createNativeDeviceAccess } from '../dist/native-connection.js';
import { RamEntity, DisplayEntity, AccelerometerEntity, Duration, ErrorCode, PermissionStatus } from '../../core/dist/index.js';

async function until(predicate) {
  const limit=Date.now()+2000;
  while(!predicate()){if(Date.now()>limit)assert.fail('Native request did not arrive.');await new Promise(resolve=>setTimeout(resolve,5));}
}

// External native-module seam: queued replies model the asynchronous native ABI.
class NativeFixture {
  created=0; disposed=0; requests=[]; waiting=null; replies=[];
  async create() {this.created++;return 'native-context';}
  async send(context, json) {
    assert.equal(context,'native-context');
    const request=JSON.parse(json);this.requests.push(request);
    if(request.operation==='get'||request.operation==='watch')this.reply({id:request.id,type:request.operation==='get'?'result':'snapshot',value:{collectedAt:'2026-11-11T00:00:00Z',physicalBytes:'9007199254740993',availableBytes:'0'}});
  }
  reply(value) {const json=JSON.stringify(value);if(this.waiting){this.waiting.resolve(json);this.waiting=null;}else this.replies.push(json);}
  async next() {if(this.replies.length)return this.replies.shift();return new Promise((resolve,reject)=>{assert.equal(this.waiting,null);this.waiting={resolve,reject};});}
  async dispose() {this.disposed++;this.waiting?.reject(Error('Disposed'));this.waiting=null;}
}

test('native permission coordination waits for observed state and retains app target identity', {timeout:4000}, async()=>{
  const native=new NativeFixture();let pending;
  native.send=async(_context,json)=>{
    const request=JSON.parse(json);native.requests.push(request);
    if(request.operation==='permissions.request'){
      pending=request.id;native.reply({id:request.id,type:'permissionRequest'});
    }else if(request.operation==='observer'&&request.value.type==='permission'&&request.value.status===PermissionStatus.Denied){
      native.reply({id:pending,type:'result',value:PermissionStatus.Denied});
    }
  };
  const access=createNativeDeviceAccess(native).withReadTimeout(Duration.milliseconds(25));
  try {
    const screen=access.observers.target(DisplayEntity,'native-1');
    access.observers.permission(screen,PermissionStatus.NotDetermined);
    let requested,settled=false;
    access.observers.onPermissionRequest(({entity})=>{requested=entity;});
    const permission=access.permissions.request(screen).then(value=>{settled=true;return value;});
    await until(()=>requested===screen);
    await new Promise(resolve=>setTimeout(resolve,70));
    assert.equal(settled,false);
    access.observers.permission(screen,PermissionStatus.Denied);
    assert.equal(await permission,PermissionStatus.Denied);
    assert.deepEqual(native.requests.slice(0,3).map(value=>value.operation),['observer','observer','permissions.request']);
    assert.deepEqual(native.requests[2].entity,{kind:'Display',targetId:'native-1',observed:true});
  } finally {access.close();}
});

test('native lifecycle suspension pauses the JS sample deadline and resume preserves the stream', {timeout:4000}, async()=>{
  const native=new NativeFixture();
  native.send=async(_context,json)=>{
    const request=JSON.parse(json);native.requests.push(request);
    if(request.operation==='watch')native.reply({id:request.id,type:'suspended'});
  };
  const access=createNativeDeviceAccess(native).withReadTimeout(Duration.milliseconds(40));
  try {
    const sensor=access.observers.target(AccelerometerEntity,'motion');
    access.observers.sensorActivity(false);
    const iterator=access.watch(sensor)[Symbol.asyncIterator]();let settled=false;
    const first=iterator.next().then(value=>{settled=true;return value;});
    await until(()=>native.requests.some(value=>value.operation==='watch'));
    await new Promise(resolve=>setTimeout(resolve,100));
    assert.equal(settled,false);
    const id=native.requests.find(value=>value.operation==='watch').id;
    access.observers.sensorActivity(true);
    native.reply({id,type:'reading'});
    native.reply({id,type:'snapshot',value:{collectedAt:'2026-11-11T00:00:00Z',value:{x:1,y:0,z:0}}});
    assert.equal((await first).value.value.x,1);
    await iterator.return();
    await until(()=>native.requests.some(value=>value.operation==='cancel'&&value.id===id));
  } finally {access.close();}
});

test('native access is lazy, retains integer data and shares one owner across configured views', async () => {
  const native=new NativeFixture();native.waiting=null;
  const access=createNativeDeviceAccess(native), configured=access.withPollInterval(Duration.seconds(2));
  assert.equal(native.created,0);
  const iterator=configured.watch(RamEntity)[Symbol.asyncIterator]();
  assert.equal(native.created,0);
  assert.equal((await iterator.next()).value.physicalBytes,9007199254740993n);
  await iterator.return();
  assert.equal(native.disposed,0);
  assert.equal((await access.get(RamEntity)).availableBytes,0n);
  assert.equal(native.created,1);
  configured.close();access.close();
  await new Promise(resolve=>setTimeout(resolve,20));
  assert.equal(native.disposed,1);
  assert.ok(native.requests.some(request=>request.operation==='cancel'));
  assert.equal(native.requests.find(request=>request.operation==='watch').settings.pollIntervalMs,2000);
});

test('deadline and final close do not wait for native context creation', async () => {
  const native=new NativeFixture();let release,started;
  const entered=new Promise(resolve=>started=resolve);
  native.create=()=>{native.created++;started();return new Promise(resolve=>release=resolve);};
  const access=createNativeDeviceAccess(native).withReadTimeout(Duration.milliseconds(40));
  const reading=assert.rejects(access.get(RamEntity),{code:ErrorCode.ReadTimeout});
  await entered;await reading;
  access.close();
  assert.equal(native.disposed,0);
  release('native-context');
  await new Promise(resolve=>setTimeout(resolve,20));
  assert.equal(native.disposed,1);
  assert.equal(native.requests.length,0);
});

test('a native typed read failure leaves a sibling stream alive', async () => {
  const native=new NativeFixture();
  const send=native.send.bind(native);
  native.send=async(context,json)=>{
    const request=JSON.parse(json);
    if(request.operation==='get')native.reply({id:request.id,type:'error',error:{code:'PermissionDenied',message:'App policy.'}});
    else await send(context,json);
  };
  const access=createNativeDeviceAccess(native);
  try {
    const watch=access.watch(RamEntity)[Symbol.asyncIterator]();
    await watch.next();
    await assert.rejects(access.get(RamEntity),{code:ErrorCode.PermissionDenied});
    const id=native.requests.find(request=>request.operation==='watch').id;
    native.reply({id,type:'snapshot',value:{collectedAt:'2026-11-11T00:00:01Z',physicalBytes:'12'}});
    assert.equal((await watch.next()).value.physicalBytes,12n);
    await watch.return();
  } finally {access.close();}
});
