import { TurboModuleRegistry } from 'react-native';
import { DeviceReadoutError, ErrorCode } from '@device-readout/core';
import { createNativeDeviceAccess } from './native-connection';
import type { Spec } from './specs/NativeDeviceReadout';
export * from '@device-readout/core';

/** Construction is inert; lookup and native context creation begin on the first operation. */
export function createReactNativeDeviceAccess() {
  let native:Spec|undefined;
  const module=()=>{
    native??=TurboModuleRegistry.get<Spec>('NativeDeviceReadout')??undefined;
    if(!native)throw new DeviceReadoutError(ErrorCode.UnsupportedEntity,'DeviceReadout native binding is unavailable on this platform.');
    return native;
  };
  return createNativeDeviceAccess({
    create:()=>module().create(),
    send:(context,request)=>module().send(context,request),
    next:context=>module().next(context),
    dispose:context=>module().dispose(context)
  });
}
