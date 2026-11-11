import type { DeviceAccess } from '@device-readout/core';

export interface WebSensorActivitySource extends EventTarget {
  readonly visibilityState:DocumentVisibilityState;
  readonly defaultView?:EventTarget|null;
}
export interface WebSensorActivityObservation { close():void; }

/** One app-owned visibility observer per SDK context. SDK queries never read Document. */
export function observeWebSensorActivity(access:DeviceAccess,source:WebSensorActivitySource):WebSensorActivityObservation {
  const lifecycle=source.defaultView;let closed=false;
  const detach=()=>{
    source.removeEventListener('visibilitychange',refresh);
    lifecycle?.removeEventListener('pagehide',hide);lifecycle?.removeEventListener('pageshow',refresh);
  };
  const publish=(active:boolean)=>{
    if(closed)return;
    try{access.observers.sensorActivity(active);}catch{closed=true;detach();}
  };
  const refresh=()=>{if(closed)return;try{publish(source.visibilityState==='visible');}catch{publish(false);}};
  const hide=()=>publish(false);
  const close=()=>{if(closed)return;publish(false);closed=true;detach();};
  access.observers.sensorActivity(source.visibilityState==='visible');
  source.addEventListener('visibilitychange',refresh);
  lifecycle?.addEventListener('pagehide',hide);lifecycle?.addEventListener('pageshow',refresh);
  return Object.freeze({close});
}
