import {readFile,writeFile,mkdir} from 'node:fs/promises';
const root=new URL('../',import.meta.url);
const schema=JSON.parse(await readFile(new URL('schema/device-readout.json',root),'utf8'));
const enums=JSON.parse(await readFile(new URL('schema/enums.json',root),'utf8'));
enums.SensorKind=schema.entities.filter(e=>e.mode!=='state').map(e=>e.name);
const pascal=s=>s[0].toUpperCase()+s.slice(1);
function type(s){
  if(s.endsWith('?'))return type(s.slice(0,-1))+'?';
  if(s.startsWith('List<'))return 'ImmutableArray<'+type(s.slice(5,-1))+'>';
  if(s.startsWith('Set<'))return 'ImmutableHashSet<'+type(s.slice(4,-1))+'>';
  if(s.startsWith('Map<'))return 'ImmutableDictionary<'+s.slice(4,-1).split(',').map(t=>type(t.trim())).join(', ')+'>';
  if(s.startsWith('Size<'))return 'Size<'+type(s.slice(5,-1))+'>';
  return ({String:'string',Integer:'int',Number:'double',Ratio:'double',Boolean:'bool',ByteCount:'ulong',Int64:'long',Duration:'TimeSpan',CalendarId:'string',NumberingSystemId:'string',IpAddress:'string'})[s]??s;
}
let code='// Generated from the common DeviceReadout schema.\n#nullable enable\nusing System.Collections.Immutable;\nnamespace DeviceReadout;\n\n';
for(const [name,values]of Object.entries(enums))code+=`public enum ${name} { ${values.join(', ')} }\n`;
code+=`public enum EntityKind { ${schema.entities.map(e=>e.name).join(', ')} }\n`;
for(const e of [...schema.entities,{name:'SensorDescription',fields:schema.sensorDescription}]){
  const model=e.name==='SensorDescription'?e.name:e.name+'Snapshot';
  code+=`\npublic sealed record ${model} : DeviceSnapshot\n{\n`;
  for(const f of e.fields)code+=`    /// <summary>${f.description.replaceAll('&','&amp;').replaceAll('<','&lt;')}</summary>\n    public ${type(f.type)} ${pascal(f.name)} { get; init; }\n`;
  code+='}\n';
}
code+='\npublic static class Entities\n{\n';
for(const e of schema.entities)code+=`    public static Entity<${e.name}Snapshot> ${e.name} { get; } = new(EntityKind.${e.name}, ${e.targeted}, EntityMode.${pascal(e.mode)});\n`;
code+='}\n';
code+='\n';
for(const e of [...schema.entities,{name:'SensorDescription'}])code+=`[System.Text.Json.Serialization.JsonSerializable(typeof(${e.name==='SensorDescription'?e.name:e.name+'Snapshot'}))]\n`;
code+='internal partial class ModelJsonContext : System.Text.Json.Serialization.JsonSerializerContext { }\n';
function normalized(f){
  const value='snapshot.'+pascal(f.name), t=f.type.replace(/\?$/,'');
  if(enums[t])return `SnapshotRules.KnownEnum(${value})`;
  if(t.startsWith('Set<'))return `SnapshotRules.EnumSet(${value})`;
  if(t.startsWith('Map<'))return `SnapshotRules.EnumMap(${value})`;
  const methods={Number:'Finite',Ratio:'Ratio',Duration:'Duration',ThermalState:'Thermal',Vector3:'Vector',Quaternion:'Rotation',Rect:'Rectangle',Insets:'Edges','Size<Number>':'Size',
    'List<String>':'Strings','List<DisplayMode>':'DisplayModes','List<IpAddressInfo>':'Addresses','List<IpAddress>':'Strings','List<NetworkRoute>':'Routes'};
  return methods[t]?`SnapshotRules.${methods[t]}(${value})`:value;
}
code+='\ninternal static partial class SnapshotRules\n{\n    internal static DeviceSnapshot Normalize(DeviceSnapshot value) => value switch {\n';
for(const e of [...schema.entities,{name:'SensorDescription',fields:schema.sensorDescription}]){
  const model=e.name==='SensorDescription'?e.name:e.name+'Snapshot';
  const changed=e.fields.filter(f=>normalized(f)!=='snapshot.'+pascal(f.name));
  code+=`        ${model} snapshot => snapshot with {${changed.map(f=>pascal(f.name)+' = '+normalized(f)).join(', ')}},\n`;
}
code+='        _ => throw new DeviceReadoutException(ErrorCode.ReadFailed, "Unrecognized snapshot type.")\n    };\n}\n';
await mkdir(new URL('dotnet/DeviceReadout',root),{recursive:true});
await writeFile(new URL('dotnet/DeviceReadout/Generated.cs',root),code);
console.log(`Generated ${schema.entities.length} C# entities.`);
