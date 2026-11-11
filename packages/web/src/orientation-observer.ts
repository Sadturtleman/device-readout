import { RelativeOrientationEntity, AbsoluteOrientationEntity, DeviceReadoutError, ErrorCode,
  type DeviceAccess, type Quaternion } from '@device-readout/core';

export interface WebOrientationEventSource extends EventTarget {
  readonly ondeviceorientation?:unknown;
  readonly ondeviceorientationabsolute?:unknown;
}
export interface WebOrientationObservation { close():void; }
let nextTarget=0;

function quaternion(alpha:unknown,beta:unknown,gamma:unknown):Quaternion|null {
  if(typeof alpha!=='number'||!Number.isFinite(alpha)||typeof beta!=='number'||!Number.isFinite(beta)||
    typeof gamma!=='number'||!Number.isFinite(gamma))return null;
  // Native intrinsic Z-X'-Y'' rotation: device coordinates -> native reference coordinates.
  const z=(alpha%360)*Math.PI/360,x=(beta%360)*Math.PI/360,y=(gamma%360)*Math.PI/360;
  const cz=Math.cos(z),sz=Math.sin(z),cx=Math.cos(x),sx=Math.sin(x),cy=Math.cos(y),sy=Math.sin(y);
  return {x:cz*sx*cy-sz*cx*sy,y:cz*cx*sy+sz*sx*cy,z:sz*cx*cy+cz*sx*sy,w:cz*cx*cy-sz*sx*sy};
}

/** Observe an explicit app source without requesting permission or querying screen orientation. */
export function observeWebOrientation(access:DeviceAccess,source:WebOrientationEventSource):WebOrientationObservation {
  const relative='ondeviceorientation' in source,absolute='ondeviceorientationabsolute' in source;
  if(!relative&&!absolute)throw new DeviceReadoutError(ErrorCode.UnsupportedEntity,'This source does not expose device orientation events.');
  const removers:(()=>void)[]=[];let closed=false;
  const close=()=>{if(closed)return;closed=true;source.removeEventListener('pagehide',pagehide);for(const remove of removers)remove();};
  const pagehide=(event:Event)=>{if(!(event as PageTransitionEvent).persisted)close();};
  const kinds=relative?[RelativeOrientationEntity,AbsoluteOrientationEntity]:[AbsoluteOrientationEntity];
  try {
    for(const kind of kinds){
      const isAbsolute=kind===AbsoluteOrientationEntity;
      const eventName=isAbsolute&&absolute?'deviceorientationabsolute':'deviceorientation';
      const target=access.observers.target(kind,`web-orientation-${++nextTarget}`);
      removers.push(access.observers.sensorSource(target,{subscribe(session){
        const reading=(raw:Event)=>{
          try {
            const event=raw as DeviceOrientationEvent;
            // A generic orientation event may switch to an absolute source. Never relabel its frame.
            const value=event.absolute===isAbsolute?quaternion(event.alpha,event.beta,event.gamma):null;
            session.publish({value});
          }catch(error){session.fail(new DeviceReadoutError(ErrorCode.ReadFailed,error instanceof Error?error.message:'Cannot read orientation event.'));}
        };
        // Native event cadence is browser-owned; there is no sampling-frequency option here.
        source.addEventListener(eventName,reading);
        return()=>source.removeEventListener(eventName,reading);
      }}));
    }
    source.addEventListener('pagehide',pagehide);
  }catch(error){close();throw error;}
  return Object.freeze({close});
}
