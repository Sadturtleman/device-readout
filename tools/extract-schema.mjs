import { readFile, writeFile, mkdir } from 'node:fs/promises';
const spec = await readFile(new URL('../docs/design.ko.md', import.meta.url), 'utf8');
const entities = [];
const targeted = new Set(['CpuCore', 'TelephonyIdentity', 'Display', 'Viewport', 'Battery', 'NetworkInterface', 'WifiConnection', 'CellularSubscription', 'StorageVolume']);
for (const match of spec.matchAll(/^### (\w+)Entity\n([\s\S]*?)(?=^#{1,3} |$(?![\s\S]))/gm)) {
  const name = match[1];
  const fields = [...match[2].matchAll(/^\| `(\w+)` \| `([^`]+)` \| ([^\n]+) \|$/gm)]
    .map(([, name, type, description]) => ({name, type, description}));
  if (!fields.length) throw new Error(`No fields: ${name}`);
  entities.push({name, targeted: targeted.has(name), mode: 'state', fields});
}
const sensorSection = spec.split('# 센서 계약\n')[1].split('## 센서 메타데이터')[0];
for (const [, name, type, unit, description] of sensorSection.matchAll(/^\| `(\w+)Entity` \| `([^`]+)` \| ([^|]+) \| ([^\n]+) \|$/gm)) {
  entities.push({name, targeted: true, mode: ['StepDetected', 'SignificantMotion'].includes(name) ? 'event' : 'sample', fields: [{name:'value', type, unit:unit.trim(), description}]});
}
const metadata = spec.split('## 센서 메타데이터\n')[1].split('## 플랫폼 기본값')[0];
const sensorDescription = [...metadata.matchAll(/^\| `(\w+)` \| `([^`]+)` \| ([^\n]+) \|$/gm)].map(([,name,type,description])=>({name,type,description}));
if (entities.length !== 46 || new Set(entities.map(x=>x.name)).size !== 46) throw new Error(`Expected 46 distinct entities, found ${entities.length}`);
const schema = {schemaVersion:1, version:'0.1.0', source:'docs/design.ko.md', defaults:{pollIntervalMs:1000,readTimeoutMs:5000,sensorSamplingRate:'PlatformDefault'}, entities, sensorDescription};
await mkdir(new URL('../schema/', import.meta.url), {recursive:true});
await writeFile(new URL('../schema/device-readout.json', import.meta.url), JSON.stringify(schema,null,2)+'\n');
console.log(`Extracted ${entities.length} entities and ${entities.reduce((n,e)=>n+e.fields.length,0)} fields.`);
