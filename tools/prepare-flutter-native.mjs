import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
function files(directory) {
  if (!fs.existsSync(directory)) return [];
  if (fs.lstatSync(directory).isSymbolicLink()) throw Error('Source directory must not be a link: ' + directory);
  return fs.readdirSync(directory, {withFileTypes: true}).flatMap(entry => {
    const name = path.join(directory, entry.name);
    if (entry.isSymbolicLink()) throw Error('Source entry must not be a link: ' + name);
    return entry.isDirectory() ? files(name) : [name];
  });
}
export function prepareFlutterNative() {
  const output = path.join(root, 'flutter/device_readout_flutter/android/shared');
  const sources = new Map();
  for (const name of ['core', 'android']) {
    const source = path.join(root, 'kotlin', name, 'src/main/kotlin');
    if (!fs.existsSync(source)) throw Error('Missing canonical source: ' + source);
    for (const file of files(source).filter(name => name.endsWith('.kt'))) {
      sources.set(name + '/' + path.relative(source, file).replaceAll('\\', '/'), file);
    }
  }
  for (const file of files(output)) {
    const relative = path.relative(output, file).replaceAll('\\', '/');
    if (relative !== 'manifest.json' && !sources.has(relative)) fs.unlinkSync(file);
  }
  const manifest = {};
  for (const [relative, source] of sources) {
    const content = fs.readFileSync(source), target = path.join(output, relative);
    manifest[relative] = createHash('sha256').update(content).digest('hex');
    fs.mkdirSync(path.dirname(target), {recursive: true});
    fs.writeFileSync(target, content);
  }
  fs.writeFileSync(path.join(output, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
  console.log(`Prepared ${sources.size} shared Kotlin source files for Flutter.`);
  return manifest;
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) prepareFlutterNative();
