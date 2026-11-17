import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import {resolve,sep,extname} from 'node:path';
import {chromium} from 'playwright-core';
import {setTimeout as delay} from 'node:timers/promises';

async function until(read,predicate){
  const end=Date.now()+10000;let last;
  do { last=await read();if(predicate(last))return last;await delay(25); } while(Date.now()<end);
  assert.fail(`Consumer state did not settle: ${JSON.stringify(last)}`);
}

const installed=process.env.DEVICE_READOUT_FLUTTER_INSTALLED==='1';
const appRoot=installed?'.tools/flutter-web-installed':'flutter/device_readout_flutter/example';
const evidencePrefix=installed?'flutter-installed-browser':'flutter-browser';
const buildRoot=resolve(appRoot,'build/web');
const contractRoot=resolve(appRoot,'build/web-contracts');
const temp=resolve('.tools/flutter-browser-temp');
await mkdir(temp,{recursive:true});process.env.TEMP=temp;process.env.TMP=temp;
const heldWorker=`onmessage=e=>{const r=e.data;if(r.operation==='cancel')return;
 if(r.entity.kind==='Ram'){
  postMessage({id:0,type:'result',value:{phase:'held'}});
  const end=performance.now()+800;while(performance.now()<end){}
  postMessage({id:0,type:'result',value:{phase:'released'}});
 }
 postMessage({id:r.id,type:'result',value:{collectedAt:new Date().toISOString(),availableLogicalProcessorCount:2,physicalBytes:'4096'}});
};`;
const server=createServer(async(request,response)=>{
  try{
    const path=new URL(request.url,'http://localhost').pathname;
    if(path==='/held-worker.js'){response.setHeader('Content-Type','text/javascript');response.end(heldWorker);return;}
    const root=path.startsWith('/contracts/')?contractRoot:buildRoot;
    const relative=path.startsWith('/contracts/')?path.slice('/contracts'.length):path;
    const file=resolve(root,'.'+(relative==='/'?'/index.html':decodeURIComponent(relative)));
    if(!file.startsWith(root+sep)){response.writeHead(403).end();return;}
    response.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.wasm':'application/wasm','.json':'application/json'})[extname(file)]??'application/octet-stream');
    response.end(await readFile(file));
  }catch{response.writeHead(404).end();}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
test.after(()=>new Promise(resolve=>server.close(resolve)));
const url=`http://127.0.0.1:${server.address().port}`;
for(const [name,executablePath] of [
  ['Chrome','C:/Program Files/Google/Chrome/Application/chrome.exe'],
  ['Edge','C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'],
])test(`${name}: Flutter example renders observed viewport values`,{timeout:60000},async t=>{
  const browser=await chromium.launch({executablePath,headless:true});t.after(()=>browser.close());
  const page=await browser.newPage({viewport:{width:1024,height:768}});
  page.setDefaultTimeout(15000);page.setDefaultNavigationTimeout(15000);
  const errors=[];page.on('pageerror',error=>errors.push(error.message));
  await page.goto(url);
  await page.locator('flt-semantics-placeholder').evaluate(element=>element.click());
  await page.waitForFunction(()=>/화면 크기:|조회 오류:/.test(document.body.innerText));
  const text=await page.locator('body').innerText();
  await mkdir('.tools/evidence',{recursive:true});
  await writeFile(`.tools/evidence/${evidencePrefix}-demo-${name.toLowerCase()}.json`,JSON.stringify({installed,browser:browser.version(),text,errors},null,2));
  assert.deepEqual(errors,[]);
  assert.match(text,/화면 크기: 1024(?:\.0)? × 768(?:\.0)?/);
  assert.doesNotMatch(text,/조회 오류:/);
  await page.setViewportSize({width:840,height:620});
  await page.waitForFunction(()=>/화면 크기: 840(?:\.0)? × 620(?:\.0)?/.test(document.body.innerText));
  t.diagnostic('Rendered initial and resized viewport values.');
});

for(const [name,executablePath] of [
  ['Chrome','C:/Program Files/Google/Chrome/Application/chrome.exe'],
  ['Edge','C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'],
])test(`${name}: Flutter application uses typed reads and framework observers`,{timeout:60000},async t=>{
  const browser=await chromium.launch({executablePath,headless:true});t.after(()=>browser.close());
  const context=await browser.newContext({viewport:{width:1024,height:768},deviceScaleFactor:2});
  const page=await context.newPage();const errors=[];page.on('pageerror',error=>errors.push(error.message));
  // Playwright enables always-focused emulation by default. Disable it only
  // on this owned test page so native tab activation can change app lifecycle.
  const cdp=await context.newCDPSession(page);
  await cdp.send('Emulation.setFocusEmulationEnabled',{enabled:false});
  page.setDefaultTimeout(15000);page.setDefaultNavigationTimeout(15000);
  await page.addInitScript(()=>{
    globalThis.sdkWorkersCreated=0;globalThis.sdkWorkersClosed=0;
    globalThis.nativeLifecycleEvents=[];
    for(const type of ['focus','blur'])addEventListener(type,e=>globalThis.nativeLifecycleEvents.push({type,trusted:e.isTrusted,focus:document.hasFocus(),visibility:document.visibilityState}));
    document.addEventListener('visibilitychange',e=>globalThis.nativeLifecycleEvents.push({type:e.type,trusted:e.isTrusted,focus:document.hasFocus(),visibility:document.visibilityState}));
    globalThis.heldStarts=0;globalThis.heldEnds=0;
    const NativeWorker=Worker;
    globalThis.Worker=class extends NativeWorker{
      constructor(url,options){super(url,options);this.sdk=options?.name==='DeviceReadout Dart';if(this.sdk){
        globalThis.sdkWorkersCreated++;
        this.addEventListener('message',e=>{
          if(e.data?.id===0&&e.data.value?.phase==='held')globalThis.heldStarts++;
          if(e.data?.id===0&&e.data.value?.phase==='released')globalThis.heldEnds++;
        });
      }}
      terminate(){if(this.sdk)globalThis.sdkWorkersClosed++;return super.terminate();}
    };
  });
  await page.goto(`${url}/contracts/`);
  await page.waitForFunction(()=>globalThis.flutterReadoutReady===true);
  await cdp.send('Emulation.setFocusEmulationEnabled',{enabled:false});
  const command=name=>page.evaluate(name=>globalThis.flutterReadoutCommand(name),name);
  const expected=await page.evaluate(()=>({cpu:navigator.hardwareConcurrency,language:navigator.language,
    width:innerWidth,height:innerHeight,screenWidth:screen.width*devicePixelRatio,screenHeight:screen.height*devicePixelRatio,scale:devicePixelRatio}));
  assert.equal(await page.evaluate(()=>globalThis.sdkWorkersCreated),0,'Attaching observers is inert.');
  const initial=await command('snapshot');const checks=[];
  assert.equal(initial.cpu.availableLogicalProcessorCount,expected.cpu);
  assert.equal(initial.locale.currentLanguageTag,expected.language);
  assert.deepEqual(initial.viewport.size,{width:expected.width,height:expected.height});
  assert.equal(initial.display.pixelSize,null,'Flutter web exposes cached CSS screen dimensions, not a physical pixel mode.');
  assert.equal(initial.display.scaleFactor,expected.scale);
  assert.equal(initial.display.currentMode,null);
  assert.ok(initial.currentIsListed&&initial.viewportIsCurrent&&initial.readable&&initial.watchable);
  checks.push('typed browser reads and app-owned viewport/display discovery');
  await command('watchViewport');await page.setViewportSize({width:840,height:620});
  await until(()=>command('state'),state=>{
    return state.viewportValues.at(-1)?.size?.width===840&&state.viewportValues.at(-1)?.size?.height===620;
  });
  const stopped=await command('stopViewport');
  await page.setViewportSize({width:900,height:640});
  // A browser resize notification precedes Flutter's next layout/paint. Wait
  // for the rendered root to settle before attaching a fresh view observer.
  await page.waitForFunction(()=>{
    const rect=document.querySelector('flutter-view')?.getBoundingClientRect();
    return rect?.width===900&&rect?.height===640;
  });
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  await until(()=>command('snapshot'),state=>state.viewport.size.width===900);
  assert.equal((await command('state')).viewportValues.length,stopped.viewportValues.length);
  const retired=await command('retireViewport');
  assert.equal(retired.oldError,'entityRemoved');assert.equal(retired.freshHandle,true);assert.equal(retired.count,1);
  assert.deepEqual(retired.fresh.size,{width:900,height:640});
  checks.push('actual browser resize, stream cancellation and retired view handles');
  await page.bringToFront();await page.mouse.click(300,300);
  await until(()=>command('state'),state=>state.lifecycle==='resumed');
  const active=await command('startSensor');
  assert.equal(active.metadataStartedSources,0);
  assert.equal(active.description.kind,'RelativeOrientation');
  assert.ok(Math.abs(active.lastSample.value.z-0.6)<1e-15&&Math.abs(active.lastSample.value.w-0.8)<1e-15);
  const other=await context.newPage();
  const otherCdp=await context.newCDPSession(other);
  await other.goto('about:blank');
  await otherCdp.send('Emulation.setFocusEmulationEnabled',{enabled:false});
  await other.bringToFront();
  const switchState=await page.evaluate(()=>({focus:document.hasFocus(),visibility:document.visibilityState,events:globalThis.nativeLifecycleEvents}));
  t.diagnostic(`Native tab activation: ${JSON.stringify(switchState)}`);
  await until(()=>command('state'),state=>{
    return state.lifecycle!=='resumed'&&state.sensorStops===state.sensorStarts;
  });
  const inactive=await command('state');
  const suspended=await command('inactiveRead');
  const focusState=await page.evaluate(()=>({focus:document.hasFocus(),visibility:document.visibilityState}));
  await writeFile(`.tools/evidence/${evidencePrefix}-lifecycle-${name.toLowerCase()}.json`,JSON.stringify({installed,active,inactive,suspended,focusState},null,2));
  assert.equal(suspended.error,'readTimeout',JSON.stringify({inactive,suspended,focusState}));assert.equal(suspended.samples,inactive.samples);
  assert.equal(suspended.sensorStarts,inactive.sensorStarts);
  await page.bringToFront();await page.mouse.click(300,300);
  await until(()=>command('state'),state=>state.lifecycle==='resumed'&&state.sensorStarts>=2&&state.samples>inactive.samples);
  await other.close();
  const resumed=await command('state');assert.deepEqual(resumed.sensorErrors,[]);
  checks.push('native browser focus lifecycle suspends and resumes app sensor sessions');
  const permission=await command('permission');
  assert.equal(permission.denied,'permissionDenied');assert.equal(permission.status,'denied');
  assert.equal(permission.implicitRequests,0);assert.equal(permission.requested,1);assert.equal(permission.granted,'granted');
  assert.ok(permission.waitedMs>=100);assert.deepEqual(permission.sensorErrors,['permissionDenied']);
  checks.push('app-observed permission denial and explicit coordinator waiting');
  const held=await command('heldWorker');
  assert.equal(held.error,'readTimeout');assert.ok(held.frames>=2&&held.ticks>=3,JSON.stringify(held));
  assert.ok(held.elapsedMs<600,JSON.stringify(held));
  assert.deepEqual(await page.evaluate(()=>({starts:globalThis.heldStarts,ends:globalThis.heldEnds})),{starts:1,ends:0});
  checks.push('Flutter frames and timers continue while a collection worker is held');
  const closed=await command('unmount');assert.equal(closed.closedError,'cancelled');
  const lifetime=await page.evaluate(()=>({created:globalThis.sdkWorkersCreated,closed:globalThis.sdkWorkersClosed}));
  assert.deepEqual(lifetime,{created:2,closed:2});checks.push('widget unmount releases its owned SDK worker');
  assert.deepEqual(errors,[]);
  await writeFile(`.tools/evidence/${evidencePrefix}-contracts-${name.toLowerCase()}.json`,JSON.stringify({installed,browser:browser.version(),expected,initial,active,inactive,resumed,permission,held,lifetime,checks,passed:true},null,2));
  t.diagnostic(`${checks.length} Flutter application scenarios passed.`);
});
