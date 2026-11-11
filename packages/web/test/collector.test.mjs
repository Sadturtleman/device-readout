import test from 'node:test';
import assert from 'node:assert/strict';
import {BrowserCollector} from '../../../.tools/test/browser-collector.mjs';

const settings={pollIntervalMs:1000,readTimeoutMs:5000,sensorHertz:null};
function collector(navigator={}) {
  const environment=Object.assign(new EventTarget(),{navigator});
  const source=new BrowserCollector(environment);
  return {source,environment,read:kind=>source.read({kind},new AbortController().signal,settings)};
}

test('browser performance converts Mbps and RTT without treating online as internet validation',async()=>{
  const connection=Object.assign(new EventTarget(),{downlink:1.25,rtt:0,effectiveType:'4g',saveData:false});
  const {read}=collector({connection,onLine:false});
  assert.deepEqual(await read('NetworkPerformance'),{browserOnline:false,downlinkBps:1250000,roundTripTime:0,effectiveType:'Type4G'});
  assert.deepEqual(await read('NetworkPath'),{saveData:false});
});

test('device hints never turn browser brands or desktop-class form factors into physical device claims',async()=>{
  const {read}=collector({userAgentData:{platform:'Windows',brands:[{brand:'Chromium',version:'100'}],
    async getHighEntropyValues(){return {architecture:'x86',bitness:'64',model:'',formFactors:['Desktop']};}}});
  assert.deepEqual(await read('DeviceInfo'),{modelCode:null,formFactor:null});
  assert.deepEqual(await read('Os'),{family:'Windows',name:'Windows'});
  assert.deepEqual(await read('Runtime'),{hostArchitecture:'X64'});
});

test('unknown storage categories invalidate the whole category map and unavailable fields stay absent',async()=>{
  const {read}=collector({storage:{async estimate(){return {quota:1,usage:0,usageDetails:{indexedDB:0,futureCache:1}};},async persisted(){return false;}}});
  assert.deepEqual(await read('OriginStorage'),{quotaBytes:1,usageBytes:0,usageByCategory:null,persistent:false});
  const partial=collector({storage:{async estimate(){throw Error('denied');},async persisted(){return false;}}});
  assert.equal((await partial.read('OriginStorage')).persistent,false);
  const failed=collector({storage:{async estimate(){throw Error('denied');},async persisted(){throw Error('denied');}}});
  await assert.rejects(failed.read('OriginStorage'),{code:'ReadFailed'});
});

test('native worker network notifications deliver duplicates and detach all event listeners',async()=>{
  const connection=Object.assign(new EventTarget(),{downlink:0,rtt:0,effectiveType:'future',saveData:true});
  const {source,environment}=collector({connection,onLine:true});
  const emissions=[];
  const detach=source.observe({kind:'NetworkPerformance'},v=>emissions.push(v),assert.fail,new AbortController().signal,settings);
  connection.dispatchEvent(new Event('change'));connection.dispatchEvent(new Event('change'));
  environment.dispatchEvent(new Event('offline'));
  assert.equal(emissions.length,3);assert.equal(emissions[0].effectiveType,null);
  detach();connection.dispatchEvent(new Event('change'));environment.dispatchEvent(new Event('online'));
  assert.equal(emissions.length,3);assert.equal(source.pollingRequired({kind:'NetworkPerformance'}),false);
  assert.equal(source.pollingRequired({kind:'Ram'}),true);
});

test('missing APIs report unsupported and do not return a successful all-null placeholder',async()=>{
  const {source,read}=collector();
  assert.equal(source.supports({kind:'Ram'}),false);
  await assert.rejects(read('Ram'),{code:'UnsupportedEntity'});
  await assert.rejects(read('AndroidIdentity'),{code:'UnsupportedEntity'});
});
