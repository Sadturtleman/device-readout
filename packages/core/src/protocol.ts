import type { EntityAddress } from './entity.js';
export interface Settings { readonly pollIntervalMs:number;readonly readTimeoutMs:number;readonly sensorHertz:number|null; }
export interface Request {id:number;operation:'get'|'watch'|'cancel'|'list'|'current'|'describe'|'capabilities'|'permissions.check'|'permissions.request'|'observer'|'sensor';entity?:EntityAddress;settings?:Settings;value?:unknown;}
export interface Response {id:number;type:'result'|'snapshot'|'reading'|'suspended'|'permissionRequest'|'sensorStart'|'sensorStop'|'error'|'end';value?:unknown;error?:{code:string;message:string};}
export interface Transport {
 send(message:Request):void;
 listen(message:(response:Response)=>void,error:(error:unknown)=>void):()=>void;
 close():void;
}
export interface ConnectionFactory {
 open():Transport;
 /** Final context cleanup, distinct from ending one transport connection. Must be nonblocking. */
 dispose?():void;
}
