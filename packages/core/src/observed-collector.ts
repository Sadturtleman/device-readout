import type { Collector } from './collector.js';
import { entityKey as key, type EntityAddress, type TargetBinding } from './entity.js';
import { DeviceReadoutError, ErrorCode } from './errors.js';
import { definition, record } from './normalize.js';
import type { Settings, Request, Response } from './protocol.js';
import { PermissionStatus, permissionStatus } from './permissions.js';
type Listener={emit:(value:unknown)=>void;fail:(error:unknown)=>void};
type State={entity:EntityAddress;removed:boolean;value?:unknown;source?:boolean;description?:Record<string,unknown>};
export class ObservedCollector implements Collector {
 private readonly states=new Map<string,State>();
 private readonly listeners=new Map<string,Set<Listener>>();
 private readonly permissions=new Map<string,unknown>();
 private readonly currentTargets=new Map<string,EntityAddress|null>();
 private readonly failures=new Map<string,DeviceReadoutError>();
 private active=true;
 private readonly activityListeners=new Set<(active:boolean)=>void>();
 get sensorsActive():boolean{return this.active;}
 onSensorActivity(listener:(active:boolean)=>void):()=>void{this.activityListeners.add(listener);return()=>{this.activityListeners.delete(listener);};}
 onFailure(entity:EntityAddress,fail:(error:unknown)=>void):()=>void{
   this.assertAvailable(entity);return this.subscribe(entity,{emit:()=>{},fail});
 }
 private readonly permissionListeners=new Map<string,Set<()=>void>>();
 private nextSession=0;
 private readonly sessions=new Map<number,Listener>();
 constructor(private readonly source:Collector,private readonly send:(response:Response)=>void){}
 update(request:Request):void {
   if(!record(request.value))return;
   if(request.operation==='sensor'){
     const listener=this.sessions.get(request.value.sessionId as number);if(!listener)return;
     const error=request.value.error;
     if(record(error))listener.fail(new DeviceReadoutError(Object.values(ErrorCode).includes(error.code as ErrorCode)?error.code as ErrorCode:ErrorCode.ReadFailed,typeof error.message==='string'?error.message:'Sensor observer failed.'));
     else listener.emit(request.value.values);
     return;
   }
   if(request.value.type==='sensorActivity'){
     const active=request.value.active===true;
     if(this.active!==active){this.active=active;for(const listener of [...this.activityListeners])listener(active);}return;
   }
   if(!request.entity)return;
   const entity=request.entity,k=key(entity),input=request.value;
   if(input.type==='failure'){
     if(input.error===null){this.failures.delete(k);return;}
     if(!record(input.error))return;
     const code=Object.values(ErrorCode).includes(input.error.code as ErrorCode)?input.error.code as ErrorCode:ErrorCode.ReadFailed;
     const failure=new DeviceReadoutError(code,typeof input.error.message==='string'?input.error.message:'Application observer failed.');
     this.failures.set(k,failure);
     for(const state of this.states.values()){
       if(state.entity.kind===entity.kind&&(entity.targetId===undefined||key(state.entity)===k))state.value=undefined;
     }
     for(const [listenerKey,listeners]of this.listeners){
       const [kind]=JSON.parse(listenerKey) as [string,string|null,boolean];
       if(kind===entity.kind&&(entity.targetId===undefined||listenerKey===k)){
         for(const listener of [...listeners])listener.fail(failure);
       }
     }
     return;
   }
   if(input.type==='current'){this.currentTargets.set(entity.kind,typeof input.targetId==='string'?{kind:entity.kind,targetId:input.targetId,observed:input.observed===true}:null);return;}
   if(input.type==='permission'){this.permissions.set(k,input.status);for(const listener of [...(this.permissionListeners.get(k)??[])])listener();return;}
   if(input.type==='register'){if(!this.states.has(k))this.states.set(k,{entity,removed:false});return;}
   if(input.type==='sensorSource'){
     if(!this.states.get(k)?.removed)this.states.set(k,{entity,removed:false,source:true,description:record(input.description)?input.description:{}});
     return;
   }
   if(input.type==='remove'){
     this.states.set(k,{entity,removed:true});
     for(const listener of [...(this.listeners.get(k)??[])])listener.fail(new DeviceReadoutError(ErrorCode.EntityRemoved,'Observed target was removed.'));return;
   }
   if(input.type==='state'){
     if(this.states.get(k)?.removed)return;
     if(!this.active&&definition(entity.kind).mode!=='state')return;
     this.states.set(k,{entity,removed:false,value:input.values});
     if(this.failureFor(entity))return;
     for(const listener of [...(this.listeners.get(k)??[])])listener.emit(input.values);
   }
 }
 private failureFor(entity:EntityAddress):DeviceReadoutError|undefined{
   return this.failures.get(key(entity))??this.failures.get(key({kind:entity.kind}));
 }
 private assertAvailable(entity:EntityAddress):void{
   if(this.states.get(key(entity))?.removed)throw new DeviceReadoutError(ErrorCode.EntityRemoved,'Observed target was removed.');
   const failure=this.failureFor(entity);if(failure)throw failure;
 }
 async read(entity:EntityAddress,signal:AbortSignal,settings:Settings):Promise<unknown>{
   this.assertAvailable(entity);
   if(this.states.get(key(entity))?.source)return this.readSensorSource(entity,signal,settings);
   if(!this.active&&definition(entity.kind).mode!=='state')await new Promise<void>((resolve,reject)=>{
     const abort=()=>{detach();reject(new DOMException('Operation cancelled.','AbortError'));};
     const detach=this.onSensorActivity(active=>{if(active){detach();signal.removeEventListener('abort',abort);resolve();}});
     signal.addEventListener('abort',abort,{once:true});if(signal.aborted)abort();
   });
   const state=this.states.get(key(entity));
   this.assertAvailable(entity);
   if(!state)return this.source.read(entity,signal,settings);
   if(state.removed)return Promise.reject(new DeviceReadoutError(ErrorCode.EntityRemoved,'Observed target was removed.'));
   if(definition(entity.kind).mode==='state'&&state.value!==undefined)return Promise.resolve(state.value);
   return new Promise((resolve,reject)=>{
     const abort=()=>{remove();reject(new DOMException('Operation cancelled.','AbortError'));};
     const remove=this.observe(entity,value=>{remove();signal.removeEventListener('abort',abort);resolve(value);},error=>{remove();signal.removeEventListener('abort',abort);reject(error);},signal,settings);
     signal.addEventListener('abort',abort,{once:true});if(signal.aborted)abort();
   });
 }
 private readSensorSource(entity:EntityAddress,signal:AbortSignal,settings:Settings):Promise<unknown>{
   return new Promise((resolve,reject)=>{
     let settled=false,generation=0,detach:(()=>void)|undefined;
     let activity:(()=>void)|undefined,failures:(()=>void)|undefined;
     const cleanup=()=>{generation++;detach?.();activity?.();failures?.();signal.removeEventListener('abort',abort);};
     const finish=(error:unknown,value?:unknown)=>{if(settled)return;settled=true;cleanup();error?reject(error):resolve(value);};
     const abort=()=>finish(new DOMException('Operation cancelled.','AbortError'));
     const changed=(active:boolean)=>{
       const session=++generation;detach?.();detach=undefined;if(!active||settled)return;
       try {
         detach=this.observe(entity,value=>{if(session===generation)finish(null,value);},error=>finish(error),signal,settings);
         if(settled){detach();detach=undefined;}
       }catch(error){finish(error);}
     };
     failures=this.subscribe(entity,{emit:()=>{},fail:error=>finish(error)});
     activity=this.onSensorActivity(changed);
     signal.addEventListener('abort',abort,{once:true});
     if(signal.aborted)abort();else changed(this.active);
   });
 }
 private subscribe(entity:EntityAddress,listener:Listener):()=>void{
   const k=key(entity);let group=this.listeners.get(k);if(!group){group=new Set();this.listeners.set(k,group);}group.add(listener);
   return()=>{group!.delete(listener);if(!group!.size)this.listeners.delete(k);};
 }
 observe(entity:EntityAddress,emit:(value:unknown)=>void,fail:(error:unknown)=>void,signal:AbortSignal,settings:Settings):()=>void{
   this.assertAvailable(entity);
   const state=this.states.get(key(entity));
   if(state?.removed)throw new DeviceReadoutError(ErrorCode.EntityRemoved,'Observed target was removed.');
   const remove=this.subscribe(entity,{emit,fail});
   let detach:(()=>void)|undefined;
   try {
     if(state?.source){
       const sessionId=++this.nextSession;this.sessions.set(sessionId,{emit,fail});
       detach=()=>{if(this.sessions.delete(sessionId))this.send({id:0,type:'sensorStop',value:{sessionId}});};
       this.send({id:0,type:'sensorStart',value:{sessionId,entity,sensorHertz:settings.sensorHertz}});
     }
     else if(!state&&this.source.observe)detach=this.source.observe(entity,emit,fail,signal,settings);
     else if(!state&&definition(entity.kind).mode!=='state')throw new DeviceReadoutError(ErrorCode.UnsupportedEntity,'Sensor observation unavailable.');
   }catch(error){remove();throw error;}
   return()=>{remove();detach?.();};
 }
 pollingRequired(entity:EntityAddress):boolean{return !this.states.has(key(entity))&&(!this.source.observe||!!this.source.pollingRequired?.(entity));}
 async list(kind:string,signal:AbortSignal):Promise<readonly string[]> {
   return (await this.listBindings(kind,signal)).map(value=>typeof value==='string'?value:value.targetId);
 }
 async listBindings(kind:string,signal:AbortSignal):Promise<readonly TargetBinding[]> {
   this.assertAvailable({kind});
   const states=[...this.states.values()].filter(s=>s.entity.kind===kind&&s.entity.observed===true);
   if(states.length||this.currentTargets.has(kind)&&this.currentTargets.get(kind)===null)return states.filter(s=>!s.removed&&s.entity.targetId!==undefined).map(s=>({targetId:s.entity.targetId!,observed:true}));
   if(this.source.list)return this.source.list(kind,signal);
   throw new DeviceReadoutError(ErrorCode.UnsupportedEntity,'Target discovery unavailable.');
 }
 async current(kind:string,signal:AbortSignal):Promise<string|null>{
   const value=await this.currentBinding(kind,signal);
   return typeof value==='string'?value:value?.targetId??null;
 }
 async currentBinding(kind:string,signal:AbortSignal):Promise<TargetBinding|null>{
   this.assertAvailable({kind});
   if(this.currentTargets.has(kind)){
     const target=this.currentTargets.get(kind)??null;
     if(target===null||this.states.get(key(target))?.removed)return null;
     return target.observed===true?{targetId:target.targetId!,observed:true}:target.targetId!;
   }
   if([...this.states.values()].some(s=>s.entity.kind===kind&&s.entity.observed===true))return null;
   return this.source.current?this.source.current(kind,signal):null;
 }
 async describe(entity:EntityAddress,signal:AbortSignal):Promise<unknown>{
   this.assertAvailable(entity);
   if(definition(entity.kind).mode==='state')throw new DeviceReadoutError(ErrorCode.UnsupportedEntity,'Expected a sensor entity.');
   const state=this.states.get(key(entity));
   if(state?.removed)throw new DeviceReadoutError(ErrorCode.EntityRemoved,'Observed sensor was removed.');
   if(state)return {...state.description,kind:entity.kind};
   if(this.source.describe)return this.source.describe(entity,signal);
   throw new DeviceReadoutError(ErrorCode.UnsupportedEntity,'Sensor description unavailable.');
 }
 capabilities(entity:EntityAddress):{readable:boolean|null;watchable:boolean|null}{
   const state=this.states.get(key(entity));
   const family=entity.targetId===undefined?[...this.states.values()].filter(value=>value.entity.kind===entity.kind):[];
   const readable=state?!state.removed:family.length?family.some(value=>!value.removed):this.source.supports?.(entity)??null;
   const watchable=readable===null?null:readable&&(!!state||family.length>0||definition(entity.kind).mode==='state'||!!this.source.observe);
   return {readable,watchable};
 }
 checkPermission(entity:EntityAddress):PermissionStatus|null{
   const k=key(entity);
   return permissionStatus(this.permissions.get(this.permissions.has(k)?k:key({kind:entity.kind})));
 }
 requestPermission(entity:EntityAddress,signal:AbortSignal,notify:()=>void):Promise<PermissionStatus|null>{
   if(this.checkPermission(entity)===PermissionStatus.Granted)return Promise.resolve(PermissionStatus.Granted);
   return new Promise((resolve,reject)=>{
     const k=key(entity),subscriptions:{key:string;listener:()=>void}[]=[];
     const subscribe=(permissionKey:string,listener:()=>void)=>{
       let listeners=this.permissionListeners.get(permissionKey);
       if(!listeners){listeners=new Set();this.permissionListeners.set(permissionKey,listeners);}
       listeners.add(listener);subscriptions.push({key:permissionKey,listener});
     };
     const cleanup=()=>{
       for(const subscription of subscriptions){
         const listeners=this.permissionListeners.get(subscription.key);listeners?.delete(subscription.listener);
         if(!listeners?.size)this.permissionListeners.delete(subscription.key);
       }
       signal.removeEventListener('abort',abort);
     };
     const listener=()=>{cleanup();resolve(this.checkPermission(entity));};
     const abort=()=>{cleanup();reject(new DOMException('Operation cancelled.','AbortError'));};
     subscribe(k,listener);
     if(entity.targetId!==undefined)subscribe(key({kind:entity.kind}),()=>{if(!this.permissions.has(k))listener();});
     signal.addEventListener('abort',abort,{once:true});
     if(signal.aborted){abort();return;}notify();
   });
 }
}
