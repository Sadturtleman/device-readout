import {readFile,writeFile,mkdir} from 'node:fs/promises';
const root=new URL('../',import.meta.url);
const schema=JSON.parse(await readFile(new URL('schema/device-readout.json',root),'utf8'));
const enums=JSON.parse(await readFile(new URL('schema/enums.json',root),'utf8'));
enums.SensorKind=schema.entities.filter(e=>e.mode!=='state').map(e=>e.name);
function type(s){
  if(s.endsWith('?'))return type(s.slice(0,-1))+'?';
  if(/^(List|Set|Map|Size)</.test(s)){
    const bracket=s.indexOf('<');return s.slice(0,bracket)+'<'+s.slice(bracket+1,-1).split(',').map(v=>type(v.trim())).join(', ')+'>';
  }
  return ({Integer:'Int',Number:'Double',Ratio:'Double',ByteCount:'ULong',Int64:'Long',CalendarId:'String',NumberingSystemId:'String',IpAddress:'String'})[s]??s;
}
let code='// Generated from the shared DeviceReadout schema.\npackage dev.devicereadout\n\nimport java.time.Instant\nimport kotlin.time.Duration\n\n';
for(const [name,values]of Object.entries(enums)){
  code+=`enum class ${name}${name.endsWith('ThermalState')?' : ThermalState':''} { ${values.join(', ')} }\n`;
}
code+=`enum class EntityKind { ${schema.entities.map(e=>e.name).join(', ')} }\n`;
code+='sealed interface ThermalState\n';
for(const e of [...schema.entities,{name:'SensorDescription',fields:schema.sensorDescription}]){
  const model=e.name==='SensorDescription'?e.name:e.name+'Snapshot';
  code+=`\ndata class ${model}(\n    override val collectedAt: Instant = Instant.EPOCH,\n`;
  for(const f of e.fields)code+=`    /** ${f.description.replaceAll('*/','')} */\n    val ${f.name}: ${type(f.type)} = null,\n`;
  code+=`) : DeviceSnapshot\n`;
  if(e.name!=='SensorDescription')code+=`val ${e.name}Entity = Entity<${model}>(EntityKind.${e.name}, ${e.targeted}, EntityMode.${e.mode[0].toUpperCase()+e.mode.slice(1)}, ${model}::class.java)\n`;
}
function normalized(f){
  const value='snapshot.'+f.name,t=f.type.replace(/\?$/,'');
  if(t.startsWith('Set<'))return `SnapshotRules.knownSet(${value}, ${t.slice(4,-1)}::class.java)`;
  if(t.startsWith('Map<'))return `SnapshotRules.knownMap(${value}, ${t.slice(4,-1).split(',')[0]}::class.java)`;
  const rules={Number:'finite',Ratio:'ratio',Duration:'duration',Vector3:'vector',Quaternion:'rotation',Rect:'rectangle',Insets:'insets','Size<Number>':'size',
    'List<String>':'strings','List<IpAddress>':'strings','List<DisplayMode>':'displayModes','List<IpAddressInfo>':'addresses','List<NetworkRoute>':'routes'};
  return rules[t]?`SnapshotRules.${rules[t]}(${value})`:value;
}
code+='\ninternal fun normalizeSnapshot(snapshot: DeviceSnapshot): DeviceSnapshot = when (snapshot) {\n';
for(const e of [...schema.entities,{name:'SensorDescription',fields:schema.sensorDescription}]){
  const name=e.name==='SensorDescription'?e.name:e.name+'Snapshot';
  const changed=e.fields.filter(f=>normalized(f)!=='snapshot.'+f.name);
  code+=`    is ${name} -> snapshot.copy(${changed.map(f=>f.name+' = '+normalized(f)).join(', ')})\n`;
}
code+='    else -> throw DeviceReadoutException(ErrorCode.ReadFailed, "Unknown snapshot type.")\n}\n';
code+='\ninternal fun stamp(value: DeviceSnapshot): DeviceSnapshot {\n    val snapshot = normalizeSnapshot(value)\n    return when (snapshot) {\n';
for(const e of [...schema.entities,{name:'SensorDescription'}]){
  const name=e.name==='SensorDescription'?e.name:e.name+'Snapshot';
  code+=`    is ${name} -> snapshot.copy(collectedAt = Instant.now())\n`;
}
code+='    else -> throw DeviceReadoutException(ErrorCode.ReadFailed, "Unknown snapshot type.")\n    }\n}\n';
code+='\ninternal fun snapshotFields(snapshot: DeviceSnapshot): Map<String, Any?> = when (snapshot) {\n';
for(const e of [...schema.entities,{name:'SensorDescription',fields:schema.sensorDescription}]){
  const name=e.name==='SensorDescription'?e.name:e.name+'Snapshot';
  code+=`    is ${name} -> linkedMapOf("collectedAt" to snapshot.collectedAt, ${e.fields.map(f=>'"'+f.name+'" to snapshot.'+f.name).join(', ')})\n`;
}
code+='    else -> throw DeviceReadoutException(ErrorCode.ReadFailed, "Unknown snapshot type.")\n}\n';
const destination=new URL('kotlin/core/src/main/kotlin/dev/devicereadout/',root);
code+='\ninternal fun bindingEntity(name: String): Entity<out DeviceSnapshot> = when (name) {\n';
for(const entity of schema.entities)code+=`    "${entity.name}" -> ${entity.name}Entity\n`;
code+='    else -> throw DeviceReadoutException(ErrorCode.UnsupportedEntity, "Unknown entity kind.")\n}\n';
await mkdir(destination,{recursive:true});await writeFile(new URL('Generated.kt',destination),code);
function decodeType(source, value) {
  const t=source.replace(/\?$/,'');
  if(t.startsWith('List<'))return `BindingValues.list(${value}) { ${decodeType(t.slice(5,-1),'it')} }`;
  if(t.startsWith('Set<'))return `BindingValues.list(${value}) { ${decodeType(t.slice(4,-1),'it')} }?.toSet()`;
  if(t.startsWith('Map<')){
    const [key,inner]=t.slice(4,-1).split(',').map(v=>v.trim());
    return `BindingValues.map(${value}, { ${decodeType(key,'it')} }, { ${decodeType(inner,'it')} })`;
  }
  if(enums[t])return `BindingValues.enum(${value}, ${t}.entries)`;
  const name={String:'string',CalendarId:'string',NumberingSystemId:'string',IpAddress:'string',Boolean:'boolean',Integer:'integer',Number:'number',Ratio:'number',ByteCount:'bytes',Int64:'counter',Duration:'duration',ThermalState:'thermal','Size<Integer>':'pixelSize','Size<Number>':'size',Rect:'rect',Insets:'insets',Vector3:'vector',Quaternion:'rotation',DisplayMode:'displayMode',IpAddressInfo:'address',NetworkRoute:'route'}[t];
  if(!name)throw Error(`No binding decoder for ${t}`);
  return `BindingValues.${name}(${value})`;
}
let decoding='// Generated from the shared DeviceReadout schema.\npackage dev.devicereadout\n\ninternal fun decodeBindingSnapshot(kind: EntityKind, values: Map<*, *>): DeviceSnapshot = when (kind) {\n';
for(const e of schema.entities)decoding+=`    EntityKind.${e.name} -> ${e.name}Snapshot(\n${e.fields.map(f=>`        ${f.name} = ${decodeType(f.type,`values["${f.name}"]`)},`).join('\n')}\n    )\n`;
decoding+='}\n';
await writeFile(new URL('BindingSnapshots.kt',destination),decoding);
console.log(`Generated ${schema.entities.length} Kotlin entities.`);
