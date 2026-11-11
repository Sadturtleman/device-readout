import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

export interface Spec extends TurboModule {
  create(): Promise<string>;
  send(context: string, request: string): Promise<void>;
  next(context: string): Promise<string>;
  dispose(context: string): Promise<void>;
}

export default TurboModuleRegistry.get<Spec>('NativeDeviceReadout');
