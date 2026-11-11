export enum ErrorCode {
  UnsupportedEntity = 'UnsupportedEntity', PermissionDenied = 'PermissionDenied',
  EntityRemoved = 'EntityRemoved', ReadTimeout = 'ReadTimeout', ReadFailed = 'ReadFailed',
  InvalidConfiguration = 'InvalidConfiguration', Cancelled = 'Cancelled'
}
export class DeviceReadoutError extends Error {
  constructor(readonly code: ErrorCode, message: string) { super(message); this.name = code; }
}
export function invalid(message: string): never { throw new DeviceReadoutError(ErrorCode.InvalidConfiguration, message); }
