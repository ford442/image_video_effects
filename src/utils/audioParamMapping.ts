import { ShaderEntry, SlotParams } from '../renderer/types';

export type AudioBandSource = 'bass' | 'mid' | 'treble' | 'overall';
export type AudioSource = AudioBandSource | { fft: number };

export interface AudioParamTarget {
  slotParamKey: keyof Pick<SlotParams, 'zoomParam1' | 'zoomParam2' | 'zoomParam3' | 'zoomParam4'>;
  audioSource: AudioSource;
  min: number;
  max: number;
  default: number;
}

const ZOOM_MAPPING_TO_SLOT: Record<string, keyof SlotParams> = {
  'zoom_params.x': 'zoomParam1',
  'zoom_params.y': 'zoomParam2',
  'zoom_params.z': 'zoomParam3',
  'zoom_params.w': 'zoomParam4',
};

const FALLBACK_BANDS: AudioBandSource[] = ['bass', 'mid', 'treble', 'overall'];
const SLOT_KEYS: Array<keyof Pick<SlotParams, 'zoomParam1' | 'zoomParam2' | 'zoomParam3' | 'zoomParam4'>> = [
  'zoomParam1',
  'zoomParam2',
  'zoomParam3',
  'zoomParam4',
];

export function parseAudioSource(raw: unknown): AudioSource | null {
  if (raw === 'bass' || raw === 'mid' || raw === 'treble' || raw === 'overall') {
    return raw;
  }
  if (raw && typeof raw === 'object' && 'fft' in raw) {
    const bin = Number((raw as { fft: number }).fft);
    if (Number.isFinite(bin) && bin >= 0 && bin <= 127) {
      return { fft: Math.floor(bin) };
    }
  }
  return null;
}

export function mappingToSlotParamKey(mapping: string | undefined, index: number): keyof SlotParams | null {
  if (mapping && ZOOM_MAPPING_TO_SLOT[mapping]) {
    return ZOOM_MAPPING_TO_SLOT[mapping];
  }
  return SLOT_KEYS[index] ?? null;
}

export interface ResolveAudioTargetsOptions {
  /**
   * Only return params with explicit `audio` metadata (no positional fallback,
   * no synthetic targets). Defaults to true for every category except
   * `generative`, which keeps its historical positional-band behaviour.
   */
  requireExplicit?: boolean;
}

/**
 * Resolve audio-reactive targets for a shader.
 * Uses param `mapping` + `audio` metadata. Generative shaders fall back to
 * positional bands; other categories (simulation, interactive-mouse, graphs)
 * only map params that declare `audio`.
 */
export function resolveAudioTargets(
  shaderEntry: ShaderEntry | undefined,
  options: ResolveAudioTargetsOptions = {},
): AudioParamTarget[] {
  const requireExplicit = options.requireExplicit ?? (shaderEntry?.category !== 'generative');
  const params = shaderEntry?.params ?? [];
  const targets: AudioParamTarget[] = [];

  for (let i = 0; i < Math.min(4, params.length); i++) {
    const param = params[i];
    const slotKey = mappingToSlotParamKey(param.mapping, i);
    if (!slotKey) continue;

    const explicit = parseAudioSource(param.audio);
    if (requireExplicit && !explicit) continue;

    const audioSource =
      explicit ??
      FALLBACK_BANDS[i] ??
      'overall';

    targets.push({
      slotParamKey: slotKey as AudioParamTarget['slotParamKey'],
      audioSource,
      min: param.min ?? 0,
      max: param.max ?? 1,
      default: param.default ?? 0.5,
    });
  }

  if (targets.length === 0 && !requireExplicit) {
    return SLOT_KEYS.map((slotParamKey, i) => ({
      slotParamKey,
      audioSource: FALLBACK_BANDS[i],
      min: 0,
      max: 1,
      default: 0.5,
    }));
  }

  return targets;
}

export function sampleAudioSource(
  source: AudioSource,
  bands: { bass: number; mid: number; treble: number; overall: number },
  fftBins: Float32Array | number[] | null,
): number {
  if (typeof source === 'object' && 'fft' in source) {
    if (!fftBins || fftBins.length === 0) return 0.5;
    const v = fftBins[source.fft] ?? 0;
    return Math.max(0, Math.min(1, v));
  }
  switch (source) {
    case 'bass':
      return bands.bass;
    case 'mid':
      return bands.mid;
    case 'treble':
      return bands.treble;
    case 'overall':
    default:
      return bands.overall;
  }
}

export type AudioBands = { bass: number; mid: number; treble: number; overall: number };

export interface AudioSlotInput {
  slot: number;
  targets: AudioParamTarget[];
  /** Fallback base per target index (shader defaults) when no performer base exists. */
  defaults: number[];
}

export interface ComputeAudioSlotUpdatesInput {
  slots: AudioSlotInput[];
  bands: AudioBands;
  fftBins: Float32Array | number[] | null;
  amount: number;
  /** EMA state keyed `${slot}:${slotParamKey}`; mutated in place. */
  smoothed: Record<string, number>;
  isHeld: (slot: number, key: string) => boolean;
  baseFor: (slot: number, key: string) => number | undefined;
  smoothing?: number;
}

/**
 * Pure per-frame host audio mapping across every active slot. Held params are
 * skipped entirely (their smoothing state is left alone so release is seamless).
 */
export function computeAudioSlotUpdates({
  slots,
  bands,
  fftBins,
  amount,
  smoothed,
  isHeld,
  baseFor,
  smoothing = 0.15,
}: ComputeAudioSlotUpdatesInput): Array<{ slot: number; updates: Partial<SlotParams> }> {
  const out: Array<{ slot: number; updates: Partial<SlotParams> }> = [];
  for (const { slot, targets, defaults } of slots) {
    const updates: Partial<SlotParams> = {};
    let any = false;
    targets.forEach((target, idx) => {
      const key = target.slotParamKey;
      if (isHeld(slot, key)) return;
      const raw = sampleAudioSource(target.audioSource, bands, fftBins);
      const sk = `${slot}:${key}`;
      const prev = smoothed[sk] ?? raw;
      const s = prev + (raw - prev) * smoothing;
      smoothed[sk] = s;
      const base = baseFor(slot, key) ?? defaults[idx] ?? target.default;
      updates[key] = Math.max(target.min, Math.min(target.max, base + (s - 0.5) * amount));
      any = true;
    });
    if (any) out.push({ slot, updates });
  }
  return out;
}
