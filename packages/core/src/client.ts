import type { ConnectionFactory, Transport, Request, Response } from './protocol.js';
import { DeviceReadoutError, ErrorCode, invalid } from './errors.js';
import { AsyncQueue } from './queue.js';
import { schedule } from './timing.js';
import type { PermissionCoordinator } from './permissions.js';
import type { Entity } from './entity.js';
import type { DeviceSnapshot } from './structures.js';
import type { EntityAddress } from './entity.js';
import { SensorSources, type SensorObserverSource } from './sensor-source.js';
import type { ObserverFailureSource } from './failure-source.js';

function observationKey(request:Omit<Request,'id'>):string {
  const input=request.value as {type?:string;ownerId?:number}|undefined,type=input?.type;
  const channel=type==='permission'?'permission':type==='current'?'current':type==='sensorActivity'?'sensorActivity':
    type==='failure'?'failure':type==='failureSource'?'failureSource':'state';
  return JSON.stringify([request.entity?.kind,request.entity?.targetId,request.entity?.observed===true,channel,
    ...(type==='failureSource'?[input?.ownerId]:[])]);
}
type Handler = {response:(response:Response)=>void;fail:(error:unknown)=>void;cleanup:()=>void};
export class Client {
  private transport:Transport|undefined;
  private unlisten:(()=>void)|undefined;
  private closed=false;
  private nextId=0;
  private nextFailureOwner=0;
  private readonly handlers=new Map<number,Handler>();
  private readonly observations=new Map<string,Omit<Request,'id'>>();
  private coordinator:PermissionCoordinator|undefined;
  private readonly sensors=new SensorSources(request=>this.transport?.send(request));
  constructor(private readonly factory:ConnectionFactory) {}
  private connect():Transport {
    if(this.closed)throw new DeviceReadoutError(ErrorCode.EntityRemoved,'DeviceAccess is closed.');
    if(!this.transport){
      this.transport=this.factory.open();
      this.unlisten=this.transport.listen(response=>{if(!this.sensors.handle(response))this.handlers.get(response.id)?.response(response);},error=>this.failAll(error));
      for(const update of this.observations.values())this.transport.send({...update,id:0});
    }
    return this.transport;
  }
  private failAll(error:unknown):void {
    const failure=error instanceof DeviceReadoutError?error:new DeviceReadoutError(ErrorCode.ReadFailed,error instanceof Error?error.message:'Collector disconnected.');
    for(const handler of [...this.handlers.values()])handler.fail(failure);
    this.disconnect();
  }
  private disconnect():void {this.unlisten?.();this.unlisten=undefined;const transport=this.transport;this.transport=undefined;this.sensors.disconnect();transport?.close();}
  close():void {
    if(this.closed)return;this.closed=true;
    try {this.failAll(new DeviceReadoutError(ErrorCode.EntityRemoved,'DeviceAccess is closed.'));}
    finally {this.observations.clear();this.sensors.clear();this.factory.dispose?.();}
  }
  registerSensor<S extends DeviceSnapshot>(entity:EntityAddress,source:SensorObserverSource<S>,description:unknown):()=>void {
    if(this.closed)throw new DeviceReadoutError(ErrorCode.EntityRemoved,'DeviceAccess is closed.');
    const cached=this.observations.get(JSON.stringify([entity.kind,entity.targetId,entity.observed===true,'state']));
    if((cached?.value as {type?:string}|undefined)?.type==='remove')throw new DeviceReadoutError(ErrorCode.EntityRemoved,'Observed sensor target was removed.');
    const detach=this.sensors.register(entity,source);let removed=false;
    this.publish({operation:'observer',entity,value:{type:'sensorSource',description}});
    return()=>{if(removed)return;removed=true;detach();if(!this.closed)this.publish({operation:'observer',entity,value:{type:'remove'}});};
  }
  failureSource(entity:EntityAddress):ObserverFailureSource {
    if(this.closed)throw new DeviceReadoutError(ErrorCode.EntityRemoved,'DeviceAccess is closed.');
    const state=this.observations.get(observationKey({operation:'observer',entity,value:{type:'register'}}));
    if((state?.value as {type?:string}|undefined)?.type==='remove')throw new DeviceReadoutError(ErrorCode.EntityRemoved,'Observed target was removed.');
    if(this.nextFailureOwner>=2147483647)throw new DeviceReadoutError(ErrorCode.ReadFailed,'Failure owner identifiers are exhausted.');
    const ownerId=++this.nextFailureOwner;let released=false;
    const update=(error:DeviceReadoutError|null):Omit<Request,'id'>=>({operation:'observer',entity,
      value:{type:'failureSource',ownerId,error:error===null?null:{code:error.code,message:error.message}}});
    return Object.freeze({
      publish:(error:DeviceReadoutError|null)=>{
        if(released)throw new DeviceReadoutError(ErrorCode.EntityRemoved,'Failure source is closed.');
        if(error!==null&&!(error instanceof DeviceReadoutError))invalid('Expected a DeviceReadoutError or null.');
        this.publish(update(error));
      },
      close:()=>{
        if(released)return;released=true;if(this.closed)return;
        const request=update(null),key=observationKey(request);
        if(!this.observations.has(key))return;
        try{this.publish(request);}finally{this.observations.delete(key);}
      }
    });
  }
  publish(request:Omit<Request,'id'>):void {
    if(this.closed)throw new DeviceReadoutError(ErrorCode.EntityRemoved,'DeviceAccess is closed.');
    const type=(request.value as {type?:string})?.type;
    if((type==='failure'||type==='failureSource')&&(request.value as {error?:unknown}).error!==null&&request.entity){
      for(const [cachedKey,cached]of this.observations){
        if((cached.value as {type?:string})?.type==='state'&&cached.entity?.kind===request.entity.kind
          &&(request.entity.targetId===undefined||cached.entity.targetId===request.entity.targetId&&cached.entity.observed===request.entity.observed)){
          this.observations.set(cachedKey,{...cached,value:{type:'register'}});
        }
      }
    }
    const key=observationKey(request);
    if(type==='register'&&this.observations.has(key))return;
    if((type==='state'||type==='sensorSource')&&(this.observations.get(key)?.value as {type?:string}|undefined)?.type==='remove')return;
    // Replay the latest inputs in publication order: fresh state may arrive while an error is active.
    this.observations.delete(key);
    this.observations.set(key,request);
    this.transport?.send({...request,id:0});
  }
  coordinatePermissions(coordinator:PermissionCoordinator):()=>void {
    if(this.coordinator)throw new DeviceReadoutError(ErrorCode.InvalidConfiguration,'A permission coordinator is already registered.');
    this.coordinator=coordinator;return()=>{if(this.coordinator===coordinator)this.coordinator=undefined;};
  }
  request(request:Omit<Request,'id'>,timeoutMs:number|null,signal?:AbortSignal,permissionEntity?:Entity<DeviceSnapshot>):Promise<unknown> {
    return new Promise((resolve,reject)=>{
      if(signal?.aborted){reject(new DOMException('Operation cancelled.','AbortError'));return;}
      const id=++this.nextId;let cancelTimer:(()=>void)|undefined;let settled=false;
      const coordinatorControl=new AbortController();
      const cleanup=()=>{cancelTimer?.();signal?.removeEventListener('abort',abort);coordinatorControl.abort();this.handlers.delete(id);};
      const finish=(error:unknown,value?:unknown)=>{if(settled)return;settled=true;cleanup();error?reject(error):resolve(value);};
      const cancel=(error:unknown)=>{if(settled)return;try{this.transport?.send({id,operation:'cancel'});}catch{}finish(error);if(!this.handlers.size)this.disconnect();};
      const abort=()=>cancel(new DOMException('Operation cancelled.','AbortError'));
      this.handlers.set(id,{cleanup,fail:error=>finish(error),response:response=>{
        if(response.type==='permissionRequest'){
          if(!this.coordinator||!permissionEntity){cancel(new DeviceReadoutError(ErrorCode.UnsupportedEntity,'Register an application permission coordinator.'));return;}
          try{Promise.resolve(this.coordinator({entity:permissionEntity,signal:coordinatorControl.signal})).catch(error=>cancel(new DeviceReadoutError(ErrorCode.ReadFailed,error instanceof Error?error.message:'Permission coordinator failed.')));}
          catch(error){cancel(new DeviceReadoutError(ErrorCode.ReadFailed,error instanceof Error?error.message:'Permission coordinator failed.'));}return;
        }
        if(response.type==='reading')return;
        if(response.type==='error'){const code=Object.values(ErrorCode).includes(response.error?.code as ErrorCode)?response.error!.code as ErrorCode:ErrorCode.ReadFailed;finish(new DeviceReadoutError(code,response.error?.message??'Collection failed.'));}
        else finish(null,response.value);
      }});
      signal?.addEventListener('abort',abort,{once:true});
      if(timeoutMs!==null)cancelTimer=schedule(timeoutMs,()=>cancel(new DeviceReadoutError(ErrorCode.ReadTimeout,'Read deadline exceeded.')));
      try{this.connect().send({...request,id});}catch(error){finish(error);}
    });
  }
  stream<T>(request:Omit<Request,'id'>,timeoutMs:number,eventOnly:boolean,decode:(value:unknown)=>T,signal?:AbortSignal):AsyncIterableIterator<T> {
    let id:number|undefined;let cancelTimer:(()=>void)|undefined;
    const cleanup=()=>{cancelTimer?.();signal?.removeEventListener('abort',abort);if(id!==undefined)this.handlers.delete(id);};
    const cancel=()=>{if(id!==undefined){try{this.transport?.send({id,operation:'cancel'});}catch{}}cleanup();if(!this.handlers.size)this.disconnect();};
    const fail=(error:unknown)=>{cancel();queue.fail(error);};
    const abort=()=>fail(new DOMException('Operation cancelled.','AbortError'));
    const deadline=()=>{cancelTimer?.();cancelTimer=schedule(timeoutMs,()=>{fail(new DeviceReadoutError(ErrorCode.ReadTimeout,'Read deadline exceeded.'));if(!this.handlers.size)this.disconnect();});};
    const queue=new AsyncQueue<T>(()=>{
      if(signal?.aborted){abort();return;}
      id=++this.nextId;
      this.handlers.set(id,{cleanup,fail,response:response=>{
        if(response.type==='reading'){deadline();return;}
        if(response.type==='suspended'){cancelTimer?.();cancelTimer=undefined;return;}
        if(response.type==='error'){const code=Object.values(ErrorCode).includes(response.error?.code as ErrorCode)?response.error!.code as ErrorCode:ErrorCode.ReadFailed;fail(new DeviceReadoutError(code,response.error?.message??'Collection failed.'));return;}
        if(response.type==='end'){cleanup();queue.finish();return;}
        cancelTimer?.();cancelTimer=undefined;
        try{queue.push(decode(response.value));}catch(error){fail(error);}
      }});
      signal?.addEventListener('abort',abort,{once:true});
      if(!eventOnly)deadline();
      try{this.connect().send({...request,id});}catch(error){fail(error);}
    },cancel);
    return queue;
  }
}
