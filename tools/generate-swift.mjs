import {readFile, writeFile, mkdir} from 'node:fs/promises';
const root = new URL('../', import.meta.url);
const schema = JSON.parse(await readFile(new URL('schema/device-readout.json', root), 'utf8'));
const enums = JSON.parse(await readFile(new URL('schema/enums.json', root), 'utf8'));
enums.SensorKind = schema.entities.filter(e => e.mode !== 'state').map(e => e.name);
const lower = value => value[0].toLowerCase() + value.slice(1);
const caseName = value => ({US:'us', UK:'uk', IOS:'iOS', IPadOS:'iPadOS'})[value] ?? lower(value);
const identifier = value => '`' + value + '`';
function normalize(field) {
  const value = 'self.' + identifier(field.name);
  if (field.type === 'Number?') return `SnapshotRules.finite(${value})`;
  if (field.type === 'Ratio?') return `SnapshotRules.ratio(${value})`;
  if (field.type === 'Duration?') return `SnapshotRules.duration(${value})`;
  if (field.type === 'Rect?') return `SnapshotRules.rectangle(${value})`;
  if (field.type === 'Insets?') return `SnapshotRules.insets(${value})`;
  if (field.type === 'Size<Number>?') return `SnapshotRules.size(${value})`;
  if (field.type === 'Vector3?') return `SnapshotRules.vector(${value})`;
  if (field.type === 'Quaternion?') return `SnapshotRules.rotation(${value})`;
  if (field.type === 'DisplayMode?') return `SnapshotRules.displayMode(${value})`;
  if (field.type === 'List<DisplayMode>?') return `SnapshotRules.displayModes(${value})`;
  return value;
}
function type(value) {
  if (value.endsWith('?')) return type(value.slice(0, -1)) + '?';
  if (value.startsWith('List<')) return '[' + type(value.slice(5, -1)) + ']';
  if (value.startsWith('Set<')) return 'Set<' + type(value.slice(4, -1)) + '>';
  if (value.startsWith('Map<')) return '[' + value.slice(4, -1).split(',').map(t => type(t.trim())).join(': ') + ']';
  if (value.startsWith('Size<')) return 'Size<' + type(value.slice(5, -1)) + '>';
  return ({Integer:'Int', Number:'Double', Ratio:'Double', Boolean:'Bool', ByteCount:'UInt64', CalendarId:'String', NumberingSystemId:'String', IpAddress:'String'})[value] ?? value;
}
let code = '// Generated from schema/device-readout.json and schema/enums.json.\nimport Foundation\n\n';
for (const [name, values] of Object.entries({...enums, EntityKind:schema.entities.map(e => e.name)})) {
  code += `public enum ${name}: String, Sendable, CaseIterable {\n`;
  for (const value of values) code += `    case ${caseName(value)} = "${value}"\n`;
  code += '}\n\n';
}
for (const entity of [...schema.entities, {name:'SensorDescription', fields:schema.sensorDescription}]) {
  const name = entity.name === 'SensorDescription' ? entity.name : entity.name + 'Snapshot';
  code += `public struct ${name}: DeviceSnapshot, Equatable, CollectibleSnapshot {\n    public let collectedAt: Date\n`;
  for (const field of entity.fields) code += `    /// ${field.description}\n    public let ${identifier(field.name)}: ${type(field.type)}\n`;
  code += '\n    public init(' + entity.fields.map(f => `${identifier(f.name)}: ${type(f.type)} = nil`).concat('collectedAt: Date = Date(timeIntervalSince1970: 0)').join(', ') + ') {\n';
  code += '        self.collectedAt = collectedAt\n';
  for (const field of entity.fields) code += `        self.${identifier(field.name)} = ${identifier(field.name)}\n`;
  code += '    }\n\n    func collected() -> any DeviceSnapshot {\n';
  const prepared = new Map();
  for (const [index, field] of entity.fields.entries()) {
    const expression = normalize(field);
    if (expression !== 'self.' + identifier(field.name)) {
      const local = `normalizedField${index}`;
      code += `        let ${local} = ${expression}\n`;
      prepared.set(field.name, local);
    }
  }
  code += '        return Self(' + entity.fields.map(f => `${f.name}: ${prepared.get(f.name) ?? normalize(f)}`).concat('collectedAt: Date()').join(', ') + ')\n    }\n}\n\n';
}
code += 'public enum Entities {\n';
for (const entity of schema.entities) code += `    public static let ${lower(entity.name)} = Entity<${entity.name}Snapshot>(kind: .${lower(entity.name)}, requiresTarget: ${entity.targeted}, mode: .${entity.mode})\n`;
code += '}\n';
await mkdir(new URL('swift/Sources/DeviceReadout', root), {recursive:true});
await writeFile(new URL('swift/Sources/DeviceReadout/Generated.swift', root), code);
console.log(`Generated ${schema.entities.length} Swift entities.`);
