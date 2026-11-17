import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { resolve, extname, sep } from 'node:path';
import { chromium } from 'playwright-core';

const root = resolve('.');
const browserTemp = resolve('.tools/browser-temp');
await mkdir(browserTemp, {recursive:true});
process.env.TEMP = browserTemp;
process.env.TMP = browserTemp;
const blockedWorker = `import {serveCollector} from '/packages/core/dist/collector.js';
serveCollector({async read(){const end=performance.now()+2000;while(performance.now()<end){}return {}; }},
{send:m=>postMessage(m),listen:f=>{const listener=e=>f(e.data);addEventListener('message',listener);return()=>removeEventListener('message',listener);}});`;
const html = `<!doctype html><title>DeviceReadout browser contract test</title>
<script type="importmap">{"imports":{"@device-readout/core":"/packages/core/dist/index.js"}}</script>
<script type="module">
import * as core from '@device-readout/core';
import * as web from '/packages/web/dist/index.js';
window.sdkTest={core,...web};
</script>`;

const server = createServer(async (request, response) => {
  try {
    const path = new URL(request.url, 'http://localhost').pathname;
    if (path === '/') {response.setHeader('Content-Type','text/html');response.end(html);return;}
    if (path === '/blocked-worker.js') {response.setHeader('Content-Type','text/javascript');response.end(blockedWorker);return;}
    const file = resolve(root, '.' + decodeURIComponent(path));
    if (!file.startsWith(root + sep)) {response.writeHead(403).end();return;}
    response.setHeader('Content-Type', extname(file) === '.js' ? 'text/javascript' : 'application/octet-stream');
    response.end(await readFile(file));
  } catch {response.writeHead(404).end();}
});
await new Promise(resolve => server.listen(0,'127.0.0.1',resolve));
const url = `http://127.0.0.1:${server.address().port}`;
test.after(() => new Promise(resolve => server.close(resolve)));

async function waitForBrowserValue(page, predicate, timeout=2000) {
  const deadline=Date.now()+timeout;
  do {
    if(await page.evaluate(predicate))return;
    await new Promise(resolve=>setTimeout(resolve,20));
  }while(Date.now()<deadline);
  assert.fail('The browser SDK state did not reach the expected value before the deadline.');
}

for (const [name, executablePath] of [
  ['Chrome', process.env.DEVICEREADOUT_CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe'],
  ['Edge', process.env.DEVICEREADOUT_EDGE || 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe']
]) {
  test(`${name}: generic sensor permission loss fails paused demand without clearing application policy`, {timeout:30000}, async t=>{
    const browser=await chromium.launch({executablePath,headless:true});t.after(()=>browser.close());
    const page=await browser.newPage();await page.goto(url);await page.waitForFunction(()=>!!window.sdkTest);
    const result=await page.evaluate(async()=>{
      const {createWebDeviceAccess,observeWebGenericSensors,core}=window.sdkTest;
      const access=createWebDeviceAccess().withReadTimeout(core.Duration.milliseconds(150)),instances=[],source=new EventTarget();
      for(const kind of ['Accelerometer','Gyroscope'])source[kind]=class extends EventTarget{
        constructor(){super();this.kind=kind;this.stops=0;instances.push(this);Object.assign(this,{x:1,y:2,z:3});}
        start(){}
        stop(){this.stops++;}
        sample(){this.dispatchEvent(new Event('reading'));}
      };
      const accelPermission=Object.assign(new EventTarget(),{state:'granted'}),gyroPermission=Object.assign(new EventTarget(),{state:'granted'});
      const observation=observeWebGenericSensors(access,source,{accelerometer:accelPermission,gyroscope:gyroPermission});
      const [accel]=(await access.sensors.list(core.AccelerometerEntity)),[gyro]=(await access.sensors.list(core.GyroscopeEntity));
      const streams=[accel,gyro].map(target=>access.watch(target)[Symbol.asyncIterator]()),first=streams.map(stream=>stream.next());
      const wait=async predicate=>{const end=performance.now()+1500;while(!predicate()){if(performance.now()>end)throw Error('Paused sensor condition did not settle');await new Promise(r=>setTimeout(r,5));}};
      await wait(()=>instances.length===2);instances.forEach(sensor=>sensor.sample());await Promise.all(first);
      access.observers.sensorActivity(false);await wait(()=>instances.every(sensor=>sensor.stops===1));
      let firstError=null,siblingSettled=false;
      const ended=streams[0].next().then(()=>{firstError='unexpected';},error=>{firstError=error.code;});
      const sibling=streams[1].next().then(result=>{siblingSettled=true;return result;});
      accelPermission.state='denied';accelPermission.dispatchEvent(new Event('change'));await wait(()=>firstError!==null);await ended;
      const pausedRead=await access.get(accel).then(()=> 'unexpected',error=>error.code),heldSibling=!siblingSettled;
      access.observers.failure(accel,new core.DeviceReadoutError(core.ErrorCode.ReadFailed,'App still blocks this target'));
      accelPermission.state='granted';accelPermission.dispatchEvent(new Event('change'));
      const appFailure=await access.get(accel).then(()=> 'unexpected',error=>error.code);
      access.observers.failure(accel,null);access.observers.sensorActivity(true);
      const recovered=access.get(accel);await wait(()=>instances.length===4);
      for(const sensor of instances.slice(2)){sensor.x=7;sensor.sample();}
      const values=[(await sibling).value.value,(await recovered).value];
      await streams[1].return();observation.close();access.close();
      return {firstError,pausedRead,heldSibling,appFailure,values,stops:instances.map(sensor=>sensor.stops)};
    });
    assert.deepEqual(result,{firstError:'PermissionDenied',pausedRead:'PermissionDenied',heldSibling:true,appFailure:'ReadFailed',
      values:[{x:7,y:2,z:3},{x:7,y:2,z:3}],stops:[1,1,1,1]});
  });
  test(`${name}: generic sensor deadlines and native failures release only their own observation`, {timeout:30000}, async t=>{
    const browser=await chromium.launch({executablePath,headless:true});t.after(()=>browser.close());
    const page=await browser.newPage();await page.goto(url);await page.waitForFunction(()=>!!window.sdkTest);
    const uncaught=[];page.on('pageerror',error=>uncaught.push(error.message));
    const result=await page.evaluate(async()=>{
      const {createWebDeviceAccess,observeWebGenericSensors,core}=window.sdkTest;
      const access=createWebDeviceAccess(),instances=[];
      class Accelerometer extends EventTarget {
        constructor(){super();this.stops=0;this.callbacks=[];instances.push(this);Object.assign(this,{x:1,y:2,z:3});}
        addEventListener(type,listener,...rest){this.callbacks.push([type,listener]);super.addEventListener(type,listener,...rest);}
        start(){}
        stop(){this.stops++;if(instances[2]===this)throw Error('Host cleanup failed');}
      }
      const permission=Object.assign(new EventTarget(),{state:'granted'}),source=Object.assign(new EventTarget(),{Accelerometer});
      const observation=observeWebGenericSensors(access,source,{accelerometer:permission});
      const [target]=await access.sensors.list(core.AccelerometerEntity);
      const wait=async predicate=>{const end=performance.now()+1500;while(!predicate()){if(performance.now()>end)throw Error('Sensor state timed out');await new Promise(r=>setTimeout(r,5));}};
      const stream=access.watch(target)[Symbol.asyncIterator](),first=stream.next();await wait(()=>instances.length===1);
      instances[0].dispatchEvent(new Event('reading'));await first;
      const timeout=await access.withReadTimeout(core.Duration.milliseconds(70)).get(target).then(()=> 'unexpected',error=>error.code);
      await wait(()=>instances[1]?.stops===1);const siblingStops=instances[0].stops;
      const next=stream.next();instances[0].dispatchEvent(new Event('reading'));const siblingValue=(await next).value.value;
      const failed=stream.next().then(()=> 'unexpected',error=>error.code);
      instances[0].dispatchEvent(Object.assign(new Event('error'),{error:new DOMException('Device unavailable','NotReadableError')}));
      const nativeError=await failed;
      const getter=access.get(target).then(()=> 'unexpected',error=>error.code);await wait(()=>instances.length===3);
      Object.defineProperty(instances[2],'x',{get(){throw Error('Native read failed');}});instances[2].dispatchEvent(new Event('reading'));
      const getterError=await getter;
      const ending=access.get(target).then(()=> 'unexpected',error=>error.code);await wait(()=>instances.length===4);
      access.close();const closed=await ending;observation.close();
      for(const sensor of instances)for(const [type,callback]of sensor.callbacks)callback(new Event(type));
      return {timeout,siblingStops,siblingValue,nativeError,getterError,closed,stops:instances.map(sensor=>sensor.stops)};
    });
    assert.deepEqual(result,{timeout:'ReadTimeout',siblingStops:0,siblingValue:{x:1,y:2,z:3},nativeError:'ReadFailed',getterError:'ReadFailed',closed:'EntityRemoved',stops:[1,1,1,1]});
    assert.deepEqual(uncaught,[]);
  });
  for(const paused of [false,true])test(`${name}: native generic sensor permission revocation ends streams and allows fresh recovery${paused?' while inactive':''}`, {timeout:30000}, async t=>{
    const browser=await chromium.launch({executablePath,headless:true});t.after(()=>browser.close());
    const context=await browser.newContext(),page=await context.newPage();await page.goto(url);await page.waitForFunction(()=>!!window.sdkTest);
    const cdp=await context.newCDPSession(page),{targetInfo}=await cdp.send('Target.getTargetInfo');
    const types=['accelerometer','gyroscope'];
    for(const type of types){await cdp.send('Emulation.setSensorOverrideEnabled',{type,enabled:true});
      await cdp.send('Emulation.setSensorOverrideReadings',{type,reading:{xyz:{x:1,y:2,z:3}}});}
    await page.evaluate(async()=>{
      const {createWebDeviceAccess,observeWebGenericSensors,core}=window.sdkTest;
      const permissions={};for(const name of ['accelerometer','gyroscope','magnetometer'])permissions[name]=await navigator.permissions.query({name});
      const access=createWebDeviceAccess(),observation=observeWebGenericSensors(access,window,permissions);
      navigator.permissions.query=()=>{throw Error('SDK must not query application permissions');};
      const state={access,observation,permissions,values:{},errors:{},targets:{},tasks:[]};window.genericPermission=state;
      for(const kind of [core.AccelerometerEntity,core.GyroscopeEntity]){
        const target=(await access.sensors.list(kind))[0];state.targets[kind.kind]=target;
        state.tasks.push((async()=>{try{for await(const snapshot of access.watch(target))state.values[kind.kind]=snapshot.value;}
          catch(error){state.errors[kind.kind]=error.code;}})());
      }
    });
    await waitForBrowserValue(page,()=>Object.keys(window.genericPermission.values).length===2);
    if(paused){
      await page.evaluate(()=>window.genericPermission.access.observers.sensorActivity(false));
      const limit=Date.now()+2000;let frequencies;
      do{frequencies=await Promise.all(types.map(async type=>(await cdp.send('Emulation.getOverriddenSensorInformation',{type})).requestedSamplingFrequency));
        if(frequencies.every(value=>value===0))break;await new Promise(r=>setTimeout(r,20));}while(Date.now()<limit);
      assert.deepEqual(frequencies,[0,0]);
    }
    await cdp.send('Browser.setPermission',{permission:{name:'accelerometer'},setting:'denied',origin:url,browserContextId:targetInfo.browserContextId});
    await waitForBrowserValue(page,()=>Object.keys(window.genericPermission.errors).length===2);
    const denied=await page.evaluate(async()=>{
      const s=window.genericPermission;await Promise.all(s.tasks);
      return {errors:s.errors,statuses:await Promise.all(Object.values(s.targets).map(target=>s.access.permissions.check(target))),
        reads:await Promise.all(Object.values(s.targets).map(target=>s.access.get(target).then(()=> 'unexpected',error=>error.code)))};
    });
    assert.deepEqual(denied,{errors:{Accelerometer:'PermissionDenied',Gyroscope:'PermissionDenied'},statuses:['Denied','Denied'],reads:['PermissionDenied','PermissionDenied']});
    for(const type of types)await cdp.send('Emulation.setSensorOverrideReadings',{type,reading:{xyz:{x:4,y:5,z:6}}});
    await cdp.send('Browser.setPermission',{permission:{name:'accelerometer'},setting:'granted',origin:url,browserContextId:targetInfo.browserContextId});
    await waitForBrowserValue(page,async()=>{const s=window.genericPermission;return(await Promise.all(Object.values(s.targets).map(target=>s.access.permissions.check(target)))).every(status=>status==='Granted');});
    const recovered=await page.evaluate(async()=>{
      const s=window.genericPermission;s.access.observers.sensorActivity(true);
      const values=await Promise.all(Object.values(s.targets).map(async target=>(await s.access.get(target)).value));
      s.observation.close();s.access.close();return values;
    });
    for(const value of recovered)for(const [key,expected]of Object.entries({x:4,y:5,z:6}))assert.ok(Math.abs(value[key]-expected)<0.002);
    const end=Date.now()+2000;let stopped;
    do{stopped=await Promise.all(types.map(async type=>(await cdp.send('Emulation.getOverriddenSensorInformation',{type})).requestedSamplingFrequency));
      if(stopped.every(value=>value===0))break;await new Promise(r=>setTimeout(r,20));}while(Date.now()<end);
    assert.deepEqual(stopped,[0,0]);
    await mkdir('.tools/evidence',{recursive:true});
    await writeFile(`.tools/evidence/generic-sensor-permission-${name.toLowerCase()}${paused?'-paused':''}.json`,JSON.stringify({browser:await browser.version(),paused,denied,recovered,stopped},null,2));
  });
  test(`${name}: generic sensor reentrant permission loss prevents native start and cleans failed construction`, {timeout:30000}, async t=>{
    const browser=await chromium.launch({executablePath,headless:true});t.after(()=>browser.close());
    const page=await browser.newPage();await page.goto(url);await page.waitForFunction(()=>!!window.sdkTest);
    const result=await page.evaluate(async()=>{
      const {createWebDeviceAccess,observeWebGenericSensors,core}=window.sdkTest;
      const access=createWebDeviceAccess().withReadTimeout(core.Duration.milliseconds(100)),instances=[];
      const permission=Object.assign(new EventTarget(),{state:'granted'});
      class Accelerometer extends EventTarget {
        constructor(){super();this.starts=0;this.stops=0;instances.push(this);
          if(instances.length===1){permission.state='denied';permission.dispatchEvent(new Event('change'));}}
        start(){this.starts++;throw new DOMException('Policy blocked access','SecurityError');}
        stop(){this.stops++;}
      }
      const observation=observeWebGenericSensors(access,Object.assign(new EventTarget(),{Accelerometer}),{accelerometer:permission});
      const [target]=await access.sensors.list(core.AccelerometerEntity);
      const errors=[await access.get(target).then(()=> 'unexpected',error=>error.code)];
      permission.state='granted';permission.dispatchEvent(new Event('change'));
      errors.push(await access.get(target).then(()=> 'unexpected',error=>error.code));
      access.observers.failure(target,new core.DeviceReadoutError(core.ErrorCode.ReadFailed,'App-owned failure'));
      permission.state='denied';permission.dispatchEvent(new Event('change'));permission.state='granted';permission.dispatchEvent(new Event('change'));
      errors.push(await access.get(target).then(()=> 'unexpected',error=>error.code));
      observation.close();access.close();return {errors,starts:instances.map(sensor=>sensor.starts),stops:instances.map(sensor=>sensor.stops)};
    });
    assert.deepEqual(result,{errors:['PermissionDenied','PermissionDenied','ReadFailed'],starts:[0,1],stops:[1,1]});
  });
  for(const experimental of [false,true])test(`${name}: native generic sensors preserve samples and release browser resources${experimental?' with experimental classes':''}`, {timeout:30000}, async t=>{
    const browser=await chromium.launch({executablePath,headless:true,args:experimental?['--enable-features=GenericSensorExtraClasses']:[]});t.after(()=>browser.close());
    const context=await browser.newContext(),page=await context.newPage();await page.goto(url);await page.waitForFunction(()=>!!window.sdkTest);
    const cdp=await context.newCDPSession(page);
    const families=[['Accelerometer','Accelerometer','accelerometer',{xyz:{x:1.2,y:-2.5,z:9.8}}],
      ['LinearAccelerationSensor','LinearAcceleration','linear-acceleration',{xyz:{x:-1,y:0,z:0.5}}],
      ['GravitySensor','Gravity','gravity',{xyz:{x:0,y:0,z:9.8}}],
      ['Gyroscope','Gyroscope','gyroscope',{xyz:{x:0,y:1.5,z:-3}}],
      ['Magnetometer','Magnetometer','magnetometer',{xyz:{x:12,y:-34,z:56}}],
      ['RelativeOrientationSensor','RelativeOrientation','relative-orientation',{quaternion:{x:0,y:0,z:0.6,w:0.8}}],
      ['AbsoluteOrientationSensor','AbsoluteOrientation','absolute-orientation',{quaternion:{x:0.5,y:0.5,z:0.5,w:0.5}}],
      ['AmbientLightSensor','Illuminance','ambient-light',{single:{value:200}}]];
    const available=await page.evaluate(families=>families.filter(([constructor])=>typeof window[constructor]==='function').map(([,kind])=>kind),families);
    for(const required of ['Accelerometer','LinearAcceleration','Gyroscope','RelativeOrientation','AbsoluteOrientation'])assert.ok(available.includes(required),required);
    if(experimental)assert.equal(available.length,8);
    const selected=families.filter(([,kind])=>available.includes(kind));
    for(const [,,type,reading]of selected){
      await cdp.send('Emulation.setSensorOverrideEnabled',{type,enabled:true,metadata:{minimumFrequency:1,maximumFrequency:120}});
      await cdp.send('Emulation.setSensorOverrideReadings',{type,reading});
    }
    await page.evaluate(async kinds=>{
      const {createWebDeviceAccess,observeWebGenericSensors,core}=window.sdkTest;
      const permissions={};for(const [key,name]of [['accelerometer','accelerometer'],['gyroscope','gyroscope'],['magnetometer','magnetometer'],
        ...(kinds.includes('Illuminance')?[['ambientLight','ambient-light-sensor']]:[])])permissions[key]=await navigator.permissions.query({name});
      const access=createWebDeviceAccess(),observation=observeWebGenericSensors(access,window,permissions),targets={};
      for(const kind of kinds){targets[kind]=(await access.sensors.list(core[`${kind}Entity`]))[0];await access.describe(targets[kind]);}
      window.genericNative={access,observation,targets,values:{},errors:{},counts:{},tasks:[]};
    },available);
    const frequencies=()=>Promise.all(selected.map(async([,,type])=>(await cdp.send('Emulation.getOverriddenSensorInformation',{type})).requestedSamplingFrequency));
    assert.deepEqual(await frequencies(),Array(selected.length).fill(0));
    await page.evaluate(()=>{
      const s=window.genericNative,{core}=window.sdkTest;s.control=new AbortController();
      s.tasks=Object.entries(s.targets).map(([kind,target])=>(async()=>{
        try{for await(const snapshot of s.access.withSensorSamplingRate(core.hertz(17)).watch(target,{signal:s.control.signal})){
          s.values[kind]=snapshot.value;s.counts[kind]=(s.counts[kind]||0)+1;
        }}catch(error){if(error.name!=='AbortError')s.errors[kind]=error.code;}
      })());
    });
    await waitForBrowserValue(page,()=>Object.keys(window.genericNative.values).length+Object.keys(window.genericNative.errors).length===Object.keys(window.genericNative.targets).length);
    assert.deepEqual(await page.evaluate(()=>window.genericNative.errors),{});
    const values=await page.evaluate(()=>window.genericNative.values),activeFrequencies=await frequencies();
    for(const [,kind,,reading]of selected){
      const expected=reading.xyz??reading.quaternion??reading.single.value,actual=values[kind];
      if(typeof expected==='number')assert.equal(actual,expected);
      else for(const key of Object.keys(expected))assert.ok(Math.abs(actual[key]-expected[key])<0.002,`${kind}.${key}: ${actual[key]}`);
    }
    for(const [index,[,kind]]of selected.entries()){
      // Browser limits apply after our 17 Hz request; experimental light/magnetic sensors are capped.
      if(kind==='Illuminance'||kind==='Magnetometer')assert.ok(activeFrequencies[index]>0&&activeFrequencies[index]<=17);
      else assert.equal(activeFrequencies[index],17);
    }
    await page.evaluate(()=>window.genericNative.access.observers.sensorActivity(false));
    const waitStopped=async()=>{const end=Date.now()+2000;let result;do{result=await frequencies();if(result.every(value=>value===0))return result;await new Promise(r=>setTimeout(r,20));}while(Date.now()<end);assert.fail(JSON.stringify(result));};
    const paused=await waitStopped();
    await page.evaluate(()=>{const s=window.genericNative;s.counts={};s.access.observers.sensorActivity(true);});
    await waitForBrowserValue(page,()=>Object.keys(window.genericNative.counts).length===Object.keys(window.genericNative.targets).length);
    const errors=await page.evaluate(async()=>{const s=window.genericNative;s.control.abort();await Promise.all(s.tasks);s.observation.close();s.access.close();return s.errors;});
    assert.deepEqual(errors,{});const stopped=await waitStopped();
    await mkdir('.tools/evidence',{recursive:true});
    await writeFile(`.tools/evidence/generic-sensors-${name.toLowerCase()}-${experimental?'experimental':'default'}.json`,JSON.stringify({browser:await browser.version(),experimental,available,values,activeFrequencies,paused,stopped,errors},null,2));
  });
  test(`${name}: generic sensor families retain native units and frames with nullable grouped values`, {timeout:30000}, async t=>{
    const browser=await chromium.launch({executablePath,headless:true});t.after(()=>browser.close());
    const page=await browser.newPage();await page.goto(url);await page.waitForFunction(()=>!!window.sdkTest);
    const result=await page.evaluate(async()=>{
      const {createWebDeviceAccess,observeWebGenericSensors,core}=window.sdkTest;
      const access=createWebDeviceAccess(),instances={},source=new EventTarget();
      const families=[['Accelerometer','Accelerometer'],['LinearAccelerationSensor','LinearAcceleration'],['GravitySensor','Gravity'],
        ['Gyroscope','Gyroscope'],['Magnetometer','Magnetometer'],['RelativeOrientationSensor','RelativeOrientation'],
        ['AbsoluteOrientationSensor','AbsoluteOrientation'],['AmbientLightSensor','Illuminance']];
      for(const [constructor,kind]of families)source[constructor]=class extends EventTarget {
        constructor(options){super();this.options=options;this.timestamp=123;this.stops=0;instances[kind]=this;}
        start(){}
        stop(){this.stops++;}
        sample(fields){Object.assign(this,fields);this.dispatchEvent(new Event('reading'));}
      };
      const permissions=Object.fromEntries(['accelerometer','gyroscope','magnetometer','ambientLight'].map(key=>[key,Object.assign(new EventTarget(),{state:'granted'})]));
      const observation=observeWebGenericSensors(access,source,permissions),streams={};
      const first=await Promise.all(families.map(async([,kind])=>{
        const [target]=await access.sensors.list(core[`${kind}Entity`]);
        const stream=access.watch(target)[Symbol.asyncIterator]();streams[kind]=stream;return {kind,next:stream.next()};
      }));
      const end=performance.now()+1500;while(Object.keys(instances).length!==8){if(performance.now()>end)throw Error('Missing sensor families');await new Promise(r=>setTimeout(r,5));}
      for(const [kind,sensor]of Object.entries(instances))sensor.sample(kind==='Illuminance'?{illuminance:0}:kind.endsWith('Orientation')?{quaternion:[0,0,0.6,0.8]}:{x:0.25,y:-0.5,z:3});
      const snapshots=Object.fromEntries(await Promise.all(first.map(async({kind,next})=>[kind,(await next).value])));
      const invalid=Object.entries(streams).map(([kind,stream])=>({kind,next:stream.next()}));
      for(const [kind,sensor]of Object.entries(instances))sensor.sample(kind==='Illuminance'?{illuminance:Infinity}:kind.endsWith('Orientation')?{quaternion:[0,NaN,0,1]}:{x:0,y:null,z:3});
      const nullValues=await Promise.all(invalid.map(async({next})=>(await next).value.value));
      await Promise.all(Object.values(streams).map(stream=>stream.return()));observation.close();access.close();
      return {values:Object.fromEntries(Object.entries(snapshots).map(([kind,snapshot])=>[kind,snapshot.value])),
        options:Object.fromEntries(Object.entries(instances).map(([kind,sensor])=>[kind,sensor.options])),
        recent:Object.values(snapshots).every(snapshot=>snapshot.collectedAt.epochMilliseconds>Date.now()-10000),nullValues};
    });
    const {RelativeOrientation,AbsoluteOrientation,...otherValues}=result.values;
    assert.deepEqual(otherValues,{Accelerometer:{x:0.25,y:-0.5,z:3},LinearAcceleration:{x:0.25,y:-0.5,z:3},Gravity:{x:0.25,y:-0.5,z:3},
      Gyroscope:{x:0.25,y:-0.5,z:3},Magnetometer:{x:0.25,y:-0.5,z:3},Illuminance:0});
    for(const rotation of [RelativeOrientation,AbsoluteOrientation]) {
      assert.deepEqual(Object.keys(rotation).sort(),['w','x','y','z']);
      for(const [axis,value]of Object.entries({x:0,y:0,z:0.6,w:0.8}))assert.ok(Math.abs(rotation[axis]-value)<=1e-15,axis);
      assert.ok(Math.abs(Math.hypot(rotation.x,rotation.y,rotation.z,rotation.w)-1)<=1e-15);
    }
    for(const [kind,options]of Object.entries(result.options))assert.deepEqual(options,kind==='Illuminance'?{}:{referenceFrame:'device'});
    assert.deepEqual(result.nullValues,Array(8).fill(null));assert.equal(result.recent,true);
  });
  test(`${name}: generic sensor construction is lazy, permission gated and uses independent sampling settings`, {timeout:30000}, async t=>{
    const browser=await chromium.launch({executablePath,headless:true});t.after(()=>browser.close());
    const page=await browser.newPage();await page.goto(url);await page.waitForFunction(()=>!!window.sdkTest);
    const result=await page.evaluate(async()=>{
      const {createWebDeviceAccess,observeWebGenericSensors,core}=window.sdkTest;
      const access=createWebDeviceAccess(),instances=[];
      class Accelerometer extends EventTarget {
        constructor(options){super();this.options=options;this.stops=0;instances.push(this);}
        start(){this.started=true;}
        stop(){this.stops++;}
        sample(x,y,z){Object.assign(this,{x,y,z});this.dispatchEvent(new Event('reading'));}
      }
      const permission=Object.assign(new EventTarget(),{state:'prompt'});
      const source=Object.assign(new EventTarget(),{Accelerometer});
      const observation=observeWebGenericSensors(access,source,{accelerometer:permission});
      const [target]=await access.sensors.list(core.AccelerometerEntity);
      const before=instances.length;
      const deniedMetadata=await access.describe(target).then(()=> 'unexpected',error=>error.code);
      const initialPermission=await access.permissions.check(target);
      const denied=await access.get(target).then(()=> 'unexpected',error=>error.code);
      const deniedInstances=instances.length;
      permission.state='granted';permission.dispatchEvent(new Event('change'));
      const allowed=await access.permissions.check(target);
      const description=await access.describe(target);
      const once=access.withSensorSamplingRate(core.hertz(50)).get(target);
      const watch=access.withSensorSamplingRate(core.hertz(17)).watch(target)[Symbol.asyncIterator]();
      const first=watch.next();
      const wait=async predicate=>{const end=performance.now()+1500;while(!predicate()){if(performance.now()>end)throw Error('Sensor state timed out');await new Promise(r=>setTimeout(r,5));}};
      await wait(()=>instances.length===2);
      for(const sensor of instances)sensor.sample(0,-2,9.5);
      const values=[(await once).value,(await first).value.value];
      const duplicate=watch.next();instances[1].sample(0,-2,9.5);values.push((await duplicate).value.value);
      await watch.return();await wait(()=>instances.every(sensor=>sensor.stops===1));
      observation.close();const removed=await access.get(target).then(()=> 'unexpected',error=>error.code);
      access.close();
      return {before,deniedInstances,initialPermission,allowed,denied,deniedMetadata,kind:description.kind,vendor:description.vendor,
        values,options:instances.map(sensor=>sensor.options),stops:instances.map(sensor=>sensor.stops),removed};
    });
    assert.deepEqual(result,{before:0,deniedInstances:0,initialPermission:'NotDetermined',allowed:'Granted',denied:'PermissionDenied',deniedMetadata:'PermissionDenied',
      kind:'Accelerometer',vendor:null,values:Array(3).fill({x:0,y:-2,z:9.5}),
      options:[{referenceFrame:'device'},{referenceFrame:'device',frequency:17}],stops:[1,1],removed:'EntityRemoved'});
  });
  test(`${name}: orientation fallback follows app activity and reports native source failures`, {timeout:30000}, async t=>{
    const browser=await chromium.launch({executablePath,headless:true});t.after(()=>browser.close());
    const page=await browser.newPage();await page.goto(url);await page.waitForFunction(()=>!!window.sdkTest);
    const uncaught=[];page.on('pageerror',error=>uncaught.push(error.message));
    const result=await page.evaluate(async()=>{
      const {createWebDeviceAccess,observeWebOrientation,observeWebSensorActivity,core}=window.sdkTest;
      const sdk=createWebDeviceAccess(),source=Object.assign(new EventTarget(),{ondeviceorientation:null});
      const documentSource=Object.assign(new EventTarget(),{visibilityState:'visible',defaultView:source});
      const listeners=new Set(),add=source.addEventListener.bind(source),remove=source.removeEventListener.bind(source);
      source.addEventListener=(type,listener,...rest)=>{if(type==='deviceorientation')listeners.add(listener);add(type,listener,...rest);};
      source.removeEventListener=(type,listener,...rest)=>{listeners.delete(listener);remove(type,listener,...rest);};
      const activity=observeWebSensorActivity(sdk,documentSource),observation=observeWebOrientation(sdk,source);
      async function wait(count){const end=performance.now()+1500;while(listeners.size!==count){if(performance.now()>end)throw Error('Listener count '+listeners.size);await new Promise(r=>setTimeout(r,5));}}
      const targets=await Promise.all([core.RelativeOrientationEntity,core.AbsoluteOrientationEntity].map(async kind=>(await sdk.sensors.list(kind))[0]));
      const streams=targets.map(target=>sdk.withReadTimeout(core.Duration.milliseconds(100)).watch(target)[Symbol.asyncIterator]());
      const first=streams.map(stream=>stream.next());await wait(2);
      source.dispatchEvent(new DeviceOrientationEvent('deviceorientation',{alpha:0,beta:0,gamma:0,absolute:false}));
      const relativeValues=(await Promise.all(first)).map(result=>result.value.value);
      const oldListeners=[...listeners];source.dispatchEvent(new PageTransitionEvent('pagehide',{persisted:true}));await wait(0);
      const pending=streams.map(stream=>stream.next());let settled=0;for(const promise of pending)promise.then(()=>settled++,()=>settled++);
      for(const listener of oldListeners)listener(new DeviceOrientationEvent('deviceorientation',{alpha:90,beta:0,gamma:0,absolute:false}));
      await new Promise(r=>setTimeout(r,160));const stayedPaused=settled===0;
      source.dispatchEvent(new PageTransitionEvent('pageshow',{persisted:true}));await wait(2);
      source.dispatchEvent(new DeviceOrientationEvent('deviceorientation',{alpha:0,beta:0,gamma:0,absolute:true}));
      const absoluteValues=(await Promise.all(pending)).map(result=>result.value.value);
      const nonfinite=streams.map(stream=>stream.next());
      source.dispatchEvent(Object.assign(new Event('deviceorientation'),{alpha:0,beta:NaN,gamma:0,absolute:false}));
      const nullValues=(await Promise.all(nonfinite)).map(result=>result.value.value);
      const failures=streams.map(stream=>stream.next().then(()=> 'unexpected',error=>error.code));
      const broken=new Event('deviceorientation');Object.defineProperty(broken,'absolute',{get(){throw Error('Native getter failed');}});
      source.dispatchEvent(broken);const errors=await Promise.all(failures);await wait(0);
      const final=sdk.get(targets[0]).then(()=> 'unexpected',error=>error.code);await wait(1);
      source.dispatchEvent(new PageTransitionEvent('pagehide',{persisted:false}));const removed=await final;await wait(0);
      observation.close();activity.close();
      let unsupported;try{observeWebOrientation(sdk,new EventTarget());}catch(error){unsupported=error.code;}
      const onlyAbsolute=Object.assign(new EventTarget(),{ondeviceorientationabsolute:null});
      const absoluteObserver=observeWebOrientation(sdk,onlyAbsolute);
      const onlyAbsoluteCount=(await sdk.sensors.list(core.AbsoluteOrientationEntity)).length;
      const relativeCount=(await sdk.sensors.list(core.RelativeOrientationEntity)).length;
      absoluteObserver.close();sdk.close();
      return {relativeValues,absoluteValues,nullValues,stayedPaused,errors,removed,unsupported,onlyAbsoluteCount,relativeCount,listeners:listeners.size};
    });
    const identity={x:0,y:0,z:0,w:1};
    assert.deepEqual(result,{relativeValues:[identity,null],absoluteValues:[null,identity],nullValues:[null,null],stayedPaused:true,
      errors:['ReadFailed','ReadFailed'],removed:'EntityRemoved',unsupported:'UnsupportedEntity',onlyAbsoluteCount:1,relativeCount:0,listeners:0});
    assert.deepEqual(uncaught,[]);
  });
  test(`${name}: app-observed native sensor revocation fails orientation streams and permits fresh reads`, {timeout:30000}, async t=>{
    const browser=await chromium.launch({executablePath,headless:true});t.after(()=>browser.close());
    const context=await browser.newContext(),page=await context.newPage();await page.goto(url);await page.waitForFunction(()=>!!window.sdkTest);
    const cdp=await context.newCDPSession(page),{targetInfo}=await cdp.send('Target.getTargetInfo');
    for(const type of ['relative-orientation','absolute-orientation']){
      await cdp.send('Emulation.setSensorOverrideEnabled',{type,enabled:true});
      await cdp.send('Emulation.setSensorOverrideReadings',{type,reading:{quaternion:{x:0,y:0,z:0,w:1}}});
    }
    await page.evaluate(async()=>{
      const {createWebDeviceAccess,observeWebOrientation,core}=window.sdkTest;
      const sdk=createWebDeviceAccess(),observation=observeWebOrientation(sdk,window),control=new AbortController();
      const permissions=Object.fromEntries(await Promise.all(['accelerometer','gyroscope','magnetometer'].map(async name=>[name,await navigator.permissions.query({name})])));
      const apply=()=>{
        for(const [kind,names]of [[core.RelativeOrientationEntity,['accelerometer','gyroscope']],[core.AbsoluteOrientationEntity,['accelerometer','gyroscope','magnetometer']]]){
          const granted=names.every(name=>permissions[name].state==='granted');
          sdk.observers.permission(kind,granted?core.PermissionStatus.Granted:core.PermissionStatus.Denied);
          sdk.observers.failure(kind,granted?null:new core.DeviceReadoutError(core.ErrorCode.PermissionDenied,'App observed revoked orientation permission.'));
        }
      };
      for(const permission of Object.values(permissions))permission.addEventListener('change',apply);apply();
      const state={sdk,observation,control,permissions,apply,values:{},errors:{},targets:{}};window.orientationPermission=state;
      state.tasks=await Promise.all([core.RelativeOrientationEntity,core.AbsoluteOrientationEntity].map(async kind=>{
        const target=(await sdk.sensors.list(kind))[0];state.targets[kind.kind]=target;
        return {done:(async()=>{try{for await(const snapshot of sdk.watch(target,{signal:control.signal}))state.values[kind.kind]=snapshot.value;}
          catch(error){if(error.name!=='AbortError')state.errors[kind.kind]=error.code;}})()};
      }));
    });
    await waitForBrowserValue(page,()=>Object.values(window.orientationPermission.values).filter(Boolean).length===2);
    await cdp.send('Browser.setPermission',{permission:{name:'magnetometer'},setting:'denied',origin:url,browserContextId:targetInfo.browserContextId});
    // Chromium exposes these three descriptors through one site sensor permission setting.
    await waitForBrowserValue(page,()=>Object.values(window.orientationPermission.errors).filter(code=>code==='PermissionDenied').length===2);
    const denied=await page.evaluate(async()=>{
      const s=window.orientationPermission;
      return {errors:await Promise.all(Object.values(s.targets).map(async target=>{try{await s.sdk.get(target);return 'unexpected';}catch(error){return error.code;}})),
        states:Object.fromEntries(Object.entries(s.permissions).map(([name,permission])=>[name,permission.state]))};
    });
    assert.deepEqual(denied,{errors:['PermissionDenied','PermissionDenied'],states:{accelerometer:'denied',gyroscope:'denied',magnetometer:'denied'}});
    for(const type of ['relative-orientation','absolute-orientation'])await cdp.send('Emulation.setSensorOverrideReadings',{type,reading:{quaternion:{x:0,y:0,z:Math.SQRT1_2,w:Math.SQRT1_2}}});
    await cdp.send('Browser.setPermission',{permission:{name:'magnetometer'},setting:'granted',origin:url,browserContextId:targetInfo.browserContextId});
    await waitForBrowserValue(page,async()=>{
      const s=window.orientationPermission;
      return (await Promise.all(Object.values(s.targets).map(target=>s.sdk.permissions.check(target)))).every(status=>status==='Granted');
    });
    const recovered=await page.evaluate(async()=>{
      const s=window.orientationPermission,values=await Promise.all(Object.values(s.targets).map(async target=>(await s.sdk.get(target)).value));
      s.control.abort();await Promise.all(s.tasks.map(task=>task.done));for(const permission of Object.values(s.permissions))permission.removeEventListener('change',s.apply);s.observation.close();s.sdk.close();
      return {values,errors:s.errors};
    });
    for(const value of recovered.values)assert.ok(Math.abs(value.z-Math.SQRT1_2)<0.002);
    assert.deepEqual(recovered.errors,{RelativeOrientation:'PermissionDenied',AbsoluteOrientation:'PermissionDenied'});
    await mkdir('.tools/evidence',{recursive:true});
    await writeFile(`.tools/evidence/orientation-permission-${name.toLowerCase()}.json`,JSON.stringify({browser:await browser.version(),denied,recovered},null,2));
  });
  test(`${name}: native virtual orientation sensors retain device-to-reference quaternions and release resources`, {timeout:30000}, async t=>{
    const browser=await chromium.launch({executablePath,headless:true});t.after(()=>browser.close());
    const context=await browser.newContext(),page=await context.newPage();await page.goto(url);await page.waitForFunction(()=>!!window.sdkTest);
    const cdp=await context.newCDPSession(page);
    const sensors=[['relative-orientation',{x:0,y:0,z:Math.SQRT1_2,w:Math.SQRT1_2}],['absolute-orientation',{x:0.5,y:0.5,z:0.5,w:0.5}]];
    for(const [type,quaternion]of sensors){await cdp.send('Emulation.setSensorOverrideEnabled',{type,enabled:true});await cdp.send('Emulation.setSensorOverrideReadings',{type,reading:{quaternion}});}
    await page.evaluate(async()=>{
      const {createWebDeviceAccess,observeWebOrientation,core}=window.sdkTest;
      const sdk=createWebDeviceAccess(),observation=observeWebOrientation(sdk,window),control=new AbortController();
      let permissionRequests=0;DeviceOrientationEvent.requestPermission=()=>{permissionRequests++;throw Error('Unexpected permission request');};
      const state={sdk,observation,control,values:{},events:[],errors:[],requests:()=>permissionRequests};window.nativeOrientation=state;
      state.tasks=await Promise.all([core.RelativeOrientationEntity,core.AbsoluteOrientationEntity].map(async kind=>{
        const target=(await sdk.sensors.list(kind))[0];
        return {done:(async()=>{try{for await(const snapshot of sdk.watch(target,{signal:control.signal})){
          state.values[kind.kind]=snapshot.value;state.events.push({kind:kind.kind,value:snapshot.value});
        }}catch(error){if(error.name!=='AbortError')state.errors.push(error.code||error.message);}})()};
      }));
    });
    await waitForBrowserValue(page,()=>Object.values(window.nativeOrientation.values).filter(Boolean).length===2);
    const values=await page.evaluate(()=>window.nativeOrientation.values);
    const closeQuaternion=(actual,expected)=>{
      const same=Object.keys(expected).every(key=>Math.abs(actual[key]-expected[key])<0.002);
      const opposite=Object.keys(expected).every(key=>Math.abs(actual[key]+expected[key])<0.002);
      assert.ok(same||opposite,JSON.stringify({actual,expected}));
    };
    closeQuaternion(values.RelativeOrientation,sensors[0][1]);closeQuaternion(values.AbsoluteOrientation,sensors[1][1]);
    // A later native sample must not be replaced by a session-rebased or cached first pose.
    const changed={x:0,y:Math.sin(Math.PI/8),z:0,w:Math.cos(Math.PI/8)};
    await cdp.send('Emulation.setSensorOverrideReadings',{type:'relative-orientation',reading:{quaternion:changed}});
    await waitForBrowserValue(page,()=>Math.abs(window.nativeOrientation.values.RelativeOrientation?.y-Math.sin(Math.PI/8))<0.002);
    const changedValue=await page.evaluate(()=>window.nativeOrientation.values.RelativeOrientation);closeQuaternion(changedValue,changed);
    const details=await page.evaluate(async()=>{
      const state=window.nativeOrientation;state.control.abort();await Promise.all(state.tasks.map(task=>task.done));
      state.observation.close();state.sdk.close();return {errors:state.errors,permissionRequests:state.requests()};
    });
    assert.deepEqual(details,{errors:[],permissionRequests:0});
    const deadline=Date.now()+2000;let frequencies;
    do {frequencies=await Promise.all(sensors.map(async([type])=>(await cdp.send('Emulation.getOverriddenSensorInformation',{type})).requestedSamplingFrequency));if(frequencies.every(f=>f===0))break;await new Promise(r=>setTimeout(r,20));}while(Date.now()<deadline);
    assert.deepEqual(frequencies,[0,0]);
    await mkdir('.tools/evidence',{recursive:true});
    await writeFile(`.tools/evidence/orientation-${name.toLowerCase()}.json`,JSON.stringify({browser:await browser.version(),values,changedValue,frequencies,...details},null,2));
  });
  test(`${name}: orientation observations preserve reference frames, rotations and fresh sessions`, {timeout:30000}, async t=>{
    const browser=await chromium.launch({executablePath,headless:true});t.after(()=>browser.close());
    const page=await browser.newPage();await page.goto(url);await page.waitForFunction(()=>!!window.sdkTest);
    const result=await page.evaluate(async()=>{
      const {createWebDeviceAccess,observeWebOrientation,core}=window.sdkTest;
      const sdk=createWebDeviceAccess(),source=Object.assign(new EventTarget(),{ondeviceorientation:null,ondeviceorientationabsolute:null});
      const listeners=new Map(),add=source.addEventListener.bind(source),remove=source.removeEventListener.bind(source);
      source.addEventListener=(type,listener,...rest)=>{if(type.startsWith('deviceorientation'))listeners.set(listener,type);add(type,listener,...rest);};
      source.removeEventListener=(type,listener,...rest)=>{listeners.delete(listener);remove(type,listener,...rest);};
      const observation=observeWebOrientation(sdk,source);
      const relative=(await sdk.sensors.list(core.RelativeOrientationEntity))[0],absolute=(await sdk.sensors.list(core.AbsoluteOrientationEntity))[0];
      const inert=listeners.size===0;
      async function wait(size){const end=performance.now()+1500;while(listeners.size!==size){if(performance.now()>end)throw Error('Wrong orientation listener count: '+listeners.size);await new Promise(r=>setTimeout(r,5));}}
      const event=(type,alpha,beta,gamma,absolute)=>new DeviceOrientationEvent(type,{alpha,beta,gamma,absolute});
      source.dispatchEvent(event('deviceorientation',180,0,0,false));
      const first=sdk.get(relative);await wait(1);
      source.dispatchEvent(event('deviceorientation',90,0,0,false));const fresh=(await first).value;await wait(0);
      const stream=sdk.withSensorSamplingRate(core.SensorSamplingRate.hertz(1)).watch(relative)[Symbol.asyncIterator]();
      const next=stream.next();await wait(1);
      // The first relative sample keeps its native session reference; it is not rebased to identity.
      for(const input of [[0,90,0,false],[0,90,0,false],[0,0,45,false],[90,90,45,false],[0,0,0,true],[0,null,0,false]])source.dispatchEvent(event('deviceorientation',...input));
      const values=[(await next).value.value];for(let i=0;i<5;i++)values.push((await stream.next()).value.value);
      const absoluteGet=sdk.get(absolute);await wait(2);source.dispatchEvent(event('deviceorientationabsolute',0,0,0,true));
      const absoluteValue=(await absoluteGet).value;await wait(1);
      const wrongAbsolute=sdk.get(absolute);await wait(2);source.dispatchEvent(event('deviceorientationabsolute',90,0,0,false));
      const wrongAbsoluteValue=(await wrongAbsolute).value;await wait(1);
      const old=[...listeners.keys()][0];const ended=stream.next().then(()=> 'unexpected',error=>error.code);
      observation.close();const removed=await ended;await wait(0);
      old(event('deviceorientation',0,0,0,false));
      let getRemoved;try{await sdk.get(relative);}catch(error){getRemoved=error.code;}
      const replacement=observeWebOrientation(sdk,source),newTarget=(await sdk.sensors.list(core.RelativeOrientationEntity))[0];
      const renewed=newTarget!==relative;
      replacement.close();sdk.close();return {inert,fresh,values,absoluteValue,wrongAbsoluteValue,removed,getRemoved,renewed,listeners:listeners.size};
    });
    const close=(actual,expected)=>expected.forEach((value,index)=>assert.ok(Math.abs(actual[index]-value)<1e-10,JSON.stringify(actual)));
    const rotatedX=q=>[1-2*(q.y*q.y+q.z*q.z),2*(q.x*q.y+q.z*q.w),2*(q.x*q.z-q.y*q.w)];
    const rotatedY=q=>[2*(q.x*q.y-q.z*q.w),1-2*(q.x*q.x+q.z*q.z),2*(q.y*q.z+q.x*q.w)];
    close(rotatedX(result.fresh),[0,1,0]);close(rotatedY(result.values[0]),[0,0,1]);
    assert.deepEqual(result.values[0],result.values[1]);close(rotatedX(result.values[2]),[Math.SQRT1_2,0,-Math.SQRT1_2]);
    // Intrinsic Z90-X90-Y45 maps device X to (-sqrt(.5),sqrt(.5),0).
    close(rotatedX(result.values[3]),[-Math.SQRT1_2,Math.SQRT1_2,0]);
    for(const q of result.values.slice(0,4))assert.ok(Math.abs(Math.hypot(q.x,q.y,q.z,q.w)-1)<1e-12);
    assert.deepEqual(result.values.slice(4),[null,null]);assert.equal(result.wrongAbsoluteValue,null);
    assert.deepEqual(result.absoluteValue,{x:0,y:0,z:0,w:1});
    assert.deepEqual([result.inert,result.removed,result.getRemoved,result.renewed,result.listeners],[true,'EntityRemoved','EntityRemoved',true,0]);
  });
  test(`${name}: motion streams retain equal values, whole-vector nulls and removed targets`, {timeout:30000}, async t=>{
    const browser=await chromium.launch({executablePath,headless:true});t.after(()=>browser.close());
    const page=await browser.newPage();await page.goto(url);await page.waitForFunction(()=>!!window.sdkTest);
    const result=await page.evaluate(async()=>{
      const {createWebDeviceAccess,observeWebMotion,core}=window.sdkTest;
      const sdk=createWebDeviceAccess(),source=Object.assign(new EventTarget(),{ondevicemotion:null});
      let listener;const add=source.addEventListener.bind(source);
      source.addEventListener=(type,callback,...rest)=>{if(type==='devicemotion')listener=callback;add(type,callback,...rest);};
      const motion=observeWebMotion(sdk,source),target=(await sdk.sensors.list(core.AccelerometerEntity))[0];
      const stream=sdk.withSensorSamplingRate(core.SensorSamplingRate.hertz(1)).watch(target)[Symbol.asyncIterator]();
      const first=stream.next();const end=performance.now()+1500;
      while(!listener){if(performance.now()>end)throw Error('No listener');await new Promise(r=>setTimeout(r,5));}
      const event=new DeviceMotionEvent('devicemotion',{accelerationIncludingGravity:{x:0,y:0,z:0}});
      source.dispatchEvent(event);source.dispatchEvent(event);
      source.dispatchEvent(new DeviceMotionEvent('devicemotion',{accelerationIncludingGravity:{x:1,y:null,z:0}}));
      const values=[(await first).value.value,(await stream.next()).value.value,(await stream.next()).value.value];
      const ended=stream.next().then(()=> 'unexpected',error=>error.code);motion.close();const error=await ended;
      listener(event);let removed;try{await sdk.get(target);}catch(e){removed=e.code;}
      const again=observeWebMotion(sdk,source),count=(await sdk.sensors.list(core.AccelerometerEntity)).length;
      again.close();sdk.close();return {values,error,removed,count};
    });
    assert.deepEqual(result,{values:[{x:0,y:0,z:0},{x:0,y:0,z:0},null],error:'EntityRemoved',removed:'EntityRemoved',count:1});
  });
  test(`${name}: app-observed native motion permission revocation fails streams and permits fresh recovery`, {timeout:30000}, async t=>{
    const browser=await chromium.launch({executablePath,headless:true});t.after(()=>browser.close());
    const context=await browser.newContext(),page=await context.newPage();await page.goto(url);await page.waitForFunction(()=>!!window.sdkTest);
    const cdp=await context.newCDPSession(page),{targetInfo}=await cdp.send('Target.getTargetInfo');
    await cdp.send('Emulation.setSensorOverrideEnabled',{type:'accelerometer',enabled:true});
    await cdp.send('Emulation.setSensorOverrideReadings',{type:'accelerometer',reading:{xyz:{x:1,y:2,z:3}}});
    await page.evaluate(async()=>{
      const {createWebDeviceAccess,observeWebMotion,core}=window.sdkTest;
      const sdk=createWebDeviceAccess(),motion=observeWebMotion(sdk,window);
      const target=(await sdk.sensors.list(core.AccelerometerEntity))[0];
      const permission=await navigator.permissions.query({name:'accelerometer'});
      const apply=()=>{
        sdk.observers.permission(core.AccelerometerEntity,permission.state==='granted'?core.PermissionStatus.Granted:core.PermissionStatus.Denied);
        sdk.observers.failure(core.AccelerometerEntity,permission.state==='granted'?null:new core.DeviceReadoutError(core.ErrorCode.PermissionDenied,'App observed revoked motion permission.'));
      };
      permission.addEventListener('change',apply);apply();
      const state={sdk,motion,target,permission,apply,values:[],error:null};window.motionPermission=state;
      state.done=(async()=>{try{for await(const value of sdk.watch(target))state.values.push(value.value);}catch(error){state.error=error.code;}})();
    });
    await waitForBrowserValue(page,()=>window.motionPermission.values.some(value=>value?.x===1));
    await cdp.send('Browser.setPermission',{permission:{name:'accelerometer'},setting:'denied',origin:url,browserContextId:targetInfo.browserContextId});
    await waitForBrowserValue(page,()=>window.motionPermission.error==='PermissionDenied');
    const denied=await page.evaluate(async()=>{
      const {sdk,target}=window.motionPermission;let error;
      try{await sdk.get(target);}catch(e){error=e.code;}
      return {error,status:await sdk.permissions.check(window.sdkTest.core.AccelerometerEntity)};
    });
    assert.deepEqual(denied,{error:'PermissionDenied',status:'Denied'});
    await cdp.send('Emulation.setSensorOverrideReadings',{type:'accelerometer',reading:{xyz:{x:20,y:2,z:3}}});
    await cdp.send('Browser.setPermission',{permission:{name:'accelerometer'},setting:'granted',origin:url,browserContextId:targetInfo.browserContextId});
    await waitForBrowserValue(page,async()=>await window.motionPermission.sdk.permissions.check(window.sdkTest.core.AccelerometerEntity)==='Granted');
    const restored=await page.evaluate(async()=>{
      const state=window.motionPermission;const value=await state.sdk.get(state.target);
      state.permission.removeEventListener('change',state.apply);state.motion.close();state.sdk.close();
      return {value:value.value,oldError:state.error};
    });
    assert.deepEqual(restored,{value:{x:20,y:2,z:3},oldError:'PermissionDenied'});
  });
  test(`${name}: native virtual motion sensors reach worker snapshots and release their resources`, {timeout:30000}, async t=>{
    const browser=await chromium.launch({executablePath,headless:true});t.after(()=>browser.close());
    const context=await browser.newContext(),page=await context.newPage();await page.goto(url);await page.waitForFunction(()=>!!window.sdkTest);
    const cdp=await context.newCDPSession(page);
    const sensors=[['accelerometer',{x:2,y:3,z:10}],['linear-acceleration',{x:1,y:1,z:0.2}],['gyroscope',{x:Math.PI/2,y:-Math.PI/4,z:Math.PI}]];
    for(const [type,xyz]of sensors){await cdp.send('Emulation.setSensorOverrideEnabled',{type,enabled:true});await cdp.send('Emulation.setSensorOverrideReadings',{type,reading:{xyz}});}
    await page.evaluate(async()=>{
      const {createWebDeviceAccess,observeWebMotion,core}=window.sdkTest;
      const sdk=createWebDeviceAccess(),observation=observeWebMotion(sdk,window),control=new AbortController();
      let permissionRequests=0;
      DeviceMotionEvent.requestPermission=()=>{permissionRequests++;throw Error('SDK must not request permission.');};
      const values={},errors=[];
      const kinds=[core.AccelerometerEntity,core.LinearAccelerationEntity,core.GravityEntity,core.GyroscopeEntity];
      const tasks=await Promise.all(kinds.map(async kind=>{
        const target=(await sdk.sensors.list(kind))[0];
        const done=(async()=>{try{for await(const value of sdk.watch(target,{signal:control.signal}))values[kind.kind]=value.value;}catch(error){if(error.name!=='AbortError')errors.push(error.code||error.message);}})();
        return {done};
      }));
      window.nativeMotionTest={sdk,observation,control,values,errors,tasks,requests:()=>permissionRequests};
    });
    await waitForBrowserValue(page,()=>Object.values(window.nativeMotionTest.values).filter(Boolean).length===4);
    const values=await page.evaluate(()=>window.nativeMotionTest.values);
    assert.deepEqual(values.Accelerometer,{x:2,y:3,z:10});assert.deepEqual(values.LinearAcceleration,{x:1,y:1,z:0.2});
    assert.deepEqual(values.Gravity,{x:1,y:2,z:9.8});
    for(const [axis,expected]of Object.entries({x:Math.PI/2,y:-Math.PI/4,z:Math.PI}))assert.ok(Math.abs(values.Gyroscope[axis]-expected)<0.002,JSON.stringify(values.Gyroscope));
    const details=await page.evaluate(async()=>{
      const state=window.nativeMotionTest;state.control.abort();await Promise.all(state.tasks.map(task=>task.done));
      state.observation.close();state.sdk.close();return {errors:state.errors,permissionRequests:state.requests()};
    });
    assert.deepEqual(details,{errors:[],permissionRequests:0});
    const deadline=Date.now()+2000;let frequencies;
    do {frequencies=await Promise.all(sensors.map(async([type])=>(await cdp.send('Emulation.getOverriddenSensorInformation',{type})).requestedSamplingFrequency));if(frequencies.every(f=>f===0))break;await new Promise(r=>setTimeout(r,20));}while(Date.now()<deadline);
    assert.deepEqual(frequencies,[0,0,0]);
    await mkdir('.tools/evidence',{recursive:true});
    await writeFile(`.tools/evidence/motion-${name.toLowerCase()}.json`,JSON.stringify({browser:await browser.version(),values,frequencies,...details},null,2));
  });
  test(`${name}: observed visibility pauses motion sources and resumes fresh sessions`, {timeout:30000}, async t=>{
    const browser=await chromium.launch({executablePath,headless:true});t.after(()=>browser.close());
    const page=await browser.newPage();await page.goto(url);await page.waitForFunction(()=>!!window.sdkTest);
    const result=await page.evaluate(async()=>{
      const {createWebDeviceAccess,observeWebMotion,observeWebSensorActivity,core}=window.sdkTest;
      const sdk=createWebDeviceAccess(),source=Object.assign(new EventTarget(),{ondevicemotion:null});
      let active=0;const add=source.addEventListener.bind(source),remove=source.removeEventListener.bind(source);
      source.addEventListener=(type,...args)=>{if(type==='devicemotion')active++;add(type,...args);};
      source.removeEventListener=(type,...args)=>{if(type==='devicemotion')active--;remove(type,...args);};
      const lifecycle=new EventTarget(),documentSource=Object.assign(new EventTarget(),{visibilityState:'hidden',defaultView:lifecycle});
      const activity=observeWebSensorActivity(sdk,documentSource),motion=observeWebMotion(sdk,source);
      const target=(await sdk.sensors.list(core.AccelerometerEntity))[0];
      const stream=sdk.withReadTimeout(core.Duration.milliseconds(100)).watch(target)[Symbol.asyncIterator]();
      const first=stream.next();let ended=false;first.then(()=>ended=true,()=>ended=true);
      await new Promise(r=>setTimeout(r,180));const pausedInitially=!ended&&active===0;
      async function wait(expected){const end=performance.now()+1500;while(active!==expected){if(performance.now()>end)throw Error('Wrong active listener count '+active);await new Promise(r=>setTimeout(r,5));}}
      documentSource.visibilityState='visible';documentSource.dispatchEvent(new Event('visibilitychange'));await wait(1);
      source.dispatchEvent(new DeviceMotionEvent('devicemotion',{accelerationIncludingGravity:{x:1,y:0,z:0}}));
      const firstValue=(await first).value.value.x;
      documentSource.visibilityState='hidden';documentSource.dispatchEvent(new Event('visibilitychange'));await wait(0);
      source.dispatchEvent(new DeviceMotionEvent('devicemotion',{accelerationIncludingGravity:{x:99,y:0,z:0}}));
      const next=stream.next();documentSource.visibilityState='visible';lifecycle.dispatchEvent(new PageTransitionEvent('pageshow',{persisted:true}));await wait(1);
      source.dispatchEvent(new DeviceMotionEvent('devicemotion',{accelerationIncludingGravity:{x:2,y:0,z:0}}));
      const nextValue=(await next).value.value.x;
      lifecycle.dispatchEvent(new PageTransitionEvent('pagehide',{persisted:true}));await wait(0);
      await stream.return();activity.close();motion.close();sdk.close();
      return {pausedInitially,firstValue,nextValue,active};
    });
    assert.deepEqual(result,{pausedInitially:true,firstValue:1,nextValue:2,active:0});
  });
  test(`${name}: app-owned motion events preserve vector units and await a fresh sample`, {timeout:30000}, async t=>{
    const browser=await chromium.launch({executablePath,headless:true});t.after(()=>browser.close());
    const page=await browser.newPage();await page.goto(url);await page.waitForFunction(()=>!!window.sdkTest);
    const result=await page.evaluate(async()=>{
      const {createWebDeviceAccess,observeWebMotion,core}=window.sdkTest;
      const sdk=createWebDeviceAccess(),source=Object.assign(new EventTarget(),{ondevicemotion:null});
      let attached=0,detached=0;
      const add=source.addEventListener.bind(source),remove=source.removeEventListener.bind(source);
      source.addEventListener=(type,...args)=>{if(type==='devicemotion')attached++;add(type,...args);};
      source.removeEventListener=(type,...args)=>{if(type==='devicemotion')detached++;remove(type,...args);};
      const observation=observeWebMotion(sdk,source);
      const initialAttached=attached;
      const kinds=[core.AccelerometerEntity,core.LinearAccelerationEntity,core.GravityEntity,core.GyroscopeEntity];
      const targets=await Promise.all(kinds.map(async kind=>(await sdk.sensors.list(kind))[0]));
      const afterDiscovery=attached;
      source.dispatchEvent(new DeviceMotionEvent('devicemotion',{accelerationIncludingGravity:{x:99,y:99,z:99}}));
      const pending=targets.map(target=>sdk.get(target));
      const deadline=performance.now()+2000;
      while(attached<4){if(performance.now()>deadline)throw Error('No native motion listeners');await new Promise(r=>setTimeout(r,5));}
      source.dispatchEvent(new DeviceMotionEvent('devicemotion',{
        accelerationIncludingGravity:{x:2,y:3,z:10},acceleration:{x:1,y:1,z:0.2},
        rotationRate:{alpha:180,beta:90,gamma:-45},interval:16
      }));
      const values=(await Promise.all(pending)).map(snapshot=>snapshot.value);
      while(detached<4){if(performance.now()>deadline)throw Error('Motion listeners not released');await new Promise(r=>setTimeout(r,5));}
      observation.close();sdk.close();return {values,initialAttached,afterDiscovery,attached,detached};
    });
    assert.deepEqual(result.values.slice(0,3),[{x:2,y:3,z:10},{x:1,y:1,z:0.2},{x:1,y:2,z:9.8}]);
    assert.deepEqual(result.values[3],{x:Math.PI,y:Math.PI/2,z:-Math.PI/4});
    assert.deepEqual([result.initialAttached,result.afterDiscovery,result.attached,result.detached],[0,0,4,4]);
  });
  test(`${name}: display recovery and disposal preserve application and independent provider failures`, {timeout:30000}, async t=>{
    const browser=await chromium.launch({executablePath,headless:true});t.after(()=>browser.close());
    const page=await browser.newPage(),uncaught=[];page.on('pageerror',error=>uncaught.push(error.message));
    await page.goto(url);await page.waitForFunction(()=>!!window.sdkTest);
    const result=await page.evaluate(async()=>{
      const {createWebDeviceAccess,observeWebDisplays,core}=window.sdkTest;
      const access=createWebDeviceAccess(),permission=Object.assign(new EventTarget(),{state:'granted'});
      const screen=Object.assign(new EventTarget(),{label:'Initial',isPrimary:true,isInternal:false,left:0,top:0,
        width:800,height:600,availLeft:0,availTop:0,availWidth:800,availHeight:600,devicePixelRatio:1,colorDepth:24});
      const details=Object.assign(new EventTarget(),{screens:[screen],currentScreen:screen});
      const denied=new core.DeviceReadoutError(core.ErrorCode.PermissionDenied,'Application blocks display access');
      const appFailure=new core.DeviceReadoutError(core.ErrorCode.ReadFailed,'Application is still unavailable');
      const code=async run=>run().then(()=> 'unexpected',error=>error.code),errors=[];
      access.observers.failure(core.DisplayEntity,denied);
      const observation=observeWebDisplays(access.withPollInterval(core.Duration.seconds(2)),window,details,{permission});
      errors.push(await code(()=>access.displays.list()));
      access.observers.failure(core.DisplayEntity,null);
      const target=await access.displays.current();
      access.observers.failure(core.DisplayEntity,appFailure);
      permission.state='denied';permission.dispatchEvent(new Event('change'));
      errors.push(await code(()=>access.get(target)));
      access.observers.failure(core.DisplayEntity,null);
      errors.push(await code(()=>access.get(target)));
      access.observers.failure(core.DisplayEntity,appFailure);
      screen.label='Fresh';permission.state='granted';permission.dispatchEvent(new Event('change'));
      errors.push(await code(()=>access.get(target)));
      access.observers.failure(core.DisplayEntity,null);
      const recovered=(await access.get(target)).label;
      const other=access.observers.failureSource(core.DisplayEntity);
      other.publish(new core.DeviceReadoutError(core.ErrorCode.UnsupportedEntity,'A separate source blocks the inventory'));
      details.dispatchEvent(new Event('screenschange'));
      errors.push(await code(()=>access.displays.list()));
      access.observers.failure(core.DisplayEntity,denied);
      observation.close();observation.close();
      errors.push(await code(()=>access.displays.list()));
      access.observers.failure(core.DisplayEntity,null);
      errors.push(await code(()=>access.displays.list()));
      other.close();const empty=(await access.displays.list()).length;
      errors.push(await code(()=>access.get(target)));
      access.close();observation.close();
      return {errors,recovered,empty};
    });
    assert.deepEqual(result,{errors:['PermissionDenied','ReadFailed','PermissionDenied','ReadFailed','UnsupportedEntity',
      'PermissionDenied','UnsupportedEntity','EntityRemoved'],recovered:'Fresh',empty:0});
    assert.deepEqual(uncaught,[]);
  });
  test(`${name}: display disposal retires every target when host listener cleanup throws`, {timeout:30000}, async t=>{
    const browser=await chromium.launch({executablePath,headless:true});t.after(()=>browser.close());
    const page=await browser.newPage(),uncaught=[];page.on('pageerror',error=>uncaught.push(error.message));
    await page.goto(url);await page.waitForFunction(()=>!!window.sdkTest);
    const result=await page.evaluate(async()=>{
      const {createWebDeviceAccess,observeWebDisplays}=window.sdkTest;
      const access=createWebDeviceAccess(),removed=[];let broken=false,reads=0;
      const screen=label=>Object.assign(new class extends EventTarget {
        removeEventListener(type,listener,...options){removed.push(label+':'+type);if(label==='First')throw Error('Host screen cleanup failed');super.removeEventListener(type,listener,...options);}
      }(),{label,isPrimary:label==='First',isInternal:false,left:0,top:0,width:800,height:600,
        availLeft:0,availTop:0,availWidth:800,availHeight:600,devicePixelRatio:1,colorDepth:24});
      const screens=[screen('First'),screen('Second')];
      const details=new class extends EventTarget {
        get screens(){reads++;if(broken)throw Error('Host inventory failed');return screens;}
        get currentScreen(){return screens[0];}
        removeEventListener(type,listener,...options){removed.push('details:'+type);if(type==='screenschange')throw Error('Host details cleanup failed');super.removeEventListener(type,listener,...options);}
      }();
      const observation=observeWebDisplays(access,window,details),targets=await access.displays.list();
      broken=true;details.dispatchEvent(new Event('screenschange'));
      const before=await access.displays.list().then(()=> 'unexpected',error=>error.code);
      let closeError=null;try{observation.close();}catch(error){closeError=error.message;}
      const after=await access.displays.list().then(items=>items.length,error=>error.code);
      const errors=await Promise.all(targets.map(target=>access.get(target).then(()=> 'unexpected',error=>error.code)));
      const readsAtClose=reads;details.dispatchEvent(new Event('screenschange'));screens.forEach(screen=>screen.dispatchEvent(new Event('change')));
      observation.close();access.close();observation.close();
      return {before,closeError,after,errors,removed:removed.sort(),lateReads:reads-readsAtClose};
    });
    assert.deepEqual(result,{before:'ReadFailed',closeError:null,after:0,errors:['EntityRemoved','EntityRemoved'],
      removed:['First:change','Second:change','details:currentscreenchange','details:screenschange'],lateReads:0});
    assert.deepEqual(uncaught,[]);
  });
  test(`${name}: newer display inventories survive stale initial getter returns and failures`, {timeout:30000}, async t=>{
    const browser=await chromium.launch({executablePath,headless:true});t.after(()=>browser.close());
    const page=await browser.newPage();await page.goto(url);await page.waitForFunction(()=>!!window.sdkTest);
    const result=await page.evaluate(async()=>{
      const {createWebDeviceAccess,observeWebDisplays}=window.sdkTest,results=[];
      for(const mode of ['return','throw']){
        const screen=label=>Object.assign(new EventTarget(),{label,isPrimary:true,isInternal:false,left:0,top:0,
          width:800,height:600,availLeft:0,availTop:0,availWidth:800,availHeight:600,devicePixelRatio:1,colorDepth:24});
        const old=screen('Old'),fresh=screen('Fresh');let inventory=[old],current=old,reenter=true,reads=0;
        const details=new class extends EventTarget {
          get screens(){
            reads++;const captured=inventory;
            if(reenter){reenter=false;inventory=[fresh];current=fresh;this.dispatchEvent(new Event('screenschange'));
              if(mode==='throw')throw Error('Initial inventory became stale');}
            return captured;
          }
          get currentScreen(){return current;}
        }();
        const access=createWebDeviceAccess();let observation;
        try {
          observation=observeWebDisplays(access,window,details);
          const targets=await access.displays.list(),selected=await access.displays.current();
          const labels=await Promise.all(targets.map(async target=>(await access.get(target)).label));
          const before=reads;await access.displays.list();await access.displays.current();
          results.push({mode,labels,current:selected?(await access.get(selected)).label:null,queryReads:reads-before});
        }catch(error){results.push({mode,error:error.code??error.message});}
        finally{observation?.close();access.close();}
      }
      return results;
    });
    assert.deepEqual(result,[{mode:'return',labels:['Fresh'],current:'Fresh',queryReads:0},
      {mode:'throw',labels:['Fresh'],current:'Fresh',queryReads:0}]);
  });
  test(`${name}: display hotplug retires handles and gates stale listeners when detachment fails`, {timeout:30000}, async t=>{
    const browser=await chromium.launch({executablePath,headless:true});t.after(()=>browser.close());
    const page=await browser.newPage(),uncaught=[];page.on('pageerror',error=>uncaught.push(error.message));
    await page.goto(url);await page.waitForFunction(()=>!!window.sdkTest);
    const result=await page.evaluate(async()=>{
      const {createWebDeviceAccess,observeWebDisplays}=window.sdkTest;
      const access=createWebDeviceAccess();let reads=0;
      const old=Object.assign(new class extends EventTarget {
        get label(){reads++;return 'Reattached';}
        removeEventListener(){throw Error('Host cannot detach this listener');}
      }(),{isPrimary:true,isInternal:false,left:0,top:0,width:800,height:600,
        availLeft:0,availTop:0,availWidth:800,availHeight:600,devicePixelRatio:1,colorDepth:24});
      const kept=Object.assign(new EventTarget(),{label:'Kept',isPrimary:false,isInternal:false,left:800,top:0,width:800,height:600,
        availLeft:800,availTop:0,availWidth:800,availHeight:600,devicePixelRatio:1,colorDepth:24});
      const details=Object.assign(new EventTarget(),{screens:[old,kept],currentScreen:old});
      const observation=observeWebDisplays(access,window,details),original=await access.displays.current();
      const stream=access.watch(original)[Symbol.asyncIterator]();await stream.next();
      const ended=stream.next().then(()=> 'unexpected',error=>error.code);
      details.screens=[kept];details.currentScreen=kept;details.dispatchEvent(new Event('screenschange'));
      const streamError=await ended;
      const remaining=await access.displays.list().then(targets=>Promise.all(targets.map(async target=>(await access.get(target)).label)),error=>error.code);
      const current=await access.displays.current().then(async target=>target?(await access.get(target)).label:null,error=>error.code);
      const removed=await access.get(original).then(()=> 'unexpected',error=>error.code);
      const before=reads;old.dispatchEvent(new Event('change'));const lateReads=reads-before;
      details.screens=[old,kept];details.currentScreen=old;details.dispatchEvent(new Event('screenschange'));
      const fresh=await access.displays.current().then(async target=>target?(await access.get(target)).label:null,error=>error.code);
      const oldAfterReattach=await access.get(original).then(()=> 'unexpected',error=>error.code);
      const reattachedReads=reads;old.dispatchEvent(new Event('change'));const onlyNewListenerReads=reads-reattachedReads;
      observation.close();access.close();
      return {streamError,remaining,current,removed,lateReads,fresh,oldAfterReattach,onlyNewListenerReads};
    });
    assert.deepEqual(result,{streamError:'EntityRemoved',remaining:['Kept'],current:'Kept',removed:'EntityRemoved',lateReads:0,
      fresh:'Reattached',oldAfterReattach:'EntityRemoved',onlyNewListenerReads:1});
    assert.deepEqual(uncaught,[]);
  });
  test(`${name}: screen permission lost during inventory collection cannot be cleared by a partial refresh`, {timeout:30000}, async t=>{
    const browser=await chromium.launch({executablePath,headless:true});t.after(()=>browser.close());
    const page=await browser.newPage();await page.goto(url);await page.waitForFunction(()=>!!window.sdkTest);
    const result=await page.evaluate(async()=>{
      const {createWebDeviceAccess,observeWebDisplays,core}=window.sdkTest;
      const screenSource=Object.assign(new EventTarget(),{label:'Fixture',isPrimary:true,isInternal:false,left:0,top:0,
        width:800,height:600,availLeft:0,availTop:0,availWidth:800,availHeight:600,devicePixelRatio:1,colorDepth:24});
      const permission=Object.assign(new EventTarget(),{state:'granted'});
      const details=new class extends EventTarget {
        get screens(){permission.state='denied';return [screenSource];}
        get currentScreen(){return screenSource;}
      }();
      const sdk=createWebDeviceAccess(),observation=observeWebDisplays(sdk,window,details,{permission});
      let listError;try{await sdk.displays.list();}catch(error){listError=error.code;}
      const status=await sdk.permissions.check(core.DisplayEntity);
      observation.close();sdk.close();return {listError,status};
    });
    assert.deepEqual(result,{listError:'PermissionDenied',status:'Denied'});
  });
  test(`${name}: display observer inventory failures are typed and disposal clears stale failure state`, {timeout:30000}, async t=>{
    const browser=await chromium.launch({executablePath,headless:true});t.after(()=>browser.close());
    const context=await browser.newContext({viewport:null}),page=await context.newPage();
    const uncaught=[];page.on('pageerror',error=>uncaught.push(error.message));
    await page.goto(url);await page.waitForFunction(()=>!!window.sdkTest);
    const cdp=await context.newCDPSession(page),{targetInfo}=await cdp.send('Target.getTargetInfo');
    await cdp.send('Browser.setPermission',{permission:{name:'window-management'},setting:'granted',origin:url,browserContextId:targetInfo.browserContextId});
    const result=await page.evaluate(async()=>{
      const {createWebDeviceAccess,observeWebDisplays}=window.sdkTest,native=await getScreenDetails();
      let inventory=[],broken=false,reads=0;
      const feed=new class extends EventTarget {
        get screens(){reads++;if(broken)throw new DOMException('Inventory unavailable','InvalidStateError');return inventory;}
        get currentScreen(){return inventory.includes(native.currentScreen)?native.currentScreen:null;}
      }();
      const sdk=createWebDeviceAccess(),observation=observeWebDisplays(sdk,window,feed);
      const initialEmpty=(await sdk.displays.list()).length;
      inventory=native.screens;feed.dispatchEvent(new Event('screenschange'));
      const target=await sdk.displays.current(),iterator=sdk.watch(target)[Symbol.asyncIterator]();await iterator.next();
      const readsAfterAttach=reads;await sdk.get(target);await sdk.displays.list();const readsAfterCalls=reads;
      const failed=iterator.next().then(()=> 'Unexpected snapshot',error=>error.code);
      broken=true;feed.dispatchEvent(new Event('screenschange'));const streamFailure=await failed;
      let readFailure;try{await sdk.get(target);}catch(error){readFailure=error.code;}
      broken=false;feed.dispatchEvent(new Event('screenschange'));
      const restored=await sdk.get(target);
      broken=true;feed.dispatchEvent(new Event('screenschange'));
      observation.close();observation.close();
      const readsAtClose=reads;feed.dispatchEvent(new Event('screenschange'));const readsAfterClose=reads;
      const finalEmpty=(await sdk.displays.list()).length;let removed;
      try{await sdk.get(target);}catch(error){removed=error.code;}
      sdk.close();
      return {initialEmpty,readsAfterAttach,readsAfterCalls,streamFailure,readFailure,restoredPrimary:restored.primary,
        readsAtClose,readsAfterClose,finalEmpty,removed};
    });
    assert.equal(result.initialEmpty,0);assert.equal(result.readsAfterAttach,result.readsAfterCalls);
    assert.equal(result.streamFailure,'ReadFailed');assert.equal(result.readFailure,'ReadFailed');assert.equal(result.restoredPrimary,true);
    assert.equal(result.readsAtClose,result.readsAfterClose);assert.equal(result.finalEmpty,0);assert.equal(result.removed,'EntityRemoved');
    assert.deepEqual(uncaught,[]);
  });
  test(`${name}: application-supplied permission changes block screen reads and recover without reopening a stream`, {timeout:30000}, async t=>{
    const browser=await chromium.launch({executablePath,headless:true});t.after(()=>browser.close());
    const context=await browser.newContext({viewport:null}),page=await context.newPage();
    const uncaught=[];page.on('pageerror',error=>uncaught.push(error.message));
    await page.goto(url);await page.waitForFunction(()=>!!window.sdkTest);
    const cdp=await context.newCDPSession(page),{targetInfo}=await cdp.send('Target.getTargetInfo');
    const setPermission=setting=>cdp.send('Browser.setPermission',{permission:{name:'window-management'},setting,origin:url,browserContextId:targetInfo.browserContextId});
    await setPermission('granted');
    await page.evaluate(async()=>{
      const {createWebDeviceAccess,observeWebDisplays}=window.sdkTest;
      const details=await getScreenDetails(),permission=await navigator.permissions.query({name:'window-management'});
      const sdk=createWebDeviceAccess(),observation=observeWebDisplays(sdk,window,details,{permission});
      const target=await sdk.displays.current(),iterator=sdk.watch(target)[Symbol.asyncIterator]();await iterator.next();
      const failure=iterator.next().then(()=> 'Unexpected snapshot',error=>error.code);
      window.permissionDisplayTest={sdk,observation,target,iterator,failure,details};
    });
    await setPermission('denied');
    await waitForBrowserValue(page,async()=>await window.permissionDisplayTest.sdk.permissions.check(window.sdkTest.core.DisplayEntity)==='Denied');
    const denied=await page.evaluate(async()=>{
      const {sdk,target,failure}=window.permissionDisplayTest;
      const result={stream:await failure};
      for(const [name,operation]of [['get',()=>sdk.get(target)],['list',()=>sdk.displays.list()],['current',()=>sdk.displays.current()]]){
        try{await operation();result[name]='Unexpected value';}catch(error){result[name]=error.code;}
      }
      return result;
    });
    assert.deepEqual(denied,{stream:'PermissionDenied',get:'PermissionDenied',list:'PermissionDenied',current:'PermissionDenied'});
    await page.evaluate(()=>{
      const state=window.permissionDisplayTest;
      state.coordinatorCalled=false;state.requestSettled=false;
      state.uncoordinate=state.sdk.observers.onPermissionRequest(()=>{state.coordinatorCalled=true;});
      state.request=state.sdk.permissions.request(window.sdkTest.core.DisplayEntity).then(status=>{state.requestSettled=true;return status;});
    });
    await page.waitForFunction(()=>window.permissionDisplayTest.coordinatorCalled);
    const prematurelySettled=await page.evaluate(async()=>{
      const state=window.permissionDisplayTest;
      state.details.dispatchEvent(new Event('screenschange'));
      await new Promise(resolve=>setTimeout(resolve,40));return state.requestSettled;
    });
    assert.equal(prematurelySettled,false,'An unrelated screen update must not complete the application permission interaction.');
    await setPermission('granted');
    await waitForBrowserValue(page,async()=>await window.permissionDisplayTest.sdk.permissions.check(window.sdkTest.core.DisplayEntity)==='Granted');
    const restored=await page.evaluate(async()=>{
      const {sdk,target,iterator,observation,request,uncoordinate}=window.permissionDisplayTest;
      const snapshot=await sdk.get(target);let oldStream;
      try{oldStream=(await iterator.next()).done;}catch(error){oldStream=error.code;}
      const requestedStatus=await request;uncoordinate();observation.close();sdk.close();return {primary:snapshot.primary,oldStream,requestedStatus};
    });
    assert.deepEqual(restored,{primary:true,oldStream:'PermissionDenied',requestedStatus:'Granted'});
    assert.deepEqual(uncaught,[]);
  });
  test(`${name}: display discovery follows native hotplug and current screen without reviving removed handles`, {timeout:30000}, async t=>{
    const browser=await chromium.launch({executablePath,headless:true});t.after(()=>browser.close());
    const context=await browser.newContext({viewport:null}),page=await context.newPage();
    const uncaught=[];page.on('pageerror',error=>uncaught.push(error.message));
    await page.goto(url);await page.waitForFunction(()=>!!window.sdkTest);
    const cdp=await context.newCDPSession(page),{targetInfo}=await cdp.send('Target.getTargetInfo');
    await cdp.send('Browser.setPermission',{permission:{name:'window-management'},setting:'granted',origin:url,browserContextId:targetInfo.browserContextId});
    await page.evaluate(async()=>{
      const {createWebDeviceAccess,observeWebDisplays}=window.sdkTest;
      const details=await getScreenDetails(),sdk=createWebDeviceAccess();
      const observation=observeWebDisplays(sdk,window,details);
      window.hotplugTest={sdk,details,observation};
    });
    const {screenInfo:added}=await cdp.send('Emulation.addScreen',{left:-1600,top:0,width:1600,height:900,devicePixelRatio:2,rotation:90,label:'Same monitor label'});
    const {screenInfo:duplicate}=await cdp.send('Emulation.addScreen',{left:1000,top:0,width:1200,height:800,label:'Same monitor label'});
    await waitForBrowserValue(page,async()=> (await window.hotplugTest.sdk.displays.list()).length===3);
    const discovered=await page.evaluate(async()=>{
      const {sdk}=window.hotplugTest,entities=await sdk.displays.list();
      const snapshots=await Promise.all(entities.map(entity=>sdk.get(entity)));
      const selected=entities[snapshots.findIndex(value=>value.logicalBounds.x===-1600)];
      const iterator=sdk.watch(selected)[Symbol.asyncIterator]();await iterator.next();
      const removed=(async()=>{try{while(!(await iterator.next()).done){}return 'Ended';}catch(error){return error.code;}})();
      Object.assign(window.hotplugTest,{selected,iterator,removed});
      return {count:entities.length,sameLabels:snapshots.filter(value=>value.label==='Same monitor label').length};
    });
    assert.deepEqual(discovered,{count:3,sameLabels:2});
    const {windowId}=await cdp.send('Browser.getWindowForTarget');
    await cdp.send('Browser.setWindowBounds',{windowId,bounds:{left:-1550,top:20,width:700,height:400}});
    await page.waitForFunction(()=>window.hotplugTest.details.currentScreen.left===-1600,{},{timeout:2000});
    await waitForBrowserValue(page,async()=>{
      const {sdk}=window.hotplugTest,current=await sdk.displays.current();
      return current!==null&&(await sdk.get(current)).logicalBounds.x===-1600;
    });
    const current=await page.evaluate(async()=>{
      const {sdk}=window.hotplugTest,selected=await sdk.get(await sdk.displays.current());
      return {x:selected.logicalBounds.x,orientation:selected.orientation,rotation:selected.rotationDegrees,nativeAngle:window.screen.orientation.angle};
    });
    // CDP's display rotation and the web ScreenOrientation angle use different conventions.
    assert.deepEqual(current,{x:-1600,orientation:'LandscapeSecondary',rotation:270,nativeAngle:270});
    await cdp.send('Emulation.removeScreen',{screenId:added.id});
    assert.equal(await page.evaluate(()=>window.hotplugTest.removed),'EntityRemoved');
    await cdp.send('Emulation.addScreen',{left:-1600,top:0,width:1600,height:900,devicePixelRatio:2,label:'Same monitor label'});
    await waitForBrowserValue(page,async()=> (await window.hotplugTest.sdk.displays.list()).length===3);
    const replacement=await page.evaluate(async()=>{
      const {sdk,selected,observation}=window.hotplugTest;
      let oldError;try{await sdk.get(selected);}catch(error){oldError=error.code;}
      const snapshots=await Promise.all((await sdk.displays.list()).map(entity=>sdk.get(entity)));
      observation.close();sdk.close();
      return {oldError,newLabel:snapshots.find(value=>value.logicalBounds.x===-1600)?.label};
    });
    assert.deepEqual(replacement,{oldError:'EntityRemoved',newLabel:'Same monitor label'});
    assert.deepEqual(uncaught,[]);void duplicate;
  });
  test(`${name}: application-supplied screen details expose per-monitor state and native changes`, {timeout:30000}, async t=>{
    const browser=await chromium.launch({executablePath,headless:true});
    t.after(()=>browser.close());
    const context=await browser.newContext({viewport:null});
    const page=await context.newPage();
    const uncaught=[];page.on('pageerror',error=>uncaught.push(error.message));
    await page.goto(url);await page.waitForFunction(()=>!!window.sdkTest);
    const cdp=await context.newCDPSession(page),{targetInfo}=await cdp.send('Target.getTargetInfo');
    await cdp.send('Browser.setPermission',{permission:{name:'window-management'},setting:'granted',origin:url,browserContextId:targetInfo.browserContextId});
    const {screenInfo}=await cdp.send('Emulation.addScreen',{left:-1600,top:0,width:1600,height:900,devicePixelRatio:2,rotation:90,
      colorDepth:30,label:'Test external monitor',isInternal:false,workAreaInsets:{top:20,bottom:30,left:0,right:0}});
    const initial=await page.evaluate(async()=>{
      const {createWebDeviceAccess,observeWebDisplays}=window.sdkTest;
      const details=await window.getScreenDetails(); // The app, not the SDK, obtains permission-backed data.
      let unexpectedRequests=0;
      window.getScreenDetails=()=>{unexpectedRequests++;throw new Error('SDK must not request screen access');};
      const sdk=createWebDeviceAccess(),observation=observeWebDisplays(sdk,window,details);
      const entities=await sdk.displays.list();
      const snapshots=await Promise.all(entities.map(entity=>sdk.get(entity)));
      const target=entities[snapshots.findIndex(snapshot=>snapshot.label==='Test external monitor')];
      const iterator=sdk.watch(target)[Symbol.asyncIterator]();const first=(await iterator.next()).value;
      const current=await sdk.get(await sdk.displays.current());
      window.displayTest={sdk,observation,details,target,iterator};
      return {count:entities.length,label:first.label,primary:first.primary,internal:first.internal,
        bounds:first.logicalBounds,work:first.workAreaBounds,pixels:first.pixelSize,scale:first.scaleFactor,depth:first.colorDepthBits,
        orientation:first.orientation,rotation:first.rotationDegrees,physical:first.physicalSizeMillimeters,
        currentIsPrimary:current.primary,currentOrientation:current.orientation,unexpectedRequests};
    });
    assert.deepEqual(initial,{count:2,label:'Test external monitor',primary:false,internal:false,
      bounds:{x:-1600,y:0,width:800,height:450},work:{x:-1600,y:10,width:800,height:425},pixels:{width:1600,height:900},scale:2,depth:30,
      orientation:null,rotation:null,physical:null,currentIsPrimary:true,currentOrientation:'LandscapePrimary',unexpectedRequests:0});
    await cdp.send('Emulation.updateScreen',{screenId:screenInfo.id,label:'Renamed external monitor',workAreaInsets:{top:40,bottom:20,left:0,right:0}});
    const changed=await page.evaluate(async()=>{
      const {iterator,sdk,observation}=window.displayTest;
      let snapshot;do{snapshot=(await iterator.next()).value;}while(snapshot.label!=='Renamed external monitor');
      await iterator.return();observation.close();sdk.close();
      return {label:snapshot.label,work:snapshot.workAreaBounds};
    });
    assert.deepEqual(changed,{label:'Renamed external monitor',work:{x:-1600,y:20,width:800,height:420}});
    assert.deepEqual(uncaught,[]);
    await mkdir('.tools/evidence',{recursive:true});
    await writeFile(`.tools/evidence/displays-${name.toLowerCase()}.json`,JSON.stringify({browser:name,version:browser.version(),date:new Date().toISOString(),initial,changed},null,2));
  });
  test(`${name}: viewport reads consume observed state with partial availability and equal events`, {timeout:30000}, async t=>{
    const browser=await chromium.launch({executablePath,headless:true});
    t.after(()=>browser.close());
    const page=await browser.newPage();
    const uncaught=[];page.on('pageerror',error=>uncaught.push(error.message));
    await page.goto(url);await page.waitForFunction(()=>!!window.sdkTest);
    const result=await page.evaluate(async()=>{
      const {createWebDeviceAccess,observeWebViewport,core}=window.sdkTest;
      const originals=Object.fromEntries(['innerWidth','innerHeight','visualViewport'].map(key=>[key,Object.getOwnPropertyDescriptor(window,key)]));
      const OriginalWorker=window.Worker;let workers=0,reads=0,missing=true;
      window.Worker=class extends OriginalWorker {constructor(...args){super(...args);workers++;}};
      Object.defineProperty(window,'innerWidth',{configurable:true,get(){reads++;if(missing)throw new DOMException('Unavailable','InvalidStateError');return 0;}});
      Object.defineProperty(window,'innerHeight',{configurable:true,get(){return 0;}});
      Object.defineProperty(window,'visualViewport',{configurable:true,value:null});
      const sdk=createWebDeviceAccess();let observation;
      try {
        observation=observeWebViewport(sdk,window);
        const workersAfterAttach=workers,readsAfterAttach=reads;
        const first=await sdk.get(observation.entity);
        const iterator=sdk.withPollInterval(core.Duration.milliseconds(1)).watch(observation.entity)[Symbol.asyncIterator]();
        await iterator.next();await new Promise(resolve=>setTimeout(resolve,20));
        const readsAfterSdkCalls=reads;
        missing=false;window.dispatchEvent(new Event('resize'));
        const next=(await iterator.next()).value;
        window.dispatchEvent(new Event('resize'));
        const equal=(await iterator.next()).value;
        await iterator.return();
        observation.close();const readsAtClose=reads;
        window.dispatchEvent(new Event('resize'));
        const readsAfterClose=reads;
        const replacement=observeWebViewport(sdk,window);
        sdk.close();window.dispatchEvent(new Event('resize'));const afterClosedSdk=reads;
        window.dispatchEvent(new Event('resize'));const detachedAfterClosedSdk=reads===afterClosedSdk;
        replacement.close();
        return {workersAfterAttach,readsAfterAttach,readsAfterSdkCalls,firstSize:first.size,firstVisual:first.visualViewportSize,
          firstScale:first.visualViewportScale,nextSize:next.size,equalSize:equal.size,readsAtClose,readsAfterClose,detachedAfterClosedSdk};
      } finally {
        observation?.close();sdk.close();window.Worker=OriginalWorker;
        for(const [key,descriptor]of Object.entries(originals)){
          if(descriptor)Object.defineProperty(window,key,descriptor);else delete window[key];
        }
      }
    });
    assert.equal(result.workersAfterAttach,0);
    assert.equal(result.readsAfterAttach,1);assert.equal(result.readsAfterSdkCalls,1);
    assert.equal(result.firstSize,null);assert.equal(result.firstVisual,null);assert.equal(result.firstScale,null);
    assert.deepEqual(result.nextSize,{width:0,height:0});assert.deepEqual(result.equalSize,{width:0,height:0});
    assert.equal(result.readsAtClose,result.readsAfterClose);assert.equal(result.detachedAfterClosedSdk,true);
    assert.deepEqual(uncaught,[]);
  });
  test(`${name}: inaccessible windows fail without leaving a discoverable viewport`, {timeout:30000}, async t=>{
    const browser=await chromium.launch({executablePath,headless:true});
    t.after(()=>browser.close());
    const page=await browser.newPage();
    await page.goto(url);await page.waitForFunction(()=>!!window.sdkTest);
    const result=await page.evaluate(async()=>{
      const {createWebDeviceAccess,observeWebViewport,core}=window.sdkTest;
      const sdk=createWebDeviceAccess(),own=observeWebViewport(sdk,window);
      const frame=document.createElement('iframe');frame.src='data:text/html,unowned-window';
      const loaded=new Promise(resolve=>frame.addEventListener('load',resolve,{once:true}));
      document.body.append(frame);await loaded;
      let errorCode;try{observeWebViewport(sdk,frame.contentWindow);}catch(error){errorCode=error.code;}
      const targets=await sdk.list(core.ViewportEntity);
      own.close();sdk.close();
      return {errorCode,count:targets.length};
    });
    assert.deepEqual(result,{errorCode:'PermissionDenied',count:1});
  });
  test(`${name}: viewport observation retires on document navigation and reattachment never revives an old handle`, {timeout:30000}, async t => {
    const browser=await chromium.launch({executablePath,headless:true});
    t.after(()=>browser.close());
    const page=await browser.newPage();
    const uncaught=[];page.on('pageerror',error=>uncaught.push(error.message));
    await page.goto(url);await page.waitForFunction(()=>!!window.sdkTest);
    await page.evaluate(async()=>{
      const {createWebDeviceAccess,observeWebViewport}=window.sdkTest;
      const frame=document.createElement('iframe');frame.name='owned-viewport';frame.width='300';frame.height='200';
      const loaded=new Promise(resolve=>frame.addEventListener('load',resolve,{once:true}));
      document.body.append(frame);await loaded;
      const sdk=createWebDeviceAccess();
      const observation=observeWebViewport(sdk,frame.contentWindow);
      const iterator=sdk.watch(observation.entity)[Symbol.asyncIterator]();
      await iterator.next();
      const outcome=(async()=>{
        try {while(!(await iterator.next()).done) {/* Native resize events may precede pagehide. */}return {ended:true};}
        catch(error){return {code:error.code};}
      })();
      window.navigationTest={sdk,observation,iterator,outcome,frame};
    });
    await page.frame({name:'owned-viewport'}).goto(`${url}/?next-document`);
    const result=await page.evaluate(async()=>{
      const {sdk,observation,outcome,frame}=window.navigationTest;
      const removed=await Promise.race([outcome,new Promise(resolve=>setTimeout(()=>resolve({timedOut:true}),1000))]);
      const next=window.sdkTest.observeWebViewport(sdk,frame.contentWindow);
      const current=await sdk.get(next.entity);
      let oldError;try{await sdk.get(observation.entity);}catch(error){oldError=error.code;}
      observation.close();observation.close();next.close();sdk.close();
      return {removed,oldError,size:current.size};
    });
    assert.deepEqual(result,{removed:{code:'EntityRemoved'},oldError:'EntityRemoved',size:{width:300,height:200}});
    assert.deepEqual(uncaught,[]);
  });
  test(`${name}: application-owned viewport snapshots follow native window and visual viewport resize`, {timeout:30000}, async t => {
    const browser=await chromium.launch({executablePath,headless:true});
    t.after(()=>browser.close());
    const page=await browser.newPage({viewport:{width:800,height:600}});
    const uncaught=[];page.on('pageerror',error=>uncaught.push(error.message));
    await page.goto(url);await page.waitForFunction(()=>!!window.sdkTest);
    const initial=await page.evaluate(async()=>{
      const {createWebDeviceAccess,observeWebViewport}=window.sdkTest;
      const sdk=createWebDeviceAccess();
      const observation=observeWebViewport(sdk,window);
      const iterator=sdk.watch(observation.entity)[Symbol.asyncIterator]();
      const first=(await iterator.next()).value;
      window.viewportTest={sdk,observation,iterator,first};
      return {size:first.size,visual:first.visualViewportSize,scale:first.visualViewportScale,
        safeArea:first.safeAreaInsets,textScale:first.textScaleFactor};
    });
    assert.deepEqual(initial,{size:{width:800,height:600},visual:{width:800,height:600},scale:1,safeArea:null,textScale:null});
    await page.setViewportSize({width:640,height:480});
    const resized=await page.evaluate(async()=>{
      const {iterator,sdk,observation,first}=window.viewportTest;
      let next;
      do {next=(await iterator.next()).value;} while(next.size.width!==640||next.visualViewportSize.width!==640);
      const read=await sdk.get(observation.entity);
      return {size:next.size,visual:next.visualViewportSize,scale:next.visualViewportScale,
        readSize:read.size,oldSize:first.size,frozen:Object.isFrozen(next)&&Object.isFrozen(next.size)};
    });
    assert.deepEqual(resized,{size:{width:640,height:480},visual:{width:640,height:480},scale:1,
      readSize:{width:640,height:480},oldSize:{width:800,height:600},frozen:true});
    const cdp=await page.context().newCDPSession(page);
    await cdp.send('Emulation.setPageScaleFactor',{pageScaleFactor:2});
    const zoomed=await page.evaluate(async()=>{
      const {iterator,sdk,observation}=window.viewportTest;
      let next;
      do {next=(await iterator.next()).value;} while(next.visualViewportScale!==2);
      await iterator.return();observation.close();sdk.close();
      return {size:next.size,visual:next.visualViewportSize,scale:next.visualViewportScale};
    });
    assert.deepEqual(zoomed,{size:{width:640,height:480},visual:{width:320,height:240},scale:2});
    assert.deepEqual(uncaught,[]);
    await mkdir('.tools/evidence',{recursive:true});
    await writeFile(`.tools/evidence/viewport-${name.toLowerCase()}.json`,JSON.stringify({browser:name,version:browser.version(),date:new Date().toISOString(),initial,resized,zoomed},null,2));
  });
  test(`${name}: real worker values, observer delivery, cancellation and host responsiveness`, {timeout:30000}, async t => {
    const browser = await chromium.launch({executablePath,headless:true});
    t.after(() => browser.close());
    const page = await browser.newPage();
    const uncaught=[];page.on('pageerror', error => uncaught.push(error.message));
    await page.goto(url);await page.waitForFunction(() => !!window.sdkTest);
    const results = await page.evaluate(async () => {
      const {core,createWebDeviceAccess}=window.sdkTest;
      const {CpuEntity,RamEntity,OsEntity,RuntimeEntity,LocaleEntity,TimeZoneEntity,OriginStorageEntity,
        NetworkPerformanceEntity,DisplayEntity,AndroidIdentityEntity,PermissionStatus,Duration}=core;
      let workerCount=0,terminated=0;
      const OriginalWorker=window.Worker;
      window.Worker=class extends OriginalWorker {
        constructor(...args){super(...args);workerCount++;}
        terminate(){terminated++;super.terminate();}
      };
      const sdk=createWebDeviceAccess();
      const initialWorkers=workerCount;
      try {
        const cpu=await sdk.get(CpuEntity),ram=await sdk.get(RamEntity),os=await sdk.get(OsEntity),runtime=await sdk.get(RuntimeEntity);
        const locale=await sdk.get(LocaleEntity),timeZone=await sdk.get(TimeZoneEntity),storage=await sdk.get(OriginStorageEntity);
        const network=await sdk.get(NetworkPerformanceEntity);
        let unsupported;
        try{await sdk.get(AndroidIdentityEntity);}catch(error){unsupported=error.code;}
        const display=sdk.observers.target(DisplayEntity,'application-current-screen');
        sdk.observers.publish(display,{pixelSize:{width:window.innerWidth,height:window.innerHeight},label:'app screen'});
        sdk.observers.current(DisplayEntity,display);
        const current=await sdk.displays.current();
        const screen=await sdk.get(current);
        const iterator=sdk.watch(display)[Symbol.asyncIterator]();
        await iterator.next();
        const changed=iterator.next();
        sdk.observers.publish(display,{pixelSize:{width:321,height:654}});
        const update=(await changed).value;
        await iterator.return();
        const releasesAfterLastSubscription=terminated;
        // Reconnect preserves the external observer cache and current selection.
        const afterReconnect=await sdk.get(await sdk.displays.current());
        sdk.observers.permission(DisplayEntity,PermissionStatus.NotDetermined);
        const coordinator=sdk.observers.onPermissionRequest(({entity})=>{
          setTimeout(()=>sdk.observers.permission(entity,PermissionStatus.Granted),80);
        });
        const permission=await sdk.withReadTimeout(Duration.milliseconds(10)).permissions.request(DisplayEntity);
        coordinator();
        const polling=sdk.withPollInterval(Duration.milliseconds(15)).watch(CpuEntity)[Symbol.asyncIterator]();
        const first=(await polling.next()).value,second=(await polling.next()).value;
        await polling.return();
        const blocked=createWebDeviceAccess({workerUrl:new URL('/blocked-worker.js',location.href)})
          .withReadTimeout(Duration.milliseconds(150));
        let ticks=0;const heartbeat=setInterval(()=>ticks++,5);let failure;
        try{await blocked.get(RamEntity);}catch(error){failure=error.code;}
        finally{clearInterval(heartbeat);blocked.close();}
        return {
          initialWorkers,workerCount,releasesAfterLastSubscription,
          cpu:cpu.availableLogicalProcessorCount,expectedCpu:navigator.hardwareConcurrency,physicalCpu:cpu.logicalProcessorCount,
          ram:ram.advertisedBytes?.toString(),expectedRam:BigInt(navigator.deviceMemory*1024**3).toString(),physicalRam:ram.physicalBytes,
          os:os.family,osVersion:os.version,hostArchitecture:runtime.hostArchitecture,
          language:locale.currentLanguageTag,expectedLanguage:navigator.language,
          timezone:timeZone.ianaId,expectedTimezone:Intl.DateTimeFormat().resolvedOptions().timeZone,
          quota:storage.quotaBytes?.toString(),usage:storage.usageBytes?.toString(),persistent:storage.persistent,
          online:network.browserOnline,expectedOnline:navigator.onLine,
          unsupported,screenWidth:screen.pixelSize.width,expectedWidth:innerWidth,
          changedWidth:update.pixelSize.width,reconnectedWidth:afterReconnect.pixelSize.width,
          permission,pollEqual:first.availableLogicalProcessorCount===second.availableLogicalProcessorCount,
          pollTimestampAdvanced:second.collectedAt.epochMilliseconds>first.collectedAt.epochMilliseconds,
          failure,ticks
        };
      } finally {sdk.close();window.Worker=OriginalWorker;}
    });
    assert.equal(results.initialWorkers,0);
    assert.equal(results.cpu,results.expectedCpu);assert.equal(results.physicalCpu,null);
    assert.equal(results.ram,results.expectedRam);assert.equal(results.physicalRam,null);
    assert.equal(results.os,'Windows');assert.equal(results.osVersion,null);
    assert.equal(results.language,results.expectedLanguage);assert.equal(results.timezone,results.expectedTimezone);
    assert.ok(BigInt(results.quota)>0n);assert.ok(BigInt(results.usage)>=0n);assert.equal(typeof results.persistent,'boolean');
    assert.equal(results.online,results.expectedOnline);assert.equal(results.unsupported,'UnsupportedEntity');
    assert.equal(results.screenWidth,results.expectedWidth);assert.equal(results.changedWidth,321);assert.equal(results.reconnectedWidth,321);
    assert.equal(results.permission,'Granted');assert.equal(results.pollEqual,true);assert.equal(results.pollTimestampAdvanced,true);
    assert.ok(results.releasesAfterLastSubscription>=1);assert.equal(results.failure,'ReadTimeout');assert.ok(results.ticks>=3);
    assert.deepEqual(uncaught,[]);
    const evidence={browser:name,version:browser.version(),platform:process.platform,date:new Date().toISOString(),results};
    await mkdir('.tools/evidence',{recursive:true});
    await writeFile(`.tools/evidence/browser-${name.toLowerCase()}.json`,JSON.stringify(evidence,null,2));
    t.diagnostic(`${name} ${browser.version()}: host ticks during blocked worker=${results.ticks}`);
  });
}
