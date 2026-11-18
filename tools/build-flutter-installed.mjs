import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import {spawn} from 'node:child_process';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {projectRoot, copySources, prepareFlutterPackages} from './prepare-flutter-packages.mjs';

const flutterRoot = process.env.FLUTTER_ROOT;
if (!flutterRoot || !process.env.PUB_CACHE) throw Error('Use build-flutter-packages.ps1 to configure local tools.');
const dart = path.join(flutterRoot, 'bin/cache/dart-sdk/bin/dart.exe');
const tool = path.join(flutterRoot, 'bin/cache/flutter_tools.snapshot');
const web = process.argv.includes('--platform=web');
const windows = process.argv.includes('--platform=windows');
const consumer = path.join(projectRoot, web ? '.tools/flutter-web-installed' : windows ? '.tools/flutter-windows-installed' : '.tools/flutter-installed');
const example = path.join(projectRoot, 'flutter/device_readout_flutter/example');
const records = prepareFlutterPackages(flutterRoot);
fs.mkdirSync(consumer, {recursive: true});
for (const name of [...(web ? [] : windows ? ['windows'] : ['android']), 'lib', 'test_support', 'web']) copySources(path.join(example, name), path.join(consumer, name));
fs.copyFileSync(path.join(projectRoot, 'flutter/device_readout_flutter/analysis_options.yaml'), path.join(consumer, 'analysis_options.yaml'));
const requests = [];
let origin;
const server = http.createServer((request, response) => {
  requests.push(request.url);
  if (request.method !== 'GET') { response.writeHead(405); response.end(); return; }
  const record = records.find(item => request.url === '/api/packages/' + item.name);
  if (record) {
    const version = {version: record.version, pubspec: record.pubspec, archive_url: origin + '/archives/' + record.name, archive_sha256: record.sha256};
    response.writeHead(200, {'Content-Type': 'application/vnd.pub.v2+json'});
    response.end(JSON.stringify({name: record.name, latest: version, versions: [version]})); return;
  }
  const archive = records.find(item => request.url === '/archives/' + item.name);
  if (archive) { response.writeHead(200, {'Content-Type': 'application/octet-stream'}); fs.createReadStream(archive.archive).pipe(response); return; }
  response.writeHead(404); response.end();
});
await new Promise((resolve, reject) => {server.once('error', reject); server.listen(0, '127.0.0.1', resolve);});
origin = 'http://127.0.0.1:' + server.address().port;
async function run(args) {
  await new Promise((resolve, reject) => {
    const child = spawn(dart, args, {cwd: consumer, stdio: 'inherit', env: process.env});
    child.once('error', reject);
    child.once('exit', code => code === 0 ? resolve() : reject(Error('Consumer command failed: ' + args.join(' '))));
  });
}
const flutter = (...args) => run([tool, '--suppress-analytics', '--no-version-check', ...args]);
try {
  const pubspec = fs.readFileSync(path.join(example, 'pubspec.yaml'), 'utf8')
    .replace(/  device_readout_flutter:\r?\n    path: \.\.\//, '  device_readout_flutter:\n    hosted: ' + origin + '\n    version: 0.1.0');
  fs.writeFileSync(path.join(consumer, 'pubspec.yaml'), pubspec + '\ndependency_overrides:\n  device_readout:\n    hosted: ' + origin + '\n    version: 0.1.0\n');
  await flutter('pub', 'get');
  const configFile = path.join(consumer, '.dart_tool/package_config.json');
  const config = JSON.parse(fs.readFileSync(configFile, 'utf8'));
  for (const record of records) {
    const entry = config.packages.find(item => item.name === record.name);
    if (!entry) throw Error('Missing installed package: ' + record.name);
    const installed = fileURLToPath(new URL(entry.rootUri, pathToFileURL(configFile)));
    if (!fs.realpathSync(installed).startsWith(path.join(process.env.PUB_CACHE, 'hosted') + path.sep)) throw Error('SDK did not resolve from hosted cache.');
    if (!requests.includes('/archives/' + record.name)) throw Error('Pub did not download the archive: ' + record.name);
    record.installed = installed;
  }
  await run(['analyze', '.']);
  if (web) {
    for (const [target, output, base] of [['lib/main.dart', 'web', '/'], ['test_support/web_contracts.dart', 'web-contracts', '/contracts/']]) {
      await flutter('build', 'web', '--release', '--no-pub', '--no-web-resources-cdn', '--no-wasm-dry-run', '--target=' + target, '--output=build/' + output, '--base-href=' + base);
    }
  } else if (windows) {
    await flutter('build', 'windows', '--release', '--no-pub', '--target=lib/main.dart');
    if (!fs.existsSync(path.join(consumer, 'build/windows/x64/runner/Release/device_readout_win32.dll'))) {
      throw Error('The installed consumer must bundle the production Win32 error-capture library.');
    }
  } else {
    await flutter('build', 'apk', '--debug', '--target-platform=android-x64', '--no-pub', '--target=test_support/android_sensors.dart');
  }
  fs.mkdirSync(path.join(projectRoot, '.tools/evidence'), {recursive: true});
  fs.writeFileSync(path.join(projectRoot, web ? '.tools/evidence/flutter-web-installed-packages.json' : windows ? '.tools/evidence/flutter-windows-installed-packages.json' : '.tools/evidence/flutter-installed-packages.json'), JSON.stringify({passed: true, origin, requests, records}, null, 2));
} finally {
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
}
