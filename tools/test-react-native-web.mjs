import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {resolve, sep, extname} from 'node:path';
import {chromium} from 'playwright-core';

const root = resolve('.tools/react-native-web-app');
const buildMode = JSON.parse(await readFile(resolve(root, 'build-mode.json'), 'utf8'));
const temp = resolve('.tools/react-native-web-browser-temp');
await mkdir(temp, {recursive: true});
process.env.TEMP = temp; process.env.TMP = temp;
const server = createServer(async (request, response) => {
  try {
    const pathname = new URL(request.url, 'http://localhost').pathname;
    if (pathname === '/held-worker.js') {
      response.setHeader('Content-Type', 'text/javascript');
      response.end(`onmessage=e=>{const r=e.data;if(r.operation==='cancel')return;
        if(r.entity.kind==='Ram'){postMessage({id:0,type:'result',value:{held:true}});const end=performance.now()+800;while(performance.now()<end){}postMessage({id:0,type:'result',value:{released:true}});}
        postMessage({id:r.id,type:'result',value:{collectedAt:new Date().toISOString(),availableLogicalProcessorCount:2,physicalBytes:0n}});};`);
      return;
    }
    const file = resolve(root, '.' + (pathname === '/' ? '/index.html' : decodeURIComponent(pathname)));
    if (!file.startsWith(root + sep)) {response.writeHead(403).end(); return;}
    response.setHeader('Content-Type', extname(file) === '.js' ? 'text/javascript' : 'text/html');
    response.end(await readFile(file));
  } catch {response.writeHead(404).end();}
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
test.after(() => new Promise(resolve => server.close(resolve)));
const url = `http://127.0.0.1:${server.address().port}`;
async function until(read, predicate) {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {const value = await read(); if (predicate(value)) return value; await new Promise(resolve => setTimeout(resolve, 20));}
  throw Error('The RN Web application did not reach the expected state.');
}

for (const [name, executablePath] of [
  ['Chrome', 'C:/Program Files/Google/Chrome/Application/chrome.exe'],
  ['Edge', 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'],
]) test(`${name}: React Native Web application imports, observes and releases the SDK`, {timeout: 30000}, async t => {
  const browser = await chromium.launch({executablePath, headless: true});
  t.after(() => browser.close());
  const page = await browser.newPage({viewport: {width: 1024, height: 768}});
  page.setDefaultTimeout(10000);
  const errors = [], checks = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.addInitScript(() => {
    globalThis.expectedCpu = navigator.hardwareConcurrency;
    globalThis.sdkWorkersCreated = 0; globalThis.sdkWorkersClosed = 0;
    globalThis.heldWorkerStarts = 0; globalThis.heldWorkerEnds = 0;
    const NativeWorker = Worker;
    globalThis.Worker = class extends NativeWorker {
      constructor(...args) {
        super(...args);
        this.sdkOwned = args[1]?.name === 'DeviceReadout';
        if (this.sdkOwned) globalThis.sdkWorkersCreated++;
        this.addEventListener('message', event => {
          if (event.data?.id === 0 && event.data.value?.held) globalThis.heldWorkerStarts++;
          if (event.data?.id === 0 && event.data.value?.released) globalThis.heldWorkerEnds++;
        });
      }
      terminate() {if (this.sdkOwned) globalThis.sdkWorkersClosed++; return super.terminate();}
    };
    Object.defineProperty(navigator, 'hardwareConcurrency', {get() {throw Error('SDK read the host CPU getter.');}});
  });
  await page.goto(url);
  await page.waitForFunction(() => document.querySelector('[data-testid="status"]')?.textContent === 'Ready');
  assert.equal(await page.getByTestId('viewport').textContent(), '1024 × 768');
  assert.equal(await page.getByTestId('framework-size').textContent(), '1024 × 768');
  assert.equal(await page.getByTestId('cpu').textContent(), String(await page.evaluate(() => globalThis.expectedCpu)));
  const initial = await page.evaluate(async () => {
    const example = globalThis.readoutWebExample;
    return {snapshot: await example.snapshot(), created: globalThis.sdkWorkersCreated};
  });
  assert.deepEqual(initial.snapshot.size, {width: 1024, height: 768});
  assert.equal(initial.snapshot.textScaleFactor, null, 'RN Web hardcodes fontScale and cannot report system text scale.');
  assert.equal(initial.created, 1);
  checks.push('rendered typed browser values and one shared owned worker');
  await page.setViewportSize({width: 840, height: 620});
  await page.waitForFunction(() => document.querySelector('[data-testid="viewport"]')?.textContent === '840 × 620');
  assert.equal(await page.getByTestId('framework-size').textContent(), '840 × 620');
  checks.push('actual browser resize reaches RN Dimensions and SDK snapshots');
  assert.equal(await page.evaluate(() => globalThis.readoutWebExample.startSensor()), 'App rotation');
  const state = () => page.evaluate(() => globalThis.readoutWebExample.state());
  const active = await until(state, value => value.samples >= 2);
  assert.deepEqual(active.last, {x: 0, y: 0, z: 0.6, w: 0.8});
  // This is a controlled platform visibility event, consumed by real RN AppState.
  await page.evaluate(() => {
    globalThis.savedVisibility = Object.getOwnPropertyDescriptor(document, 'visibilityState');
    Object.defineProperty(document, 'visibilityState', {configurable: true, value: 'hidden'});
    document.dispatchEvent(new Event('visibilitychange'));
  });
  const inactive = await until(state, value => value.appState === 'background' && value.starts === value.stops);
  const inactiveRead = await page.evaluate(() => globalThis.readoutWebExample.inactiveRead());
  assert.equal(inactiveRead.error, 'ReadTimeout');
  assert.equal(inactiveRead.samples, inactive.samples);
  assert.equal(inactiveRead.starts, inactive.starts);
  assert.equal(inactiveRead.cpu, await page.evaluate(() => globalThis.expectedCpu));
  await page.evaluate(() => {
    if (globalThis.savedVisibility) Object.defineProperty(document, 'visibilityState', globalThis.savedVisibility);
    else delete document.visibilityState;
    document.dispatchEvent(new Event('visibilitychange'));
  });
  const resumed = await until(state, value => value.appState === 'active' && value.samples > inactive.samples && value.starts > inactive.starts);
  assert.deepEqual(resumed.errors, []);
  checks.push('RN AppState notifications suspend and resume an app sensor source');
  const permission = await page.evaluate(() => globalThis.readoutWebExample.permission());
  assert.equal(permission.denied, 'PermissionDenied'); assert.equal(permission.status, 'Denied');
  assert.equal(permission.implicit, 0); assert.equal(permission.requests, 1); assert.equal(permission.granted, 'Granted');
  assert.ok(permission.elapsed >= 100);
  assert.deepEqual(permission.value, {x: 0, y: 0, z: 0.6, w: 0.8});
  checks.push('permission observations and explicit coordination remain app-owned');
  const heartbeat = Number(await page.getByTestId('heartbeat').textContent());
  const held = await page.evaluate(() => globalThis.readoutWebExample.heldWorker());
  assert.equal(held.error, 'ReadTimeout'); assert.ok(held.frames >= 2 && held.ticks >= 3 && held.elapsed < 600);
  assert.deepEqual(await page.evaluate(() => [globalThis.heldWorkerStarts, globalThis.heldWorkerEnds]), [1, 0]);
  assert.ok(Number(await page.getByTestId('heartbeat').textContent()) > heartbeat);
  checks.push('React rendering and host tasks continue during a held collection worker');
  const retired = await page.evaluate(() => globalThis.readoutWebExample.retireViewport());
  assert.deepEqual(retired, {error: 'EntityRemoved', count: 0});
  checks.push('disposed viewport handles are retired without replacement');
  await page.evaluate(() => globalThis.unmountReadoutWebExample());
  await page.waitForFunction(() => !globalThis.readoutWebExample && globalThis.sdkWorkersClosed === globalThis.sdkWorkersCreated);
  const lifetime = await page.evaluate(() => ({created: globalThis.sdkWorkersCreated, closed: globalThis.sdkWorkersClosed}));
  checks.push('React unmount releases observations and its owned worker');
  assert.deepEqual(errors, []);
  await mkdir('.tools/evidence', {recursive: true});
  await writeFile(`.tools/evidence/react-native-web-${name.toLowerCase()}.json`, JSON.stringify({browser: browser.version(), ...buildMode, initial, active, inactive, resumed, permission, held, retired, lifetime, checks, passed: true}, null, 2));
  t.diagnostic(`${checks.length} React Native Web application scenarios passed.`);
});
