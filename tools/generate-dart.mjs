import {readFile, writeFile, mkdir} from 'node:fs/promises';
const root = new URL('../', import.meta.url);
const schema = JSON.parse(await readFile(new URL('schema/device-readout.json', root), 'utf8'));
const enums = JSON.parse(await readFile(new URL('schema/enums.json', root), 'utf8'));
enums.SensorKind = schema.entities.filter(e => e.mode !== 'state').map(e => e.name);
const lower = s => s[0].toLowerCase() + s.slice(1);
function type(s) {
  if (s.endsWith('?')) return type(s.slice(0, -1)) + '?';
  const generic = /^(List|Set|Map|Size)<(.+)>$/.exec(s);
  if (generic) return `${generic[1]}<${generic[2].split(',').map(v => type(v.trim())).join(', ')}>`;
  return ({String:'String', Integer:'int', Number:'double', Ratio:'double', Boolean:'bool',
    ByteCount:'BigInt', Int64:'BigInt', CalendarId:'String', NumberingSystemId:'String', IpAddress:'String'})[s] ?? s;
}
function decode(t, v, hydrated = false) {
  t = t.replace(/\?$/, '');
  if (enums[t]) return `_enumValue(${v}, ${t}.values)`;
  const simple = {Integer:'_integer', Number:'_number', Ratio:'_ratio', ByteCount:'_counter',
    Duration:'_duration', Quaternion:'_rotation', ThermalState:'_thermal', DisplayMode:'_displayMode', IpAddressInfo:'_addressInfo', NetworkRoute:'_route'};
  if (hydrated) Object.assign(simple, {Integer:'_wireInteger', Number:'_wireNumber', Ratio:'_wireNumber', ByteCount:'_wireCounter',
    Duration:'_wireDuration', Quaternion:'_wireRotation', DisplayMode:'_wireDisplayMode', IpAddressInfo:'_wireAddressInfo', NetworkRoute:'_wireRoute'});
  if (simple[t]) return `${simple[t]}(${v})`;
  if (t === 'Int64') return hydrated ? `_wireCounter(${v})` : `_counter(${v}, signed: true)`;
  if (['String', 'CalendarId', 'NumberingSystemId', 'IpAddress'].includes(t)) return `${v} is String ? ${v}${v === 'raw' ? '' : ' as String'} : null`;
  if (t === 'Boolean') return `${v} is bool ? ${v}${v === 'raw' ? '' : ' as bool'} : null`;
  if (t === 'Size<Integer>') return `${hydrated?'_wirePixelSize':'_pixelSize'}(${v})`;
  const composites = {Rect:[['x','y','width','height'],'Rect'], Insets:[['top','right','bottom','left'],'Insets'],
    Vector3:[['x','y','z'],'Vector3'], 'Size<Number>':[['width','height'],'Size<double>']};
  if (composites[t]) {
    const [keys, ctor] = composites[t];
    return `${hydrated?'_wireComponents':'_components'}(${v}, [${keys.map(k=>`'${k}'`).join(', ')}], (n) => ${ctor}(${keys.map((_,i)=>`n[${i}]`).join(', ')}))`;
  }
  const list = /^(List|Set)<(.+)>$/.exec(t);
  if (list) return `_${list[1].toLowerCase()}(${v}, (raw) => ${decode(list[2], 'raw', hydrated)})`;
  const map = /^Map<(.+), (.+)>$/.exec(t);
  if (map) return `_map(${v}, (raw) => ${decode(map[1], 'raw', hydrated)}, (raw) => ${decode(map[2], 'raw', hydrated)})`;
  throw Error(`Unhandled Dart field type: ${t}`);
}
let code = "// Generated from schema/device-readout.json and schema/enums.json.\npart of 'core.dart';\n\n";
for (const [name, values] of Object.entries(enums)) {
  code += `enum ${name} implements _WireEnum${name.endsWith('ThermalState')?', ThermalState':''} {\n`;
  code += values.map(v => `  ${lower(v)}('${v}')`).join(',\n') + ';\n';
  code += `  @override\n  final String wireName;\n  const ${name}(this.wireName);\n}\n\n`;
}
code += `enum EntityKind { ${schema.entities.map(e=>lower(e.name)).join(', ')} }\n\n`;
code += 'abstract final class Entities {\n';
for (const e of schema.entities) code += `  static const ${lower(e.name)} = Entity<${e.name}Snapshot>._(EntityKind.${lower(e.name)}, EntityMode.${e.mode}, ${e.targeted});\n`;
code += '}\n';
code += '\nSensorKind? _sensorKind(EntityKind kind) => switch (kind) {\n';
for (const e of schema.entities.filter(e => e.mode !== 'state')) {
  code += `  EntityKind.${lower(e.name)} => SensorKind.${lower(e.name)},\n`;
}
code += '  _ => null,\n};\n';
const models = [...schema.entities, {name:'SensorDescription', fields:schema.sensorDescription}];
for (const e of models) {
  const model = e.name === 'SensorDescription' ? e.name : e.name+'Snapshot';
  const collections = e.fields.filter(f=>/^(List|Set|Map)</.test(f.type));
  code += `\nfinal class ${model} extends DeviceSnapshot {\n`;
  for (const f of e.fields) code += `  /// ${f.description.replaceAll('\n',' ')}\n  final ${type(f.type)} ${f.name};\n`;
  code += `  ${model}({super.collectedAt,\n`;
  for (const f of e.fields) code += `    ${collections.includes(f) ? type(f.type)+' '+f.name : 'this.'+f.name},\n`;
  code += '  })';
  if (collections.length) code += ' : '+collections.map(f=>`${f.name} = ${f.name} == null ? null : ${f.type.split('<')[0]}.unmodifiable(${f.name})`).join(',\n      ');
  code += ';\n';
  // Only the worker calls this after decoding. Reuse normalized immutable fields
  // so collection copying and validation finish before the completion clock.
  code += `  ${model}._completed(${model} snapshot)\n    : `;
  code += e.fields.map(f=>`${f.name} = snapshot.${f.name}`).join(',\n      ');
  code += ',\n      super._completed();\n';
  code += `  @override\n  ${model} _collected() => ${model}._completed(this);\n`;
  code += '  @override\n  EntityKind? get entityKind => '+(e.name==='SensorDescription'?'null':`EntityKind.${lower(e.name)}`)+';\n';
  code += "  @override\n  Map<String, Object?> _fields() => {\n";
  for (const f of e.fields) code += `    '${f.name}': ${f.name},\n`;
  code += '  };\n}\n';
}
code += '\n/// Low-level native-adapter decoder. App queries use typed Entities.\nabstract final class SnapshotCodec {\n';
code += '  static DeviceSnapshot decode(EntityKind kind, Map<String, Object?> fields, {DateTime? collectedAt}) => switch(kind) {\n';
for (const e of schema.entities) {
  code += `    EntityKind.${lower(e.name)} => ${e.name}Snapshot(collectedAt: collectedAt,\n`;
  for (const f of e.fields) code += `      ${f.name}: ${decode(f.type,`fields['${f.name}']`)},\n`;
  code += '    ),\n';
}
code += '  };\n';
code += '  static SensorDescription describe(Map<String, Object?> fields, {DateTime? collectedAt}) => SensorDescription(collectedAt: collectedAt,\n';
for (const f of schema.sensorDescription) code += `    ${f.name}: ${decode(f.type,`fields['${f.name}']`)},\n`;
code += '  );\n';
code += '  static DeviceSnapshot _hydrate(EntityKind kind, Map<String, Object?> fields, DateTime collectedAt) => switch(kind) {\n';
for (const e of schema.entities) {
  code += `    EntityKind.${lower(e.name)} => ${e.name}Snapshot(collectedAt: collectedAt,\n`;
  for (const f of e.fields) code += `      ${f.name}: ${decode(f.type,`fields['${f.name}']`,true)},\n`;
  code += '    ),\n';
}
code += '  };\n';
code += '  static SensorDescription _hydrateDescription(Map<String, Object?> fields, DateTime collectedAt) => SensorDescription(collectedAt: collectedAt,\n';
for (const f of schema.sensorDescription) code += `    ${f.name}: ${decode(f.type,`fields['${f.name}']`,true)},\n`;
code += '  );\n}\n';
const destination = new URL('dart/device_readout/lib/src/', root);
await mkdir(destination, {recursive:true});
await writeFile(new URL('generated.dart', destination), code);
console.log(`Generated ${schema.entities.length} Dart entities and SensorDescription.`);
