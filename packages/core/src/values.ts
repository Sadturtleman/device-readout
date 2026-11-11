import { invalid } from './errors.js';

export class Duration {
  private constructor(readonly milliseconds: number) { Object.freeze(this); }
  static milliseconds(value: number): Duration {
    if (!Number.isFinite(value) || value < 0) invalid('Duration must be finite and nonnegative.');
    return new Duration(value);
  }
  static seconds(value: number): Duration { return Duration.milliseconds(value * 1000); }
  toJSON(): number { return this.milliseconds; }
}
export class Instant {
  readonly epochMilliseconds: number;
  constructor(value: string | number) {
    const ms = typeof value === 'string' ? Date.parse(value) : value;
    if (!Number.isFinite(ms) || Math.abs(ms) > 8640000000000000) invalid('Invalid instant.');
    this.epochMilliseconds = ms; Object.freeze(this);
  }
  toISOString(): string { return new Date(this.epochMilliseconds).toISOString(); }
  toJSON(): string { return this.toISOString(); }
  toDate(): Date { return new Date(this.epochMilliseconds); }
}
export class SensorSamplingRate {
  static readonly PlatformDefault = new SensorSamplingRate(null);
  private constructor(readonly hertz: number | null) { Object.freeze(this); }
  static hertz(value: number): SensorSamplingRate {
    if (!Number.isFinite(value) || value <= 0) invalid('Frequency must be finite and positive.');
    return new SensorSamplingRate(value);
  }
}
export function hertz(value: number): SensorSamplingRate { return SensorSamplingRate.hertz(value); }
export function requirePositiveDuration(value: Duration): Duration {
  if (!(value instanceof Duration) || value.milliseconds <= 0) invalid('Interval must be a positive Duration.');
  return value;
}
