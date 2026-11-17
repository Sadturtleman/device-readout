import { schemaData, enumValues } from './schema-data.js';
import { DeviceReadoutError, ErrorCode } from './errors.js';
import { Duration, Instant } from './values.js';
import { ImmutableSet } from './structures.js';
type RecordValue = Record<string,unknown>;
export function record(value:unknown):value is RecordValue { return typeof value==='object'&&value!==null&&!Array.isArray(value); }
export function definition(kind:string) {
 const found = schemaData.entities.find(e=>e.name===kind);
 if(!found)throw new DeviceReadoutError(ErrorCode.UnsupportedEntity,'Unknown entity.');return found;
}
const fieldsFor=(kind:string)=>kind==='SensorDescription'?schemaData.sensorDescription:definition(kind).fields;
function normalize(type:string,value:unknown):unknown {
 if(value===null||value===undefined)return null;
 type=type.replace(/\?$/,'');
 if(type.startsWith('List<')||type.startsWith('Set<')) {
   if(!Array.isArray(value))return null;
   const inner=type.slice(type.startsWith('List<')?5:4,-1);
   const items=value.map(item=>normalize(inner,item));
   return items.some(item=>item===null)?null:items;
 }
 if(type.startsWith('Map<')) {
   if(!record(value))return null;const [keyType,valueType]=type.slice(4,-1).split(',').map(x=>x.trim());
   const result:RecordValue={};for(const [key,item]of Object.entries(value)){
     if(normalize(keyType!,key)===null)return null;const normalized=normalize(valueType!,item);if(normalized===null)return null;result[key]=normalized;
   }return result;
 }
 if(type==='ByteCount'||type==='Int64') {
   if(typeof value!=='bigint'&&!(typeof value==='string'&&/^-?\d+$/.test(value))&&!(typeof value==='number'&&Number.isSafeInteger(value)))return null;
   const v=BigInt(value);const min=type==='ByteCount'?0n:-(1n<<63n);const max=type==='ByteCount'?(1n<<64n)-1n:(1n<<63n)-1n;return v<min||v>max?null:v;
 }
 if(type==='Boolean')return typeof value==='boolean'?value:null;
 if(['Number','Integer','Ratio','Duration'].includes(type)){
   if(typeof value!=='number'||!Number.isFinite(value))return null;
   if(type==='Integer'&&!Number.isSafeInteger(value))return null;
   if(type==='Ratio'&&(value<0||value>1))return null;
   if(type==='Duration'&&value<0)return null;return value;
 }
 if(['String','CalendarId','NumberingSystemId','IpAddress'].includes(type))return typeof value==='string'?value:null;
 if(enumValues[type])return typeof value==='string'&&enumValues[type]!.includes(value)?value:null;
 const components:Record<string,readonly string[]>={Vector3:['x','y','z'],Quaternion:['x','y','z','w'],Rect:['x','y','width','height'],Insets:['top','right','bottom','left']};
 if(type.startsWith('Size<'))components[type]=['width','height'];
 if(components[type]) {
   if(!record(value))return null;const result:RecordValue={};for(const key of components[type]!){const v=normalize(type==='Size<Integer>'?'Integer':'Number',value[key]);if(v===null)return null;result[key]=v;}
   if(type==='Quaternion') {
     const q=result as {x:number;y:number;z:number;w:number};
     const scale=Math.max(Math.abs(q.x),Math.abs(q.y),Math.abs(q.z),Math.abs(q.w));
     if(scale===0)return null;
     const x=q.x/scale,y=q.y/scale,z=q.z/scale,w=q.w/scale;
     const length=Math.sqrt(x*x+y*y+z*z+w*w);
     return {x:x/length,y:y/length,z:z/length,w:w/length};
   }
   return result;
 }
 if(!record(value))return null;
 if(type==='DisplayMode')return {pixelSize:normalize('Size<Integer>',value.pixelSize),refreshRateHz:normalize('Number',value.refreshRateHz)};
 if(type==='IpAddressInfo')return typeof value.address==='string'?{address:value.address,prefixLength:normalize('Integer',value.prefixLength)}:null;
 if(type==='NetworkRoute')return typeof value.destination==='string'?{destination:value.destination,prefixLength:normalize('Integer',value.prefixLength),gateway:normalize('IpAddress',value.gateway)}:null;
 return null;
}
export function normalizeSnapshot(kind:string,raw:unknown):RecordValue {
 if(!record(raw))throw new DeviceReadoutError(ErrorCode.ReadFailed,'Collector returned an invalid snapshot.');
 const result:RecordValue={};
 for(const field of fieldsFor(kind)) result[field.name]=normalize(field.type,raw[field.name]);
 result.collectedAt=new Date().toISOString();
 return result;
}
function freeze(value:unknown):unknown {
 if(Array.isArray(value))return Object.freeze(value.map(freeze));
 if(record(value))return Object.freeze(Object.fromEntries(Object.entries(value).map(([k,v])=>[k,freeze(v)])));return value;
}
export function hydrateSnapshot(kind:string,wire:unknown):unknown {
 if(!record(wire)||typeof wire.collectedAt!=='string')throw new DeviceReadoutError(ErrorCode.ReadFailed,'Invalid snapshot response.');
 const result:RecordValue={collectedAt:new Instant(wire.collectedAt)};
 for(const field of fieldsFor(kind)){
   const value=wire[field.name]??null;
   // Native JSON preserves integers as decimal strings; worker transports may carry bigint directly.
   const v=/\b(ByteCount|Int64)\b/.test(field.type)?normalize(field.type,value):value;
   result[field.name]=v===null?null:field.type.startsWith('Set<')?new ImmutableSet(v as unknown[]):field.type==='Duration?'?Duration.milliseconds(v as number):freeze(v);
 }
 return Object.freeze(result);
}
export function serializeSnapshot(value:unknown):string {return JSON.stringify(value,(_,item)=>typeof item==='bigint'?item.toString():item);}
