import { DeviceAccess, DeviceReadoutError, ErrorCode, serializeSnapshot, type ConnectionFactory, type Transport } from '@device-readout/core';

/** Asynchronous platform ABI. Implementations enqueue collection off the app/JS execution path. */
export interface NativeDeviceReadout {
  create(): Promise<string>;
  send(context: string, request: string): Promise<void>;
  next(context: string): Promise<string>;
  dispose(context: string): Promise<void>;
}
type Message = Parameters<Transport['send']>[0];
type Response = Parameters<Parameters<Transport['listen']>[0]>[0];
type Listener = {message:(response:Response)=>void;error:(error:unknown)=>void};

/** Platform adapter seam; applications normally use createReactNativeDeviceAccess. */
export function createNativeDeviceAccess(native: NativeDeviceReadout): DeviceAccess {
  let context:Promise<string>|undefined, disposed=false, failure:DeviceReadoutError|undefined;
  let listener:Listener|undefined;
  let queued=0, sending=Promise.resolve();
  const normalize=(error:unknown)=>error instanceof DeviceReadoutError?error:new DeviceReadoutError(ErrorCode.ReadFailed,error instanceof Error?error.message:'Native transport failed.');
  const fail=(error:unknown)=>{if(disposed)return;failure??=normalize(error);listener?.error(failure);};
  const start=()=>{
    if(!context){
      context=Promise.resolve().then(()=>native.create());
      void context.then(async id=>{
        try {
          while(!disposed){
            const json=await native.next(id);
            if(disposed)return;
            if(typeof json!=='string'||json.length>262144)throw new Error('Invalid native response size.');
            const response=JSON.parse(json) as Response;
            if(!response||!Number.isSafeInteger(response.id)||typeof response.type!=='string')throw new Error('Invalid native response.');
            if(response.id===0&&response.type==='error')throw new DeviceReadoutError(ErrorCode.ReadFailed,response.error?.message??'Observer input failed.');
            listener?.message(response);
          }
        } catch(error){fail(error);}
      },fail);
    }
    return context;
  };
  const submit=(request:Message)=>{
    if(queued>=256)throw new DeviceReadoutError(ErrorCode.ReadFailed,'Native request queue is full.');
    const json=serializeSnapshot(request);
    if(json.length>262144)throw new DeviceReadoutError(ErrorCode.InvalidConfiguration,'Native request is too large.');
    const pending=start();queued++;
    // Preserve observer-publication ordering even while native context creation is pending.
    sending=sending.then(async()=>{const id=await pending;if(!disposed)await native.send(id,json);}).catch(fail).finally(()=>{queued--;});
  };
  const factory:ConnectionFactory={
    open(){
      if(disposed)throw new DeviceReadoutError(ErrorCode.EntityRemoved,'Native context is closed.');
      if(failure)throw failure;
      let closed=false, current:Listener|undefined;
      const active=new Set<number>();
      return {
        send(request){
          if(closed)throw new DeviceReadoutError(ErrorCode.EntityRemoved,'Native connection is closed.');
          if(request.operation==='cancel')active.delete(request.id);
          else if(request.id!==0)active.add(request.id);
          submit(request);
        },
        listen(message,error){
          current={message(response){
            if(response.type==='result'||response.type==='error'||response.type==='end')active.delete(response.id);
            message(response);
          },error};
          listener=current;
          return()=>{if(listener===current)listener=undefined;};
        },
        close(){
          if(closed)return;closed=true;
          if(listener===current)listener=undefined;
          for(const id of active){try{submit({id,operation:'cancel'});}catch(error){fail(error);}}
          active.clear();
        }
      };
    },
    dispose(){
      if(disposed)return;disposed=true;listener=undefined;
      if(context)void context.then(id=>native.dispose(id)).catch(()=>{});
    }
  };
  return new DeviceAccess(factory);
}
