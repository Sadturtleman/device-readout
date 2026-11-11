import {createWebDeviceAccess, observeWebViewport, observeWebDisplays, observeWebMotion, observeWebSensorActivity, type WebViewportObservation, type WebScreenDetails, type WebDisplayObservation} from '../dist/index.js';
import {DeviceReadoutError, ErrorCode, DisplayEntity, AccelerometerEntity, type DisplaySnapshot, type ViewportSnapshot, type RamSnapshot, type Vector3} from '@device-readout/core';
import {observeWebOrientation, type WebOrientationObservation} from '../dist/index.js';
import {RelativeOrientationEntity, AbsoluteOrientationEntity, type Quaternion} from '@device-readout/core';

async function consumeOrientation(source:Window):Promise<void> {
  const access=createWebDeviceAccess();
  const orientation:WebOrientationObservation=observeWebOrientation(access,source);
  for(const kind of [RelativeOrientationEntity,AbsoluteOrientationEntity]){
    const [target]=await access.sensors.list(kind);
    if(target){const value:Quaternion|null=(await access.get(target)).value;void value;}
  }
  // @ts-expect-error The application supplies its native event source explicitly.
  observeWebOrientation(access);
  orientation.close();access.close();
}
void consumeOrientation;

async function consumeMotion(source:Window):Promise<void> {
  const access=createWebDeviceAccess(),activity=observeWebSensorActivity(access,source.document),motion=observeWebMotion(access,source);
  const [target]=await access.sensors.list(AccelerometerEntity);
  if(target){const value:Vector3|null=(await access.get(target)).value;void value;}
  // @ts-expect-error A motion observer needs an explicit application source.
  observeWebMotion(access);
  motion.close();activity.close();access.close();
}
void consumeMotion;

async function consumeViewport(source: Window): Promise<void> {
  const access = createWebDeviceAccess();
  const observer: WebViewportObservation = observeWebViewport(access, source);
  const snapshot: ViewportSnapshot = await access.get(observer.entity);
  const width: number | undefined = snapshot.size?.width;
  for await (const update of access.watch(observer.entity)) {
    const scale: number | null = update.visualViewportScale;
    void scale;
    break;
  }
  // @ts-expect-error A viewport entity cannot return another entity's snapshot.
  const wrong: RamSnapshot = await access.get(observer.entity);
  // @ts-expect-error Snapshot values remain immutable.
  snapshot.visualViewportScale = 2;
  // @ts-expect-error An application must supply its Window explicitly.
  observeWebViewport(access);
  observer.close();
  access.close();
  void [width, wrong];
}
void consumeViewport;

async function consumeDisplays(source: Window, details: WebScreenDetails, permission: PermissionStatus): Promise<void> {
  const access = createWebDeviceAccess();
  const observer: WebDisplayObservation = observeWebDisplays(access, source, details, {permission});
  const [display] = await access.displays.list();
  if (display) {
    const snapshot: DisplaySnapshot = await access.get(display);
    const primary: boolean | null = snapshot.primary;
    // @ts-expect-error Display handles retain their snapshot type.
    const wrong: ViewportSnapshot = await access.get(display);
    void [primary, wrong];
  }
  access.observers.failure(DisplayEntity, new DeviceReadoutError(ErrorCode.ReadFailed, 'Application observer failed.'));
  access.observers.failure(DisplayEntity, null);
  // @ts-expect-error Untyped native errors must be mapped by the app's observer adapter.
  access.observers.failure(DisplayEntity, new Error('Native error'));
  // @ts-expect-error An app must supply screen details rather than a request callback.
  observeWebDisplays(access, source, () => Promise.resolve(details));
  observer.close();access.close();
}
void consumeDisplays;
