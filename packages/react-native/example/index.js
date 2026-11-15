import React from 'react';
import {AppRegistry} from 'react-native';
function VerificationRoot(props) {
  const App = props.isolation ? require('./src/IsolationApp').default : require('./src/App').default;
  return React.createElement(App, props);
}
AppRegistry.registerComponent('DeviceReadoutVerification', () => VerificationRoot);
