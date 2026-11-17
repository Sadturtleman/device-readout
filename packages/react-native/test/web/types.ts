import {createReactNativeDeviceAccess, CpuEntity, type CpuSnapshot, type DeviceAccess} from '@device-readout/react-native';
import {createReactNativeDeviceAccess as createExplicitWebAccess, type ReactNativeWebDeviceAccessOptions} from '@device-readout/react-native/web';

const options: ReactNativeWebDeviceAccessOptions = {workerUrl: new URL('https://example.invalid/worker.js')};
const access: DeviceAccess = createReactNativeDeviceAccess(options);
const cpu: Promise<CpuSnapshot> = access.get(CpuEntity);
const explicit: DeviceAccess = createExplicitWebAccess(options);
// @ts-expect-error Worker assets use a typed URL, not an unchecked string.
createReactNativeDeviceAccess({workerUrl: '/worker.js'});
// @ts-expect-error Entity selection remains typed in the browser entrypoint.
access.get('Cpu');
void [cpu, explicit];
