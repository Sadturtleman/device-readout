const path = require('node:path');
const runtime = path.resolve(__dirname, '../../../.tools/react-native-0.88/node_modules');
const useRuntime = require('node:module').createRequire(path.join(runtime, '../package.json'));
const android = useRuntime('@react-native-community/cli-platform-android');
const {bundleCommand} = useRuntime('@react-native/community-cli-plugin');
module.exports = {
  reactNativePath: path.join(runtime, 'react-native'),
  project: {android: {sourceDir: './android', packageName: 'dev.devicereadout.verification'}},
  dependencies: {'@device-readout/react-native': {root: path.resolve(__dirname, '..')}},
  platforms: {android: {projectConfig: android.projectConfig, dependencyConfig: android.dependencyConfig}},
  commands: [bundleCommand],
};
