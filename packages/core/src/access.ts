import { Duration, SensorSamplingRate, requirePositiveDuration } from './values.js';
import { invalid } from './errors.js';
import { Client } from './client.js';
import type { ConnectionFactory, Settings } from './protocol.js';
import { addressOf, bindEntity, type Entity } from './entity.js';
import type { DeviceSnapshot } from './structures.js';
import { hydrateSnapshot, definition, record } from './normalize.js';
import { ObserverInputs } from './observers.js';
import { permissionStatus, type PermissionStatus } from './permissions.js';
import { DisplayEntity, CpuCoreEntity, BatteryEntity, NetworkInterfaceEntity, StorageVolumeEntity, CellularSubscriptionEntity, TelephonyIdentityEntity, type SensorDescription } from './generated.js';

export interface EntityCapabilities {readonly readable:boolean|null;readonly watchable:boolean|null;}
export interface EntityCollection<S extends DeviceSnapshot> {list(options?:{signal?:AbortSignal}):Promise<readonly Entity<S>[]>;current(options?:{signal?:AbortSignal}):Promise<Entity<S>|null>;}

export class DeviceAccess {
  private readonly client:Client;
  readonly pollInterval: Duration;
  readonly readTimeout: Duration;
  readonly sensorSamplingRate: SensorSamplingRate;
  readonly observers: ObserverInputs;
  readonly permissions:{
    check<S extends DeviceSnapshot>(entity:Entity<S>,options?:{signal?:AbortSignal}):Promise<PermissionStatus|null>;
    request<S extends DeviceSnapshot>(entity:Entity<S>,options?:{signal?:AbortSignal}):Promise<PermissionStatus|null>;
  };
  constructor(private readonly connection: ConnectionFactory, settings?: {
    pollInterval: Duration; readTimeout: Duration; sensorSamplingRate: SensorSamplingRate;
  }, client?:Client) {
    this.client=client??new Client(connection);
    this.observers=new ObserverInputs(this.client);
    this.pollInterval = requirePositiveDuration(settings?.pollInterval ?? Duration.seconds(1));
    this.readTimeout = requirePositiveDuration(settings?.readTimeout ?? Duration.seconds(5));
    this.sensorSamplingRate = settings?.sensorSamplingRate ?? SensorSamplingRate.PlatformDefault;
    if (!(this.sensorSamplingRate instanceof SensorSamplingRate)) invalid('Expected SensorSamplingRate.');
    this.permissions=Object.freeze({
      check:async <S extends DeviceSnapshot>(entity:Entity<S>,options?:{signal?:AbortSignal})=>permissionStatus(await this.client.request({operation:'permissions.check',entity:addressOf(entity,this.client,true),settings:this.settings()},this.readTimeout.milliseconds,options?.signal)),
      request:async <S extends DeviceSnapshot>(entity:Entity<S>,options?:{signal?:AbortSignal})=>permissionStatus(await this.client.request({operation:'permissions.request',entity:addressOf(entity,this.client,true),settings:this.settings()},null,options?.signal,entity))
    });
    Object.freeze(this);
  }
  withPollInterval(interval: Duration): DeviceAccess {
    return new DeviceAccess(this.connection, {...this, pollInterval:requirePositiveDuration(interval)},this.client);
  }
  withReadTimeout(timeout: Duration): DeviceAccess {
    return new DeviceAccess(this.connection, {...this, readTimeout:requirePositiveDuration(timeout)},this.client);
  }
  withSensorSamplingRate(rate: SensorSamplingRate): DeviceAccess {
    if (!(rate instanceof SensorSamplingRate)) invalid('Expected SensorSamplingRate.');
    return new DeviceAccess(this.connection, {...this, sensorSamplingRate:rate},this.client);
  }
  private settings():Settings {return {pollIntervalMs:this.pollInterval.milliseconds,readTimeoutMs:this.readTimeout.milliseconds,sensorHertz:this.sensorSamplingRate.hertz};}
  async get<S extends DeviceSnapshot>(entity:Entity<S>,options?:{signal?:AbortSignal}):Promise<S> {
    const address=addressOf(entity,this.client);
    const value=await this.client.request({operation:'get',entity:address,settings:{...this.settings(),sensorHertz:null}},this.readTimeout.milliseconds,options?.signal);
    return hydrateSnapshot(entity.kind,value) as S;
  }
  close():void {this.client.close();}
  async list<S extends DeviceSnapshot>(kind:Entity<S>,options?:{signal?:AbortSignal}):Promise<readonly Entity<S>[]> {
    const value=await this.client.request({operation:'list',entity:addressOf(kind,this.client,true),settings:this.settings()},this.readTimeout.milliseconds,options?.signal);
    if(!Array.isArray(value))invalid('Invalid discovery response.');
    return Object.freeze(value.map(target=>this.bind(kind,target)));
  }
  private bind<S extends DeviceSnapshot>(kind:Entity<S>,value:unknown):Entity<S> {
    if(typeof value==='string'&&value.length)return bindEntity(kind,value,this.client);
    if(record(value)&&value.observed===true&&typeof value.targetId==='string'&&value.targetId.length)return bindEntity(kind,value.targetId,this.client,true);
    return invalid('Invalid target binding response.');
  }
  private collection<S extends DeviceSnapshot>(kind:Entity<S>):EntityCollection<S>{
    return Object.freeze({list:(options?:{signal?:AbortSignal})=>this.list(kind,options),current:async(options?:{signal?:AbortSignal})=>{
      const value=await this.client.request({operation:'current',entity:addressOf(kind,this.client,true),settings:this.settings()},this.readTimeout.milliseconds,options?.signal);
      return value===null?null:this.bind(kind,value);
    }});
  }
  get displays(){return this.collection(DisplayEntity);}
  get cpuCores(){return this.collection(CpuCoreEntity);}
  get batteries(){return this.collection(BatteryEntity);}
  get networkInterfaces(){return this.collection(NetworkInterfaceEntity);}
  get storageVolumes(){return this.collection(StorageVolumeEntity);}
  get cellularSubscriptions(){return this.collection(CellularSubscriptionEntity);}
  get telephonyIdentities(){return this.collection(TelephonyIdentityEntity);}
  get sensors(){return Object.freeze({list:<S extends DeviceSnapshot>(kind:Entity<S>,options?:{signal?:AbortSignal})=>this.list(kind,options)});}
  async describe<S extends DeviceSnapshot>(sensor:Entity<S>,options?:{signal?:AbortSignal}):Promise<SensorDescription>{
    const value=await this.client.request({operation:'describe',entity:addressOf(sensor,this.client),settings:this.settings()},this.readTimeout.milliseconds,options?.signal);
    return hydrateSnapshot('SensorDescription',value) as SensorDescription;
  }
  get capabilities(){return Object.freeze({get:async<S extends DeviceSnapshot>(entity:Entity<S>,options?:{signal?:AbortSignal}):Promise<EntityCapabilities>=>{
    const value=await this.client.request({operation:'capabilities',entity:addressOf(entity,this.client,true),settings:this.settings()},this.readTimeout.milliseconds,options?.signal);
    return Object.freeze(value as EntityCapabilities);
  }});}
  watch<S extends DeviceSnapshot>(entity:Entity<S>,options?:{signal?:AbortSignal}):AsyncIterable<S> {
    const address=addressOf(entity,this.client);const settings={...this.settings(),sensorHertz:definition(entity.kind).mode==='sample'?this.sensorSamplingRate.hertz:null};const client=this.client;
    return Object.freeze({[Symbol.asyncIterator](){return client.stream({operation:'watch',entity:address,settings},settings.readTimeoutMs,definition(entity.kind).mode==='event',value=>hydrateSnapshot(entity.kind,value) as S,options?.signal);}});
  }
}
