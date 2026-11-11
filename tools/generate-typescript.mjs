import { readFile, writeFile } from 'node:fs/promises';
const root = new URL('../',import.meta.url);
const schema = JSON.parse(await readFile(new URL('schema/device-readout.json',root),'utf8'));
const enums = JSON.parse(await readFile(new URL('schema/enums.json',root),'utf8'));
enums.SensorKind = schema.entities.filter(e=>e.mode!=='state').map(e=>e.name);
function type(value) {
  if(value.endsWith('?')) return type(value.slice(0,-1))+' | null';
  if(value.startsWith('List<')) return 'ReadonlyArray<'+type(value.slice(5,-1))+'>';
  if(value.startsWith('Set<')) return 'ReadonlySet<'+type(value.slice(4,-1))+'>';
  if(value.startsWith('Map<')) return 'Readonly<Partial<Record<'+value.slice(4,-1).split(',').map(s=>type(s.trim())).join(', ')+'>>>';
  if(value.startsWith('Size<')) return 'Size<'+type(value.slice(5,-1))+'>';
  return ({String:'string',Integer:'number',Number:'number',Ratio:'number',Boolean:'boolean',ByteCount:'bigint',Int64:'bigint'})[value]??value;
}
const enumText=Object.entries(enums).map(([name,values])=>`export enum ${name} {\n${values.map(v=>`  ${v} = '${name.endsWith('ThermalState')?name+'.':''}${v}',`).join('\n')}\n}`).join('\n');
let output=`// Generated from schema/device-readout.json and schema/enums.json.\nimport { defineEntity } from './entity.js';\nimport type { DeviceSnapshot, CalendarId, NumberingSystemId, Size, Rect, Insets, Vector3, Quaternion, DisplayMode, IpAddress, IpAddressInfo, NetworkRoute, Duration } from './structures.js';\n${enumText}\nexport type ThermalState = AndroidThermalState | AppleThermalState;\n`;
output+=`export enum EntityKind {\n${schema.entities.map(e=>`  ${e.name} = '${e.name}',`).join('\n')}\n}\n`;
for(const e of [...schema.entities,{name:'SensorDescription',fields:schema.sensorDescription}]){
 const model=e.name==='SensorDescription'?e.name:e.name+'Snapshot';
 output+=`export interface ${model} extends DeviceSnapshot {\n${e.fields.map(f=>`  /** ${f.description.replaceAll('*/','')} */\n  readonly ${f.name}: ${type(f.type)};`).join('\n')}\n}\n`;
 if(e.name!=='SensorDescription')output+=`export const ${e.name}Entity = defineEntity<${model}>(EntityKind.${e.name}, ${e.targeted});\n`;
}
await writeFile(new URL('packages/core/src/generated.ts',root),output);
const enumValues=Object.fromEntries(Object.entries(enums).map(([k,v])=>[k,v.map(x=>k.endsWith('ThermalState')?k+'.'+x:x)]));
enumValues.ThermalState=[...enumValues.AndroidThermalState,...enumValues.AppleThermalState];
await writeFile(new URL('packages/core/src/schema-data.ts',root),`// Generated.\nexport const schemaData = ${JSON.stringify(schema)} as const;\nexport const enumValues: Readonly<Record<string,readonly string[]>> = ${JSON.stringify(enumValues)};\n`);
console.log(`Generated ${schema.entities.length} typed entities.`);
