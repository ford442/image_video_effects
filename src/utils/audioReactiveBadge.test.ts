import { getAudioReactiveBadgeLabel, isAudioReactiveReady } from '../utils/audioReactiveBadge';

describe('audioReactiveBadge', () => {
  it('returns badge when audio-reactive feature and 4 mapped params', () => {
    const shader = {
      features: ['audio-reactive'],
      params: [
        { id: 'p0', name: 'P0', default: 0.5, min: 0, max: 1, mapping: 'zoom_params.x', audio: 'bass' as const },
        { id: 'p1', name: 'P1', default: 0.5, min: 0, max: 1, mapping: 'zoom_params.y', audio: 'mid' as const },
        { id: 'p2', name: 'P2', default: 0.5, min: 0, max: 1, mapping: 'zoom_params.z', audio: 'treble' as const },
        { id: 'p3', name: 'P3', default: 0.5, min: 0, max: 1, mapping: 'zoom_params.w', audio: 'overall' as const },
      ],
    };
    expect(isAudioReactiveReady(shader)).toBe(true);
    expect(getAudioReactiveBadgeLabel(shader)).toBe('audio-ready');
  });

  it('returns null when metadata incomplete', () => {
    const shader = {
      features: ['audio-reactive'],
      params: [{ id: 'p0', name: 'P0', default: 0.5, min: 0, max: 1, mapping: 'zoom_params.x', audio: 'bass' as const }],
    };
    expect(getAudioReactiveBadgeLabel(shader)).toBeNull();
  });
});
