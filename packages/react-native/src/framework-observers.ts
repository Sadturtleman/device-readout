import {DeviceReadoutError, ErrorCode, ViewportEntity, type DeviceAccess, type Entity, type ViewportSnapshot} from '@device-readout/core';

export interface ReactNativeWindowMetrics {readonly width:number;readonly height:number;readonly fontScale:number;}
export interface ReactNativeDimensionsSource {
  get(name:'window'):ReactNativeWindowMetrics;
  addEventListener(type:'change',listener:(event:{window:ReactNativeWindowMetrics})=>void):{remove():void};
}
export interface ReactNativeViewportObservation {readonly entity:Entity<ViewportSnapshot>;close():void;}
export interface ReactNativeAppStateSource {
  readonly currentState:string|null|undefined;
  addEventListener(type:'change',listener:(state:string)=>void):{remove():void};
}
export enum ReactNativeSensorActivityPolicy {
  ForegroundOnly = 'ForegroundOnly',
  AllowInactive = 'AllowInactive',
}
export interface ReactNativeSensorActivityObservation {close():void;}

let nextViewport=0;
type Subscription={remove():void};
function remove(subscription:Subscription|undefined):void {try{subscription?.remove();}catch{/* Disposed callbacks remain gated even if a host remover fails. */}}
function failure(error:unknown):DeviceReadoutError {
  return error instanceof DeviceReadoutError?error:new DeviceReadoutError(ErrorCode.ReadFailed,'Cannot attach the React Native observer.');
}
function optional<T>(read:()=>T):T|null {try{return read();}catch{return null;}}
function number(value:unknown,positive=false):number|null {
  return typeof value==='number'&&Number.isFinite(value)&&(positive?value>0:value>=0)?value:null;
}

/** Explicit app-owned Dimensions connection. Only setup reads get('window'); changes copy their payload. */
export function observeReactNativeViewport(access:DeviceAccess,source:ReactNativeDimensionsSource):ReactNativeViewportObservation {
  if(!source||typeof source.get!=='function'||typeof source.addEventListener!=='function')
    throw new DeviceReadoutError(ErrorCode.InvalidConfiguration,'Expected an application-owned Dimensions source.');
  const entity=access.observers.target(ViewportEntity,`rn-viewport-${++nextViewport}`);
  let closed=false,revision=0,subscription:Subscription|undefined;
  const detach=()=>{const current=subscription;subscription=undefined;remove(current);};
  const close=()=>{
    if(closed)return;closed=true;detach();
    try{access.observers.remove(entity);}catch{/* The SDK context may already be closed or disconnected. */}
  };
  const publish=(metrics:ReactNativeWindowMetrics|null)=>{
    if(closed)return;
    const size=optional(()=>{
      const width=number(metrics?.width),height=number(metrics?.height);
      return width===null||height===null?null:{width,height};
    });
    try {
      access.observers.publish(entity,{size,textScaleFactor:optional(()=>number(metrics?.fontScale,true)),
        visualViewportSize:null,visualViewportScale:null,safeAreaInsets:null});
    }catch{close();}
  };
  const changed=(event:{window:ReactNativeWindowMetrics})=>{
    if(closed)return;revision++;publish(optional(()=>event.window));
  };
  try {
    const before=revision;
    subscription=source.addEventListener('change',changed);
    if(closed)detach();
    else if(revision===before){
      const initial=source.get('window');
      if(revision===before)publish(initial);
    }
  }catch(error){close();throw failure(error);}
  return Object.freeze({entity,close});
}

/** One app lifecycle owner per SDK context. Ignores focus/blur; dispose before closing the SDK. */
export function observeReactNativeSensorActivity(access:DeviceAccess,source:ReactNativeAppStateSource,
  policy:ReactNativeSensorActivityPolicy=ReactNativeSensorActivityPolicy.ForegroundOnly):ReactNativeSensorActivityObservation {
  if(!source||typeof source.addEventListener!=='function'||!Object.values(ReactNativeSensorActivityPolicy).includes(policy))
    throw new DeviceReadoutError(ErrorCode.InvalidConfiguration,'Expected an app-state source and a typed sensor activity policy.');
  let closed=false,published=false,revision=0,subscription:Subscription|undefined;
  const detach=()=>{const current=subscription;subscription=undefined;remove(current);};
  const close=()=>{
    if(closed)return;closed=true;detach();
    if(published)try{access.observers.sensorActivity(false);}catch{/* The context may already have ended. */}
  };
  const publish=(state:string|null|undefined)=>{
    if(closed)return;
    const active=state==='active'||policy===ReactNativeSensorActivityPolicy.AllowInactive&&state==='inactive';
    try{access.observers.sensorActivity(active);published=true;}catch{close();}
  };
  const changed=(state:string)=>{if(closed)return;revision++;publish(state);};
  try {
    const before=revision;
    subscription=source.addEventListener('change',changed);
    if(closed)detach();
    else if(revision===before){
      const initial=source.currentState;
      if(revision===before)publish(initial);
    }
  }catch(error){close();throw failure(error);}
  return Object.freeze({close});
}
