import type { DeviceSnapshot } from './structures.js';
import type { SensorDescription } from './generated.js';
import type { EntityAddress } from './entity.js';
import type { Request, Response } from './protocol.js';
import { DeviceReadoutError, ErrorCode } from './errors.js';
import { SensorSamplingRate } from './values.js';
import { record } from './normalize.js';

/** A single app-owned observation. Callbacks should only copy native samples. */
export interface SensorObserverSession<S extends DeviceSnapshot> {
  readonly samplingRate:SensorSamplingRate;
  readonly signal:AbortSignal;
  publish(values:Partial<Omit<S,'collectedAt'>>):void;
  fail(error:DeviceReadoutError):void;
}
export interface SensorObserverSource<S extends DeviceSnapshot> {
  readonly description?:Partial<Omit<SensorDescription,'kind'|'collectedAt'>>;
  /** Must not request permission or perform blocking work. Return native listener cleanup. */
  subscribe(session:SensorObserverSession<S>):void|(()=>void);
}
type Source={subscribe(session:SensorObserverSession<DeviceSnapshot>):void|(()=>void)};
const key=(entity:EntityAddress)=>JSON.stringify([entity.kind,entity.targetId??null,entity.observed===true]);

/** Host-side subscription ownership; samples are normalized only in the collector worker. */
export class SensorSources {
  private readonly sources=new Map<string,Source>();
  private readonly sessions=new Map<number,{source:Source;close:()=>void}>();
  constructor(private readonly send:(request:Request)=>void){}
  register<S extends DeviceSnapshot>(entity:EntityAddress,source:SensorObserverSource<S>):()=>void {
    const k=key(entity);
    if(this.sources.has(k))throw new DeviceReadoutError(ErrorCode.InvalidConfiguration,'A sensor source is already registered for this target.');
    const entry=source as Source;this.sources.set(k,entry);
    return()=>{
      if(this.sources.get(k)!==entry)return;
      this.sources.delete(k);
      for(const session of [...this.sessions.values()])if(session.source===entry)session.close();
    };
  }
  handle(response:Response):boolean {
    if(response.type!=='sensorStart'&&response.type!=='sensorStop')return false;
    const input=response.value;
    if(!record(input)||!Number.isSafeInteger(input.sessionId))return true;
    const id=input.sessionId as number;
    if(response.type==='sensorStop'){this.sessions.get(id)?.close();return true;}
    if(!record(input.entity)||typeof input.entity.kind!=='string')return true;
    const source=this.sources.get(key(input.entity as unknown as EntityAddress));
    const error=(failure:unknown)=>{
      const e=failure instanceof DeviceReadoutError?failure:new DeviceReadoutError(ErrorCode.ReadFailed,failure instanceof Error?failure.message:'Application sensor observer failed.');
      this.send({id:0,operation:'sensor',value:{sessionId:id,error:{code:e.code,message:e.message}}});
    };
    if(!source){error(new DeviceReadoutError(ErrorCode.EntityRemoved,'Application sensor source was removed.'));return true;}
    this.sessions.get(id)?.close();
    const control=new AbortController();let disposed=false;let cleanup:(()=>void)|void;
    const dispose=()=>{if(cleanup){const fn=cleanup;cleanup=undefined;try{fn();}catch{ /* A disposed source cannot fail a completed stream. */ }}};
    const close=()=>{if(disposed)return;disposed=true;this.sessions.delete(id);control.abort();dispose();};
    this.sessions.set(id,{source,close});
    const fail=(failure:unknown)=>{if(disposed)return;try{error(failure);}finally{close();}};
    try {
      cleanup=source.subscribe(Object.freeze({
        samplingRate:input.sensorHertz===null?SensorSamplingRate.PlatformDefault:SensorSamplingRate.hertz(input.sensorHertz as number),
        signal:control.signal,
        publish:(values:unknown)=>{if(!disposed)try{this.send({id:0,operation:'sensor',value:{sessionId:id,values}});}catch(e){fail(e);}},
        fail
      }));
      if(disposed)dispose();
    }catch(e){fail(e);}
    return true;
  }
  disconnect():void {for(const session of [...this.sessions.values()])session.close();}
  clear():void {this.disconnect();this.sources.clear();}
}
