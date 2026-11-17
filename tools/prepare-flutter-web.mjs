import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export function prepareFlutterWeb() {
  const source = path.join(root, 'packages/web/dist/dart-worker.js');
  const output = path.join(root, 'flutter/device_readout_flutter/assets/device-readout-dart-worker.js');
  // Ship the standalone module without a dangling development sourcemap URL.
  const code = fs.readFileSync(source, 'utf8').replace(/\n\/\/# sourceMappingURL=.*(?:\r?\n)?$/, '\n');
  fs.mkdirSync(path.dirname(output), {recursive: true});
  fs.writeFileSync(output, code);
  console.log('Prepared the Flutter web collection-worker asset.');
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) prepareFlutterWeb();
