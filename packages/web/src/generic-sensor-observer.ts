import { AccelerometerEntity, LinearAccelerationEntity, GravityEntity, GyroscopeEntity, MagnetometerEntity,
  RelativeOrientationEntity, AbsoluteOrientationEntity, IlluminanceEntity, DeviceReadoutError, ErrorCode,
  PermissionStatus as DevicePermissionStatus, type DeviceAccess, type DeviceSnapshot, type Entity, type Vector3, type Quaternion
} from '@device-readout/core';

/** Structural types also work with DOM libraries that do not declare Generic Sensor. */
export interface WebGenericSensor extends EventTarget {
  start():void;
  stop():void;
  readonly x?:number|null;
  readonly y?:number|null;
  readonly z?:number|null;
  readonly quaternion?:readonly number[]|null;
  readonly illuminance?:number|null;
}
export interface WebGenericSensorOptions { readonly frequency?:number; readonly referenceFrame?:'device'; }
export interface WebGenericSensorConstructor { new(options?:WebGenericSensorOptions):WebGenericSensor; }
export interface WebGenericSensorSource extends EventTarget {
  readonly Accelerometer?:WebGenericSensorConstructor;
  readonly LinearAccelerationSensor?:WebGenericSensorConstructor;
  readonly GravitySensor?:WebGenericSensorConstructor;
  readonly Gyroscope?:WebGenericSensorConstructor;
  readonly Magnetometer?:WebGenericSensorConstructor;
  readonly RelativeOrientationSensor?:WebGenericSensorConstructor;
  readonly AbsoluteOrientationSensor?:WebGenericSensorConstructor;
  readonly AmbientLightSensor?:WebGenericSensorConstructor;
}
export interface WebSensorPermissionSource extends EventTarget { readonly state:PermissionState; }
export interface WebGenericSensorPermissions {
  readonly accelerometer?:WebSensorPermissionSource;
  readonly gyroscope?:WebSensorPermissionSource;
  readonly magnetometer?:WebSensorPermissionSource;
  readonly ambientLight?:WebSensorPermissionSource;
}
export interface WebGenericSensorObservation { close():void; }
type Reading=DeviceSnapshot&{readonly value:Vector3|Quaternion|number|null};
type PermissionKey=keyof WebGenericSensorPermissions;
type ConstructorKey=Exclude<keyof WebGenericSensorSource,keyof EventTarget>;
type Descriptor={constructor:ConstructorKey;entity:Entity<Reading>;permissions:readonly PermissionKey[];shape:'vector'|'quaternion'|'light'};
const descriptors:readonly Descriptor[]=[
  {constructor:'Accelerometer',entity:AccelerometerEntity,permissions:['accelerometer'],shape:'vector'},
  {constructor:'LinearAccelerationSensor',entity:LinearAccelerationEntity,permissions:['accelerometer'],shape:'vector'},
  {constructor:'GravitySensor',entity:GravityEntity,permissions:['accelerometer'],shape:'vector'},
  {constructor:'Gyroscope',entity:GyroscopeEntity,permissions:['gyroscope'],shape:'vector'},
  {constructor:'Magnetometer',entity:MagnetometerEntity,permissions:['magnetometer'],shape:'vector'},
  {constructor:'RelativeOrientationSensor',entity:RelativeOrientationEntity,permissions:['accelerometer','gyroscope'],shape:'quaternion'},
  {constructor:'AbsoluteOrientationSensor',entity:AbsoluteOrientationEntity,permissions:['accelerometer','gyroscope','magnetometer'],shape:'quaternion'},
  {constructor:'AmbientLightSensor',entity:IlluminanceEntity,permissions:['ambientLight'],shape:'light'}
];
let nextTarget=0;
const cleanup=(action:()=>void)=>{try{action();}catch{/* Disposed callbacks remain gated if the host remover fails. */}};
function sensorError(error:unknown):DeviceReadoutError {
  if(error instanceof DeviceReadoutError)return error;
  let name:unknown;
  try{name=error&&typeof error==='object'&&'name' in error?error.name:null;}catch{/* A malformed error is still a read failure. */}
  const code=name==='NotAllowedError'||name==='SecurityError'?ErrorCode.PermissionDenied:
    name==='NotSupportedError'?ErrorCode.UnsupportedEntity:ErrorCode.ReadFailed;
  return new DeviceReadoutError(code,'The browser sensor could not provide a reading.');
}
const denied=()=>new DeviceReadoutError(ErrorCode.PermissionDenied,'The application has not observed granted sensor access.');

/** Connect app-supplied constructors and permission observers. No permission query or request is performed. */
export function observeWebGenericSensors(access:DeviceAccess,source:WebGenericSensorSource,
  permissions:WebGenericSensorPermissions):WebGenericSensorObservation {
  if(!source||typeof source.addEventListener!=='function'||typeof source.removeEventListener!=='function')
    throw new DeviceReadoutError(ErrorCode.InvalidConfiguration,'Expected an application-owned sensor source.');
  const removers:(()=>void)[]=[],updates:(()=>void)[]=[];
  const states=new Map<PermissionKey,PermissionState|null>();
  let closed=false,count=0;
  const close=()=>{if(closed)return;closed=true;for(const remove of removers)cleanup(remove);};
  const pagehide=(event:Event)=>{if(!(event as PageTransitionEvent).persisted)close();};
  try {
    for(const descriptor of descriptors){
      const Constructor=source[descriptor.constructor];if(typeof Constructor!=='function')continue;
      const target=access.observers.target(descriptor.entity,'web-generic-'+(++nextTarget));count++;
      removers.push(()=>access.observers.remove(target));
      const failure=access.observers.failureSource(target);
      removers.push(()=>failure.close());
      const sessions=new Set<(error:DeviceReadoutError)=>void>();
      let status:DevicePermissionStatus|null=null;
      updates.push(()=>{
        const values=descriptor.permissions.map(key=>states.get(key));
        status=values.some(value=>value==='denied')?DevicePermissionStatus.Denied:
          values.every(value=>value==='granted')?DevicePermissionStatus.Granted:
          values.some(value=>value==='prompt')?DevicePermissionStatus.NotDetermined:null;
        access.observers.permission(target,status);
        failure.publish(status===DevicePermissionStatus.Granted?null:denied());
        if(status!==DevicePermissionStatus.Granted)for(const fail of [...sessions])fail(denied());
      });
      removers.push(access.observers.sensorSource(target,{subscribe(session){
        if(closed)throw new DeviceReadoutError(ErrorCode.EntityRemoved,'The sensor observer is closed.');
        if(status!==DevicePermissionStatus.Granted)throw denied();
        let sensor:WebGenericSensor|undefined,disposed=false;
        const dispose=()=>{
          if(disposed)return;disposed=true;sessions.delete(fail);session.signal.removeEventListener('abort',dispose);
          if(sensor){const active=sensor;cleanup(()=>active.removeEventListener('reading',reading));
            cleanup(()=>active.removeEventListener('error',failed));cleanup(()=>active.stop());}
        };
        const fail=(error:DeviceReadoutError)=>{if(disposed)return;dispose();session.fail(error);};
        const reading=()=>{
          if(disposed)return;
          try {
            // Only copy the fixed-size native sample; normalization and timestamps belong to the worker.
            let value:Reading['value'];
            if(descriptor.shape==='light')value=sensor!.illuminance??null;
            else if(descriptor.shape==='quaternion'){
              const q=sensor!.quaternion;value=q?.length===4?{x:q[0]!,y:q[1]!,z:q[2]!,w:q[3]!}:null;
            }else value={x:sensor!.x as number,y:sensor!.y as number,z:sensor!.z as number};
            session.publish({value});
          }catch(error){fail(sensorError(error));}
        };
        const failed=(event:Event)=>{try{fail(sensorError((event as Event&{error?:unknown}).error));}
          catch{fail(new DeviceReadoutError(ErrorCode.ReadFailed,'Cannot read sensor error.'));}};
        try {
          sensor=new Constructor({...(descriptor.shape==='light'?{}:{referenceFrame:'device' as const}),
            ...(session.samplingRate.hertz===null?{}:{frequency:session.samplingRate.hertz})});
          if(closed)throw new DeviceReadoutError(ErrorCode.EntityRemoved,'The sensor observer is closed.');
          if(status!==DevicePermissionStatus.Granted)throw denied();
          sessions.add(fail);session.signal.addEventListener('abort',dispose,{once:true});
          sensor.addEventListener('reading',reading);sensor.addEventListener('error',failed);
          if(session.signal.aborted)dispose();else sensor.start();
        }catch(error){dispose();throw sensorError(error);}
        return dispose;
      }}));
    }
    if(count===0)throw new DeviceReadoutError(ErrorCode.UnsupportedEntity,'This source does not expose a supported Generic Sensor.');
    for(const key of ['accelerometer','gyroscope','magnetometer','ambientLight'] as const){
      const permission=permissions?.[key];if(!permission)continue;
      let revision=0;
      const changed=()=>{
        if(closed)return;const current=++revision;let state:PermissionState|null=null;
        try{state=permission.state;}catch{/* Unreadable permission does not authorize collection. */}
        if(current!==revision)return;
        states.set(key,state);
        try{for(const update of updates)update();}catch{close();}
      };
      removers.push(()=>permission.removeEventListener('change',changed));
      permission.addEventListener('change',changed);changed();
    }
    if(!closed){for(const update of updates)update();
      removers.push(()=>source.removeEventListener('pagehide',pagehide));source.addEventListener('pagehide',pagehide);}
  }catch(error){close();throw sensorError(error);}
  return Object.freeze({close});
}
