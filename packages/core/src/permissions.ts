import type { Entity } from './entity.js';
import type { DeviceSnapshot } from './structures.js';
export enum PermissionStatus { Granted='Granted', Denied='Denied', NotDetermined='NotDetermined', Restricted='Restricted', Unavailable='Unavailable' }
export interface PermissionRequest {readonly entity:Entity<DeviceSnapshot>;readonly signal:AbortSignal;}
export type PermissionCoordinator = (request:PermissionRequest)=>void|Promise<void>;
export function permissionStatus(value:unknown):PermissionStatus|null {return Object.values(PermissionStatus).includes(value as PermissionStatus)?value as PermissionStatus:null;}
