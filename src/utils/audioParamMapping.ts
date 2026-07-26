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

/**
 * Resolve audio-reactive targets for a generative shader.
 * Uses param `mapping` + `audio` metadata; falls back to positional bands.
 */
export function resolveAudioTargets(shaderEntry: ShaderEntry | undefined): AudioParamTarget[] {
  const params = shaderEntry?.params ?? [];
  const targets: AudioParamTarget[] = [];

  for (let i = 0; i < Math.min(4, params.length); i++) {
    const param = params[i];
    const slotKey = mappingToSlotParamKey(param.mapping, i);
    if (!slotKey) continue;

    const audioSource =
      parseAudioSource(param.audio) ??
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

  if (targets.length === 0) {
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
