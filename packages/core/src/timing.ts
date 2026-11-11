export function schedule(milliseconds:number,action:()=>void):()=>void {
 const deadline=performance.now()+milliseconds;
 let timer:ReturnType<typeof setTimeout>;let cancelled=false;
 const tick=()=>{if(cancelled)return;const remaining=deadline-performance.now();if(remaining<=0){action();return;}timer=setTimeout(tick,Math.min(remaining,2147483647));};
 timer=setTimeout(tick,Math.min(milliseconds,2147483647));
 return()=>{cancelled=true;clearTimeout(timer);};
}
