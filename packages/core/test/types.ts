import { DeviceAccess, RamEntity, OsEntity, Duration, DisplayEntity, AccelerometerEntity, SensorSamplingRate, type RamSnapshot, type OsSnapshot } from '../dist/index.js';
declare const access: DeviceAccess;
async function consumer(): Promise<void> {
  const ram:RamSnapshot=await access.get(RamEntity);
  const bytes:bigint|null=ram.physicalBytes;
  const os:OsSnapshot=await access.get(OsEntity);
  for await (const sample of access.watch(RamEntity)) { const value:bigint|null=sample.physicalBytes; void value; }
  // @ts-expect-error Entity result types cannot be mixed.
  const wrong:OsSnapshot=await access.get(RamEntity);
  // @ts-expect-error Snapshot fields are immutable.
  ram.physicalBytes=0n;
  // @ts-expect-error String selectors are not entities.
  await access.get('Ram');
  // @ts-expect-error Unitless interval numbers are not accepted.
  access.withPollInterval(1000);
  const configured=access.withPollInterval(Duration.seconds(1));
  const display=access.observers.target(DisplayEntity,'main');
  access.observers.publish(display,{brightness:0.5});
  // @ts-expect-error Input fields remain entity-specific.
  access.observers.publish(display,{physicalBytes:10n});
  const accelerometer=access.observers.target(AccelerometerEntity,'accelerometer');
  access.observers.sensorSource(accelerometer,{subscribe(session){
    const rate:SensorSamplingRate=session.samplingRate;
    session.publish({value:{x:0,y:0,z:9.8}});
    // @ts-expect-error Sensor source values retain their entity-specific fields.
    session.publish({physicalBytes:10n});
    // @ts-expect-error A vector sensor cannot publish a boolean event.
    session.publish({value:true});
    void rate;
  }});
  void [bytes,os,wrong,configured];
}
void consumer;
