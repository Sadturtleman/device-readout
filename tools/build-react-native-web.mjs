import {build} from 'esbuild';
import {mkdir, copyFile, writeFile, symlink, realpath} from 'node:fs/promises';
import {resolve} from 'node:path';
import {spawnSync} from 'node:child_process';

const installed = process.argv.includes('--installed');
const consumer = resolve('.tools/react-native-web-installed');
const typeCommands = installed
  ? [['--target', 'ES2020', '--module', 'ESNext', '--moduleResolution', 'Bundler', '--customConditions', 'browser', '--strict', '--noEmit', resolve(consumer, 'types.ts')]]
  : [['-p', 'packages/react-native/tsconfig.web.json'], ['-p', 'packages/react-native/tsconfig.web-test.json']];
for (const args of typeCommands) {
  const result = spawnSync(process.execPath, ['node_modules/typescript/bin/tsc', ...args], {stdio: 'inherit'});
  if (result.status !== 0) process.exit(result.status ?? 1);
}

const runtime = installed ? resolve(consumer, 'node_modules') : resolve('.tools/react-native-web-0.21/node_modules');
const output = resolve('.tools/react-native-web-app');
const packages = installed ? runtime : resolve('.tools/react-native-web-packages/node_modules');
await mkdir(resolve(packages, '@device-readout'), {recursive: true});
for (const name of ['core', 'web', 'react-native']) {
  if (installed) {
    const target = resolve(packages, '@device-readout', name);
    if (await realpath(target) !== target) throw Error(`Installed ${name} is unexpectedly linked to source.`);
    continue;
  }
  const source = resolve('packages', name), target = resolve(packages, '@device-readout', name);
  try { await symlink(source, target, 'junction'); }
  catch (error) { if (error.code !== 'EEXIST' || await realpath(target) !== await realpath(source)) throw error; }
}
await mkdir(output, {recursive: true});
const result = await build({
  entryPoints: [installed ? resolve(consumer, 'app/App.jsx') : 'packages/react-native/example/web/App.jsx'],
  outfile: resolve(output, 'app.js'), bundle: true, format: 'esm', platform: 'browser',
  target: 'es2020', jsx: 'automatic', metafile: true,
  nodePaths: [packages],
  define: {'process.env.NODE_ENV': '"production"'},
  alias: {
    'react-native': resolve(runtime, 'react-native-web'),
    react: resolve(runtime, 'react'),
    'react-dom': resolve(runtime, 'react-dom'),
  },
});
await writeFile(resolve(output, 'metafile.json'), JSON.stringify(result.metafile, null, 2));
if (Object.keys(result.metafile.inputs).some(file => /(?:packages|@device-readout)\/react-native\/(?:src|dist)\/(?:index\.(?:js|ts)|native-connection\.|specs\/)/.test(file))) {
  throw Error('The browser bundle includes the native SDK entrypoint or transport.');
}
const nativeResolution = await build({
  stdin: {contents: "export {createReactNativeDeviceAccess} from '@device-readout/react-native';", resolveDir: installed ? consumer : resolve('.')},
  bundle: true, write: false, metafile: true, format: 'esm', platform: 'neutral', target: 'es2020',
  conditions: ['react-native'], nodePaths: [packages], external: ['react-native', '@device-readout/core'],
});
const nativeInputs = Object.keys(nativeResolution.metafile.inputs);
if (!nativeInputs.some(file => /(?:packages|@device-readout)\/react-native\/src\/index\.ts$/.test(file)) ||
    nativeInputs.some(file => /index\.web\./.test(file))) {
  throw Error('The react-native package condition no longer selects its native entrypoint.');
}
await build({entryPoints: [installed ? resolve(consumer, 'server.test.mjs') : 'packages/react-native/test/web/server.test.mjs'],
  outfile: '.tools/test/react-native-web-server.test.mjs', bundle: true, format: 'esm', platform: 'node',
  target: 'es2020', nodePaths: [packages]});
await copyFile(installed ? resolve(runtime, '@device-readout/web/dist/worker.js') : 'packages/web/dist/worker.js', resolve(output, 'worker.js'));
await writeFile(resolve(output, 'build-mode.json'), JSON.stringify({installed}));
await writeFile(resolve(output, 'index.html'), '<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>DeviceReadout React Native Web</title><style>html,body,#root{margin:0;min-height:100%;}#root{display:flex;flex-direction:column;}</style><div id="root"></div><script type="module" src="./app.js"></script></html>');
console.log(`React Native Web application: ${output}`);
