import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import {resolve,sep,extname} from 'node:path';
import {chromium} from 'playwright-core';

const root=resolve('.');
const temp=resolve('.tools/dart-browser-temp');
await mkdir(temp,{recursive:true});process.env.TEMP=temp;process.env.TMP=temp;
const pacedWorker=`
import '/packages/web/dist/dart-worker.js';
const send=globalThis.postMessage.bind(globalThis);
globalThis.postMessage=(value,...args)=>{
 if(value.type==='snapshot')send({id:0,type:'result',value:{fixture:'paced-snapshot'}});
 if(value.type==='error')send({id:0,type:'result',value:{fixture:'paced-error'}});
 return send(value,...args);
};
addEventListener('message',event=>{
 if(event.data.operation==='watch'&&event.data.entity?.kind==='Locale')setTimeout(()=>{
  const count=new URL(location.href).searchParams.has('burst')?3000:2;
  for(let i=0;i<count;i++)dispatchEvent(new Event('languagechange'));
 },20);
});`;
const heldWorker=`
const stamp=value=>({collectedAt:new Date().toISOString(),...value});
const phase=value=>postMessage({id:0,type:'result',value:{fixture:value}});
const hold=()=>{phase('held');const end=performance.now()+500;while(performance.now()<end){}phase('released');};
onmessage=event=>{
 const r=event.data;if(r.operation==='cancel')return;
 if(r.operation==='watch'){
   postMessage({id:r.id,type:'reading'});postMessage({id:r.id,type:'snapshot',value:stamp({availableLogicalProcessorCount:2})});
   setTimeout(()=>{postMessage({id:r.id,type:'reading'});hold();postMessage({id:r.id,type:'snapshot',probeStale:true,value:stamp({availableLogicalProcessorCount:2})});},30);return;
 }
 if(r.entity.kind==='Ram'){hold();postMessage({id:r.id,type:'result',probeStale:true,value:stamp({physicalBytes:'18446744073709551615'})});return;}
 if(r.entity.kind==='OriginStorage'){postMessage({id:r.id,type:'result',value:stamp({quotaBytes:'18446744073709551615',usageBytes:'0',persistent:false,usageByCategory:{Caches:'0'}})});return;}
 postMessage({id:r.id,type:'result',value:stamp({availableLogicalProcessorCount:2})});
};`;
const slowDeliveryWorker=`
const value=()=>({collectedAt:new Date().toISOString(),availableLogicalProcessorCount:2,physicalBytes:'0'});
onmessage=e=>{const r=e.data;if(r.operation==='cancel')return;
 if(r.operation==='watch'){
  postMessage({id:r.id,type:'reading'});postMessage({id:r.id,type:'snapshot',value:value()});
  setTimeout(()=>{postMessage({id:r.id,type:'reading'});postMessage({id:r.id,type:'snapshot',slowDelivery:true,value:value()});},30);
 }else postMessage({id:r.id,type:'result',slowDelivery:r.entity.kind==='Ram',value:value()});
};`;
const largeWorker=`
onmessage=e=>{const r=e.data;if(r.operation==='cancel')return;
 if(r.operation==='list'){postMessage({id:r.id,type:'result',value:['screen']});return;}
 if(r.entity.kind==='Cpu'){postMessage({id:r.id,type:'result',value:{collectedAt:new Date().toISOString(),availableLogicalProcessorCount:2}});return;}
 const large={collectedAt:new Date().toISOString(),label:'large',primary:false,
  supportedModes:Array.from({length:12000},(_,i)=>({pixelSize:{width:1920,height:1080},refreshRateHz:i}))};
 if(r.operation==='watch'){
  postMessage({id:r.id,type:'reading'});postMessage({id:r.id,type:'snapshot',largeDelivery:true,value:large});
  const small={collectedAt:large.collectedAt,label:'small',primary:false,supportedModes:[]};
  for(let i=0;i<2;i++){postMessage({id:r.id,type:'reading'});postMessage({id:r.id,type:'snapshot',value:small});}
  postMessage({id:r.id,type:'end'});return;
 }
 postMessage({id:r.id,type:'result',largeDelivery:true,value:large});
};`;
const server=createServer(async(request,response)=>{
  try {
    const path=new URL(request.url,'http://localhost').pathname;
    if(path==='/paced-worker.js'){response.setHeader('Content-Type','text/javascript');response.end(pacedWorker);return;}
    if(path==='/held-worker.js'){response.setHeader('Content-Type','text/javascript');response.end(heldWorker);return;}
    if(path==='/slow-delivery-worker.js'){response.setHeader('Content-Type','text/javascript');response.end(slowDeliveryWorker);return;}
    if(path==='/large-worker.js'){response.setHeader('Content-Type','text/javascript');response.end(largeWorker);return;}
    if(path==='/malformed-worker.js'){response.setHeader('Content-Type','text/javascript');response.end("onmessage=e=>postMessage({id:e.data.id,type:'error',error:7});");return;}
    if(path==='/'){
      response.setHeader('Content-Type','text/html');
      response.end('<!doctype html><title>Dart DeviceReadout contracts</title><script src="/.tools/dart-checks/browser-contracts.js" defer></script>');return;
    }
    const file=resolve(root,'.'+decodeURIComponent(path));
    if(!file.startsWith(root+sep)){response.writeHead(403).end();return;}
    response.setHeader('Content-Type',extname(file)==='.js'?'text/javascript':'application/octet-stream');
    response.end(await readFile(file));
  }catch{response.writeHead(404).end();}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
test.after(()=>new Promise(resolve=>server.close(resolve)));
const url=`http://127.0.0.1:${server.address().port}`;
for(const [name,executablePath] of [
  ['Chrome','C:/Program Files/Google/Chrome/Application/chrome.exe'],
  ['Edge','C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'],
])test(`${name}: compiled Dart SDK uses actual web workers`,{timeout:60000},async t=>{
  const browser=await chromium.launch({executablePath,headless:true});t.after(()=>browser.close());
  const page=await browser.newPage();const errors=[];page.on('pageerror',error=>errors.push(error.message));
  await page.addInitScript(()=>{
    globalThis.workersCreated=0;globalThis.workersClosed=0;
    globalThis.pacedSnapshots=0;
    globalThis.pacedErrors=0;
    globalThis.heldOperations=0;globalThis.releasedOperations=0;
    globalThis.latePayloadReads=0;
    globalThis.slowPayloadReads=0;
    globalThis.largePayloadYielded=false;
    globalThis.largePayloadStarts=0;globalThis.largePayloadEnds=0;
    globalThis.largePayloadAction=null;
    globalThis.outboundHostTurn=false;globalThis.outboundYielded=false;
    globalThis.expectedCpuCount=navigator.hardwareConcurrency;
    const NativeWorker=Worker;
    globalThis.Worker=class extends NativeWorker{
      constructor(...args){super(...args);globalThis.workersCreated++;this.addEventListener('message',e=>{
        if(e.data?.id===0&&e.data.value?.fixture==='paced-snapshot')globalThis.pacedSnapshots++;
        if(e.data?.id===0&&e.data.value?.fixture==='paced-error')globalThis.pacedErrors++;
        if(e.data?.id===0&&e.data.value?.fixture==='held')globalThis.heldOperations++;
        if(e.data?.id===0&&e.data.value?.fixture==='released')globalThis.releasedOperations++;
        if(e.data?.probeStale)Object.defineProperty(e.data,'value',{enumerable:true,get(){globalThis.latePayloadReads++;throw Error('Retired response payload must not be traversed.');}});
        if(e.data?.slowDelivery){const value=e.data.value;Object.defineProperty(e.data,'value',{enumerable:true,get(){globalThis.slowPayloadReads++;const end=performance.now()+200;while(performance.now()<end){}return value;}});}
        if(e.data?.largeDelivery){
          const modes=e.data.value.supportedModes,last=modes.at(-1);let yielded=false;
          globalThis.largePayloadStarts++;
          setTimeout(()=>{yielded=true;globalThis.largePayloadAction?.();},0);
          Object.defineProperty(modes,modes.length-1,{enumerable:true,get(){globalThis.largePayloadEnds++;globalThis.largePayloadYielded=yielded;return last;}});
        }
      });}
      postMessage(value,...args){
        if(value.operation==='normalize'&&value.value?.snapshot?.supportedModes?.length===12000)globalThis.outboundYielded=globalThis.outboundHostTurn;
        return super.postMessage(value,...args);
      }
      terminate(){globalThis.workersClosed++;return super.terminate();}
    };
    Object.defineProperty(navigator,'hardwareConcurrency',{get(){throw Error('SDK queried the UI navigator.');}});
  });
  await page.goto(url);await page.waitForFunction(()=>!!globalThis.deviceReadoutWebReport,null,{timeout:45000});
  const report=await page.evaluate(()=>globalThis.deviceReadoutWebReport);
  await mkdir('.tools/evidence',{recursive:true});
  await writeFile(`.tools/evidence/dart-browser-${name.toLowerCase()}.json`,JSON.stringify({browser:browser.version(),...report},null,2));
  assert.deepEqual(errors,[]);assert.equal(report.passed,true,JSON.stringify(report));
  assert.ok(report.checks.length>0);t.diagnostic(`${report.checks.length} Dart browser scenarios passed.`);
});
