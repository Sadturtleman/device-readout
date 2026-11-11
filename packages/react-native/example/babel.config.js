const path = require('node:path');
const runtime = path.resolve(__dirname, '../../../.tools/react-native-0.88/node_modules');
const useRuntime = require('node:module').createRequire(path.join(runtime, '../package.json'));
module.exports = {presets: [useRuntime.resolve('@react-native/babel-preset')]};
