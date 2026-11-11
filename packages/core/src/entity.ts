import { invalid } from './errors.js';
import type { DeviceSnapshot } from './structures.js';
declare const snapshotType: unique symbol;
export interface Entity<S extends DeviceSnapshot> { readonly kind: string; readonly [snapshotType]: S; }
export interface EntityAddress { readonly kind: string; readonly targetId?: string; readonly observed?: boolean; }
export type TargetBinding = string | {readonly targetId:string;readonly observed:true};
export const entityKey=(entity:EntityAddress):string=>JSON.stringify([entity.kind,entity.targetId??null,entity.observed===true]);
interface Binding { address: EntityAddress; targeted: boolean; owner?: object; }
const bindings = new WeakMap<object, Binding>();
export function defineEntity<S extends DeviceSnapshot>(kind:string, targeted:boolean):Entity<S> {
  const entity = Object.freeze({kind}) as Entity<S>;
  bindings.set(entity,{address:{kind},targeted}); return entity;
}
export function addressOf<S extends DeviceSnapshot>(entity:Entity<S>, owner:object, forList=false):EntityAddress {
  const binding = bindings.get(entity);
  if (!binding) invalid('Expected a generated Entity or a discovered entity handle.');
  if (binding.owner && binding.owner !== owner) invalid('Entity handle belongs to another DeviceAccess context.');
  if (binding.targeted && !binding.address.targetId && !forList) invalid('Discover a target with list/current before reading this entity.');
  return binding.address;
}
export function bindEntity<S extends DeviceSnapshot>(entity:Entity<S>,targetId:string,owner:object,observed=false):Entity<S> {
  const handle = Object.freeze({kind:entity.kind}) as Entity<S>;
  bindings.set(handle,{address:{kind:entity.kind,targetId,...(observed?{observed:true}:{})},targeted:true,owner}); return handle;
}
