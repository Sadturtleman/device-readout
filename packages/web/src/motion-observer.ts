import { AccelerometerEntity, LinearAccelerationEntity, GravityEntity, GyroscopeEntity,
  DeviceReadoutError, ErrorCode, type DeviceAccess, type Vector3 } from '@device-readout/core';

export interface WebMotionEventSource extends EventTarget { readonly ondevicemotion?:unknown; }
export interface WebMotionObservation { close():void; }
let nextTarget=0;
function vector(x:unknown,y:unknown,z:unknown):Vector3|null {
  return typeof x==='number'&&Number.isFinite(x)&&typeof y==='number'&&Number.isFinite(y)&&typeof z==='number'&&Number.isFinite(z)?{x,y,z}:null;
}

/** Attach an application-owned motion source. This never requests permission or reads screen state. */
export function observeWebMotion(access:DeviceAccess,source:WebMotionEventSource):WebMotionObservation {
  if(!('ondevicemotion' in source))throw new DeviceReadoutError(ErrorCode.UnsupportedEntity,'This source does not expose device motion events.');
  const removers:(()=>void)[]=[];let closed=false;
  const close=()=>{if(closed)return;closed=true;source.removeEventListener('pagehide',pagehide);for(const remove of removers)remove();};
  const pagehide=(event:Event)=>{if(!(event as PageTransitionEvent).persisted)close();};
  try {
    for(const kind of [AccelerometerEntity,LinearAccelerationEntity,GravityEntity,GyroscopeEntity]) {
      const target=access.observers.target(kind,`web-motion-${++nextTarget}`);
      removers.push(access.observers.sensorSource(target,{subscribe(session){
        const reading=(raw:Event)=>{
          try {
            const event=raw as DeviceMotionEvent;
            let value:Vector3|null;
            if(kind===GyroscopeEntity){
              const rate=event.rotationRate,rawRate=vector(rate?.alpha,rate?.beta,rate?.gamma);
              value=rawRate?vector(rawRate.x*Math.PI/180,rawRate.y*Math.PI/180,rawRate.z*Math.PI/180):null;
            }else{
              const input=kind===LinearAccelerationEntity?event.acceleration:event.accelerationIncludingGravity;
              value=vector(input?.x,input?.y,input?.z);
              if(kind===GravityEntity){
                const linear=event.acceleration,acceleration=vector(linear?.x,linear?.y,linear?.z);
                value=value&&acceleration?vector(value.x-acceleration.x,value.y-acceleration.y,value.z-acceleration.z):null;
              }
            }
            session.publish({value});
          }catch(error){session.fail(new DeviceReadoutError(ErrorCode.ReadFailed,error instanceof Error?error.message:'Cannot read motion event.'));}
        };
        // DeviceMotion has no frequency option. Preserve every delivered event without resampling.
        source.addEventListener('devicemotion',reading);
        return()=>source.removeEventListener('devicemotion',reading);
      }}));
    }
    source.addEventListener('pagehide',pagehide);
  }catch(error){close();throw error;}
  return Object.freeze({close});
}
