import { resolveAudioTargets, sampleAudioSource, mappingToSlotParamKey } from './audioParamMapping';
import { ShaderEntry } from '../renderer/types';

describe('audioParamMapping', () => {
  const shader: ShaderEntry = {
    id: 'test',
    name: 'Test',
    url: 'shaders/test.wgsl',
    category: 'generative',
    params: [
      { id: 'a', name: 'A', default: 0.4, min: 0, max: 1, mapping: 'zoom_params.x', audio: 'bass' },
      { id: 'b', name: 'B', default: 0.5, min: 0, max: 1, mapping: 'zoom_params.y', audio: 'mid' },
      { id: 'c', name: 'C', default: 0.6, min: 0, max: 1, mapping: 'zoom_params.z', audio: { fft: 10 } },
      { id: 'd', name: 'D', default: 0.3, min: 0, max: 1, mapping: 'zoom_params.w', audio: 'overall' },
    ],
  };

  it('maps zoom_params to slot keys', () => {
    expect(mappingToSlotParamKey('zoom_params.z', 0)).toBe('zoomParam3');
  });

  it('resolves audio targets from metadata', () => {
    const targets = resolveAudioTargets(shader);
    expect(targets).toHaveLength(4);
    expect(targets[0].slotParamKey).toBe('zoomParam1');
    expect(targets[0].audioSource).toBe('bass');
    expect(targets[2].audioSource).toEqual({ fft: 10 });
  });

  it('samples fft bins', () => {
    const bins = new Float32Array(128);
    bins[10] = 0.9;
    const v = sampleAudioSource(
      { fft: 10 },
      { bass: 0, mid: 0, treble: 0, overall: 0 },
      bins,
    );
    expect(v).toBeCloseTo(0.9);
  });

  it('falls back to positional bands when no params', () => {
    const targets = resolveAudioTargets({
      id: 'x',
      name: 'X',
      url: 'x',
      category: 'generative',
    });
    expect(targets).toHaveLength(4);
    expect(targets[1].audioSource).toBe('mid');
  });
});
