import { DeviceReadoutError, ErrorCode } from './errors.js';
export class AsyncQueue<T> implements AsyncIterableIterator<T> {
 private readonly values:T[]=[];
 private readonly waiting:Array<{resolve:(value:IteratorResult<T>)=>void;reject:(error:unknown)=>void}>=[];
 private ended=false;private failure:unknown;private started=false;
 constructor(private readonly start:()=>void,private readonly cancel:()=>void){}
 [Symbol.asyncIterator]():AsyncIterableIterator<T>{return this;}
 next():Promise<IteratorResult<T>> {
   if(!this.started&&!this.ended){this.started=true;try{this.start();}catch(error){this.fail(error);}}
   if(this.values.length)return Promise.resolve({value:this.values.shift()!,done:false});
   if(this.failure)return Promise.reject(this.failure);
   if(this.ended)return Promise.resolve({value:undefined,done:true});
   return new Promise((resolve,reject)=>this.waiting.push({resolve,reject}));
 }
 push(value:T):void {
   if(this.ended)return;const waiter=this.waiting.shift();
   if(waiter){waiter.resolve({value,done:false});return;}
   if(this.values.length>=2048){this.fail(new DeviceReadoutError(ErrorCode.ReadFailed,'Consumer cannot keep up with the bounded delivery queue.'));this.cancel();return;}
   this.values.push(value);
 }
 fail(error:unknown):void{if(this.ended)return;this.failure=error;this.ended=true;this.values.length=0;for(const w of this.waiting.splice(0))w.reject(error);}
 finish():void{if(this.ended)return;this.ended=true;for(const w of this.waiting.splice(0))w.resolve({value:undefined,done:true});}
 return():Promise<IteratorResult<T>>{this.values.length=0;this.failure=undefined;this.cancel();this.finish();return Promise.resolve({value:undefined,done:true});}
}
