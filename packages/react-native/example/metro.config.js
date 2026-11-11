const path = require('node:path');
const root = path.resolve(__dirname, '../../..');
const modules = path.join(root, '.tools/react-native-0.88/node_modules');
const useRuntime = require('node:module').createRequire(path.join(modules, '../package.json'));
const {getDefaultConfig, mergeConfig} = useRuntime('@react-native/metro-config');
module.exports = mergeConfig(getDefaultConfig(__dirname), {
  maxWorkers: 2,
  watchFolders: [path.join(root, 'packages/core'), path.join(root, 'packages/react-native'), modules],
  resolver: {
    nodeModulesPaths: [modules],
    extraNodeModules: {
      react: path.join(modules, 'react'),
      'react-native': path.join(modules, 'react-native'),
      '@device-readout/core': path.join(root, 'packages/core'),
      '@device-readout/react-native': path.join(root, 'packages/react-native'),
    },
  },
});
