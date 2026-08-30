import type { SourceGainStatus } from './types';

export interface SourceGainGate {
  toggleOn: boolean;
  gpuComputeAvailable: boolean;
  physicsPinned: boolean;
  killSwitch: boolean;
}

/**
 * Whether to encode apply_gain_2d onto the catalog source this frame.
 * Default visual path: toggle off → skip.
 */
export function shouldEncodeSourceGain(opts: SourceGainGate): boolean {
  if (!opts.toggleOn) return false;
  if (opts.killSwitch) return false;
  if (!opts.gpuComputeAvailable) return false;
  if (opts.physicsPinned) return false;
  return true;
}

export function sourceGainStatus(opts: SourceGainGate): SourceGainStatus {
  if (!opts.toggleOn || opts.killSwitch || !opts.gpuComputeAvailable) return 'off';
  if (opts.physicsPinned) return 'skipped-physics';
  return 'on';
}
