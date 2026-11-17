import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
import {createHash, randomUUID} from 'node:crypto';
import {prepareFlutterNative} from './prepare-flutter-native.mjs';
import {prepareFlutterWeb} from './prepare-flutter-web.mjs';

export const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export function copySources(source, destination) {
  fs.cpSync(source, destination, {recursive: true, filter: name => {
    const relative = path.relative(source, name).replaceAll('\\', '/');
    if (/(^|\/)(build|\.gradle|\.dart_tool|\.cxx|ephemeral|\.idea)(\/|$)|(^|\/)(local\.properties|GeneratedPluginRegistrant\.java)$/.test(relative)) return false;
    if (fs.lstatSync(name).isSymbolicLink()) throw Error('Source copy cannot follow links: ' + name);
    return true;
  }});
}
export function prepareFlutterPackages(flutterRoot) {
  prepareFlutterNative();
  prepareFlutterWeb();
  const staging = path.join(projectRoot, '.tools/flutter-package-candidates', randomUUID());
  const dart = path.join(flutterRoot, 'bin/cache/dart-sdk/bin/dart.exe');
  const yamlConfig = path.join(flutterRoot, 'packages/flutter_tools/.dart_tool/package_config.json');
  const records = [];
  for (const [name, relative] of [['device_readout', 'dart/device_readout'], ['device_readout_flutter', 'flutter/device_readout_flutter']]) {
    const source = path.join(projectRoot, relative), target = path.join(staging, name);
    fs.mkdirSync(target, {recursive: true});
    for (const item of ['pubspec.yaml', 'README.md', 'lib']) copySources(path.join(source, item), path.join(target, item));
    fs.copyFileSync(path.join(projectRoot, 'LICENSE'), path.join(target, 'LICENSE'));
    if (name === 'device_readout_flutter') {
      copySources(path.join(source, 'assets'), path.join(target, 'assets'));
      copySources(path.join(source, 'android/src/main'), path.join(target, 'android/src/main'));
      copySources(path.join(source, 'android/shared'), path.join(target, 'android/shared'));
      fs.copyFileSync(path.join(source, 'android/build.gradle'), path.join(target, 'android/build.gradle'));
    }
    const pubspec = JSON.parse(execFileSync(dart, ['--packages=' + yamlConfig, path.join(projectRoot, 'tools/read-pubspec.dart'), path.join(target, 'pubspec.yaml')], {encoding: 'utf8'}));
    const archive = path.join(staging, name + '-' + pubspec.version + '.tar.gz');
    execFileSync('tar', ['-czf', archive, '-C', target, '.']);
    const sha256 = createHash('sha256').update(fs.readFileSync(archive)).digest('hex');
    records.push({name, version: pubspec.version, pubspec, archive, sha256});
  }
  return records;
}
