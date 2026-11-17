import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';

const packageRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repository = path.resolve(packageRoot, '../..');
const output = path.join(packageRoot, 'android/shared');
const digest = value => createHash('sha256').update(value).digest('hex');
function files(directory) {
  if (!fs.existsSync(directory)) return [];
  if (fs.lstatSync(directory).isSymbolicLink()) throw Error('Shared sources must not be linked.');
  return fs.readdirSync(directory, {withFileTypes: true}).flatMap(entry => {
    const name = path.join(directory, entry.name);
    if (entry.isSymbolicLink()) throw Error('Shared source entry must not be linked: ' + name);
    return entry.isDirectory() ? files(name) : [name];
  });
}
const sources = ['core', 'android'].map(name => [name, path.join(repository, 'kotlin', name, 'src/main/kotlin')]);
if (sources.every(([, source]) => fs.existsSync(source))) {
  const manifest = {};
  for (const [name, source] of sources) {
    for (const file of files(source).filter(file => file.endsWith('.kt'))) {
      const relative = name + '/' + path.relative(source, file).replaceAll('\\', '/');
      const content = fs.readFileSync(file);
      manifest[relative] = digest(content);
    }
  }
  // Validate the fixed output before removing only obsolete individual source files.
  const existing = files(output);
  for (const file of existing) {
    const relative = path.relative(output, file).replaceAll('\\', '/');
    if (relative !== 'manifest.json' && !Object.hasOwn(manifest, relative)) fs.unlinkSync(file);
  }
  for (const [name, source] of sources) {
    for (const file of files(source).filter(file => file.endsWith('.kt'))) {
      const target = path.join(output, name, path.relative(source, file));
      fs.mkdirSync(path.dirname(target), {recursive: true});
      fs.copyFileSync(file, target);
    }
  }
  fs.writeFileSync(path.join(output, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
}
// A downloaded package can also be re-packed without the original repository.
const manifest = JSON.parse(fs.readFileSync(path.join(output, 'manifest.json'), 'utf8'));
const entries = Object.entries(manifest);
if (!entries.length) throw Error('Missing shared Kotlin sources.');
for (const [relative, expected] of entries) {
  const target = path.resolve(output, relative);
  if (!target.startsWith(output + path.sep) || digest(fs.readFileSync(target)) !== expected) throw Error('Invalid shared source: ' + relative);
}
console.log(`Prepared ${entries.length} shared Kotlin source files for the React Native package.`);
