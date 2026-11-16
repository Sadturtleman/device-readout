import { Client } from './client.js';
import { addressOf, bindEntity, type Entity } from './entity.js';
import { definition } from './normalize.js';
import { DeviceReadoutError, invalid } from './errors.js';
import { Duration } from './values.js';
import type { DeviceSnapshot } from './structures.js';
import type { PermissionStatus, PermissionCoordinator } from './permissions.js';
import type { SensorObserverSource } from './sensor-source.js';
import type { ObserverFailureSource } from './failure-source.js';
export { PermissionStatus } from './permissions.js';
function encode(value:unknown):unknown {
 if(value instanceof Duration)return value.milliseconds;
 if(value!==null&&typeof value==='object'){
   if(Symbol.iterator in value)return Array.from(value as Iterable<unknown>,encode);
   return Object.fromEntries(Object.entries(value).map(([key,item])=>[key,encode(item)]));
 }return value;
}
/** Inputs from application-owned UI/permission observers. No UI reads or prompts are performed here. */
export class ObserverInputs {
 constructor(private readonly client:Client){Object.freeze(this);}
 /** Feed mobile/web foreground or visibility state from the application's lifecycle observer. */
 sensorActivity(active:boolean):void{
   if(typeof active!=='boolean')invalid('Expected a boolean sensor activity state.');
   this.client.publish({operation:'observer',value:{type:'sensorActivity',active}});
 }
 target<S extends DeviceSnapshot>(kind:Entity<S>,id:string):Entity<S>{
   if(typeof id!=='string'||!id.length||!definition(kind.kind).targeted)invalid('Expected a target identifier and a multi-target entity kind.');
   const collection=addressOf(kind,this.client,true);
   if(collection.targetId!==undefined)invalid('Expected an entity kind.');
   const entity=bindEntity(kind,id,this.client,true);
   this.client.publish({operation:'observer',entity:addressOf(entity,this.client),value:{type:'register'}});
   return entity;
 }
 publish<S extends DeviceSnapshot>(entity:Entity<S>,values:Partial<Omit<S,'collectedAt'>>):void{
   this.client.publish({operation:'observer',entity:addressOf(entity,this.client),value:{type:'state',values:encode(values)}});
 }
 remove<S extends DeviceSnapshot>(entity:Entity<S>):void{
   this.client.publish({operation:'observer',entity:addressOf(entity,this.client),value:{type:'remove'}});
 }
 current<S extends DeviceSnapshot>(kind:Entity<S>,entity:Entity<S>|null):void{
   const collection=addressOf(kind,this.client,true);
   if(!definition(kind.kind).targeted||collection.targetId!==undefined)invalid('Expected a multi-target entity kind.');
   const target=entity===null?null:addressOf(entity,this.client);
   if(target&&target.kind!==collection.kind)invalid('Current target must belong to the same entity kind.');
   this.client.publish({operation:'observer',entity:collection,value:{type:'current',targetId:target?.targetId??null,observed:target?.observed===true}});
 }
 permission<S extends DeviceSnapshot>(entity:Entity<S>,status:PermissionStatus|null):void {
   this.client.publish({operation:'observer',entity:addressOf(entity,this.client,true),value:{type:'permission',status}});
 }
 /** Report an observer-wide read failure for a target or collection; null explicitly clears it. */
 failure<S extends DeviceSnapshot>(entity:Entity<S>,error:DeviceReadoutError|null):void {
   if(error!==null&&!(error instanceof DeviceReadoutError))invalid('Expected a DeviceReadoutError or null.');
   this.client.publish({operation:'observer',entity:addressOf(entity,this.client,true),value:{type:'failure',error:error===null?null:{code:error.code,message:error.message}}});
 }
 /** An independently owned error channel; recovery never clears application or sibling policy. */
 failureSource<S extends DeviceSnapshot>(entity:Entity<S>):ObserverFailureSource {
   return this.client.failureSource(addressOf(entity,this.client,true));
 }
 onPermissionRequest(coordinator:PermissionCoordinator):()=>void {return this.client.coordinatePermissions(coordinator);}
 /** Register an app-owned source; get/watch control each observation and its lifetime. */
 sensorSource<S extends DeviceSnapshot>(entity:Entity<S>,source:SensorObserverSource<S>):()=>void {
   const address=addressOf(entity,this.client);
   if(definition(entity.kind).mode==='state'||typeof source?.subscribe!=='function')invalid('Expected a sensor target and a sensor observation source.');
   return this.client.registerSensor(address,source,encode(source.description??{}));
 }
}
