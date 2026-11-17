import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const consumer = path.join(root, '.tools/rn-installed');
const example = path.join(root, 'packages/react-native/example');
fs.mkdirSync(consumer, {recursive: true});
const files = execFileSync('git', ['ls-files', '-z', 'packages/react-native/example'], {cwd: root, encoding: 'utf8'}).split('\0').filter(Boolean);
for (const file of files) {
  const relative = path.relative(example, path.join(root, file));
  if (!(relative.startsWith('android' + path.sep) || relative.startsWith('src' + path.sep) || relative === 'index.js')) continue;
  const target = path.join(consumer, relative);
  fs.mkdirSync(path.dirname(target), {recursive: true});
  fs.copyFileSync(path.join(root, file), target);
}
const write = (name, value) => fs.writeFileSync(path.join(consumer, name), value);
const appGradle = fs.readFileSync(path.join(example, 'android/app/build.gradle'), 'utf8')
  .replace("file('../../../../../.tools/react-native-0.88/node_modules')", "file('../../node_modules')")
  .replace("file('../../../../../.tools/rn-app-cxx')", "file('../../.cxx')");
if (appGradle.includes('.tools')) throw Error('Consumer app must not use monorepo paths.');
write('android/app/build.gradle', appGradle);
write('android/settings.gradle', `pluginManagement {includeBuild('../node_modules/@react-native/gradle-plugin')}
plugins {id('com.facebook.react.settings')}
extensions.configure(com.facebook.react.ReactSettingsExtension) {it.autolinkLibrariesFromCommand()}
rootProject.name = 'DeviceReadoutInstalledVerification'
include ':app'
includeBuild('../node_modules/@react-native/gradle-plugin')
`);
write('metro.config.js', `const {getDefaultConfig, mergeConfig} = require('@react-native/metro-config');
module.exports = mergeConfig(getDefaultConfig(__dirname), {maxWorkers: 2});
`);
write('babel.config.js', "module.exports = {presets: ['module:@react-native/babel-preset']};\n");
write('react-native.config.js', "module.exports = {project: {android: {packageName: 'dev.devicereadout.verification'}}};\n");
write('tsconfig.json', JSON.stringify({extends: '@react-native/typescript-config', compilerOptions: {noEmit: true, types: ['react']}, include: ['src/**/*.tsx']}, null, 2));
const runtime = JSON.parse(fs.readFileSync(path.join(root, 'tools/react-native-runtime/package.json'), 'utf8'));
const records = JSON.parse(fs.readFileSync(path.join(root, '.tools/rn-package-records.json'), 'utf8'));
for (const record of records) runtime.dependencies[record.name] = 'file:' + path.relative(consumer, record.path).replaceAll('\\', '/');
write('package.json', JSON.stringify({name: 'device-readout-installed-android-consumer', version: '0.1.0', private: true, ...runtime}, null, 2));
fs.copyFileSync(path.join(root, 'tools/react-native-runtime/package-lock.json'), path.join(consumer, 'package-lock.json'));
console.log('Prepared an independent Android consumer with ordinary package resolution.');
