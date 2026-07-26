import type { ShaderMetadata } from '../services/shaderApi';

const AUDIO_BANDS = new Set(['bass', 'mid', 'treble', 'overall']);
const MAPPINGS = ['zoom_params.x', 'zoom_params.y', 'zoom_params.z', 'zoom_params.w'];

type AudioReactiveMeta = Pick<ShaderMetadata, 'features' | 'params'>;

/** True when shader has full audio-reactive param metadata (attract-pool contract). */
export function isAudioReactiveReady(shader: AudioReactiveMeta): boolean {
  if (!shader.features?.includes('audio-reactive')) {
    return false;
  }
  const params = shader.params;
  if (!params || params.length < 4) {
    return false;
  }
  for (let i = 0; i < 4; i++) {
    const p = params[i];
    if (!p || p.mapping !== MAPPINGS[i] || typeof p.audio !== 'string' || !AUDIO_BANDS.has(p.audio)) {
      return false;
    }
  }
  return true;
}

export function getAudioReactiveBadgeLabel(shader: AudioReactiveMeta): string | null {
  return isAudioReactiveReady(shader) ? 'audio-ready' : null;
}
