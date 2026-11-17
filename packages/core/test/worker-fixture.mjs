import { parentPort, workerData } from 'node:worker_threads';
import { serveCollector } from '../dist/collector.js';
let sensorSubscriptions=0;
const collector={
  read: async entity => {
    if(workerData.completionBoundary) return {
      get downlinkBps() {
        const end=Date.now()+25;
        while(Date.now()<end) { /* Lazy collector field work belongs to the worker. */ }
        return Date.now();
      },
      browserOnline:false
    };
    if (workerData.blockMs) {
      const end = Date.now() + workerData.blockMs;
      while (Date.now() < end) { /* Deliberately hostile OS collector fixture. */ }
    }
    return workerData.snapshots?.[entity.kind] ?? {physicalBytes:'9007199254740993', availableBytes:'0', lowMemory:false};
  }
};
if(workerData.targets)collector.list=async()=>workerData.targets;
if(workerData.nativeSensor){
  collector.list=async()=>['motion'];
  collector.pollingRequired=entity=>entity.kind!=='Accelerometer';
  collector.observe=(entity,emit)=>{
    if(entity.kind!=='Accelerometer')return()=>{};
    const session=++sensorSubscriptions;
    const timer=setInterval(()=>emit({value:{x:session,y:0,z:0}}),40);
    return()=>clearInterval(timer);
  };
}
serveCollector(collector, {send: m => parentPort.postMessage(m), listen: f => {parentPort.on('message',f);return()=>parentPort.off('message',f);}});
