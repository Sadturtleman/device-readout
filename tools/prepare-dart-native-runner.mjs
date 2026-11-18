import fs from 'node:fs';

// A separate build-only consumer keeps verification entrypoints out of the SDK's
// public bin directory. dart build bundles the runtime's native code asset.
const directory = '.tools/dart-native-runner';
fs.mkdirSync(`${directory}/bin`, {recursive: true});
fs.writeFileSync(`${directory}/pubspec.yaml`, `name: device_readout_checks
publish_to: none
environment:
  sdk: '>=3.13.0 <4.0.0'
dependencies:
  device_readout:
    path: ../../dart/device_readout
`);
fs.writeFileSync(`${directory}/bin/contracts.dart`, `import '../../../dart/device_readout/test/contracts.dart' as checks;
Future<void> main(List<String> arguments) => checks.main(arguments);
`);
