import { DeviceReadoutError, ErrorCode } from './errors.js';
import { normalizeSnapshot, definition } from './normalize.js';
import { schedule } from './timing.js';
import type { EntityAddress } from './entity.js';
import type { Request, Response, Settings } from './protocol.js';
import { ObservedCollector } from './observed-collector.js';
export interface Collector {
  read(entity:EntityAddress,signal:AbortSignal,settings:Settings):Promise<unknown>;
  observe?(entity:EntityAddress,emit:(value:unknown)=>void,fail:(error:unknown)=>void,signal:AbortSignal,settings:Settings):()=>void;
  pollingRequired?(entity:EntityAddress):boolean;
  list?(kind:string,signal:AbortSignal):Promise<readonly string[]>;
  current?(kind:string,signal:AbortSignal):Promise<string|null>;
  describe?(entity:EntityAddress,signal:AbortSignal):Promise<unknown>;
  supports?(entity:EntityAddress):boolean;
}
export interface CollectorPort {send(response:Response):void;listen(listener:(request:Request)=>void):()=>void;}
/** Run this endpoint in a worker or native collection context, never in the host UI path. */
export function serveCollector(collector:Collector,port:CollectorPort):()=>void {
 const observed=new ObservedCollector(collector,response=>port.send(response));collector=observed;
 const running=new Map<number,AbortController>();
 const stop=port.listen(request=>{
   if(request.operation==='observer'||request.operation==='sensor'){observed.update(request);return;}
   if(request.operation==='cancel'){running.get(request.id)?.abort();running.delete(request.id);return;}
   if(!['get','watch','list','current','describe','capabilities','permissions.check','permissions.request'].includes(request.operation)||!request.entity||!request.settings){port.send({id:request.id,type:'error',error:{code:ErrorCode.UnsupportedEntity,message:'Operation unavailable.'}});return;}
   const control=new AbortController();running.set(request.id,control);
   if(request.operation==='watch') {
     const entity=request.entity, settings=request.settings;
     const mode=definition(entity.kind).mode;
     let unsubscribe:(()=>void)|undefined;let cancelPoll:(()=>void)|undefined;let cancelDeadline:(()=>void)|undefined;
     let cancelActivity:(()=>void)|undefined,cancelFailure:(()=>void)|undefined;let sampleControl:AbortController|undefined;
     const cleanup=()=>{cancelActivity?.();cancelFailure?.();sampleControl?.abort();unsubscribe?.();cancelPoll?.();cancelDeadline?.();running.delete(request.id);};
     control.signal.addEventListener('abort',cleanup,{once:true});
     const fail=(error:unknown)=>{if(control.signal.aborted)return;port.send({id:request.id,type:'error',error:{code:error instanceof DeviceReadoutError?error.code:ErrorCode.ReadFailed,message:error instanceof Error?error.message:'Collection failed.'}});control.abort();};
     const emit=(raw:unknown)=>{if(control.signal.aborted)return;try{port.send({id:request.id,type:'snapshot',value:normalizeSnapshot(entity.kind,raw)});}catch(error){fail(error);}};
     const read=async()=>{
       if(control.signal.aborted)return;
       port.send({id:request.id,type:'reading'});
       cancelDeadline=schedule(settings.readTimeoutMs,()=>fail(new DeviceReadoutError(ErrorCode.ReadTimeout,'Read deadline exceeded.')));
       try {const raw=await collector.read(entity,control.signal,settings);cancelDeadline?.();emit(raw);}
       catch(error){fail(error);}
       if(!control.signal.aborted&&(!collector.observe||collector.pollingRequired?.(entity)))cancelPoll=schedule(settings.pollIntervalMs,()=>{void read();});
     };
     const start=()=>{
       if(control.signal.aborted)return;
       const session=new AbortController();sampleControl=session;
       try {
         if(mode==='sample')port.send({id:request.id,type:'reading'});
         if(collector.observe){
           unsubscribe=collector.observe(entity,value=>{if(!session.signal.aborted)emit(value);},error=>{if(!session.signal.aborted)fail(error);},session.signal,settings);
           if(control.signal.aborted||session.signal.aborted)unsubscribe();
         }
         if(mode==='state')void read();
         else if(!collector.observe)fail(new DeviceReadoutError(ErrorCode.UnsupportedEntity,'Sensor observation is unavailable.'));
       } catch(error){fail(error);}
     };
     if(mode==='state')start();
     else {
       try{cancelFailure=observed.onFailure(entity,fail);}catch(error){fail(error);return;}
       const activity=(active:boolean)=>{
         if(active){start();return;}
         sampleControl?.abort();unsubscribe?.();unsubscribe=undefined;cancelDeadline?.();
         port.send({id:request.id,type:'suspended'});
       };
       cancelActivity=observed.onSensorActivity(activity);activity(observed.sensorsActive);
     }
     return;
   }
   void (async()=>{
     try{
       let value:unknown;
       if(request.operation==='permissions.check')value=observed.checkPermission(request.entity!);
       else if(request.operation==='permissions.request')value=await observed.requestPermission(request.entity!,control.signal,()=>port.send({id:request.id,type:'permissionRequest'}));
       else if(request.operation==='list')value=await observed.listBindings(request.entity!.kind,control.signal);
       else if(request.operation==='current')value=await observed.currentBinding(request.entity!.kind,control.signal);
       else if(request.operation==='describe')value=normalizeSnapshot('SensorDescription',await observed.describe(request.entity!,control.signal));
       else if(request.operation==='capabilities')value=observed.capabilities(request.entity!);
       else value=normalizeSnapshot(request.entity!.kind,await collector.read(request.entity!,control.signal,request.settings!));
       if(!control.signal.aborted)port.send({id:request.id,type:'result',value});
     }
     catch(error){if(!control.signal.aborted)port.send({id:request.id,type:'error',error:{code:error instanceof DeviceReadoutError?error.code:ErrorCode.ReadFailed,message:error instanceof Error?error.message:'Collection failed.'}});}
     finally{running.delete(request.id);}
   })();
 });
 return()=>{stop();for(const control of running.values())control.abort();running.clear();};
}
export { DeviceReadoutError, ErrorCode } from './errors.js';
export type { EntityAddress } from './entity.js';
export type { Settings } from './protocol.js';
