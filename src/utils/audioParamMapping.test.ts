import {
  computeAudioSlotUpdates,
  resolveAudioTargets,
  sampleAudioSource,
  mappingToSlotParamKey,
} from './audioParamMapping';
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
    expect(targets[0]!.slotParamKey).toBe('zoomParam1');
    expect(targets[0]!.audioSource).toBe('bass');
    expect(targets[2]!.audioSource).toEqual({ fft: 10 });
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
    expect(targets[1]!.audioSource).toBe('mid');
  });

  describe('non-generative categories', () => {
    const sim: ShaderEntry = {
      id: 'sim',
      name: 'Sim',
      url: 'x',
      category: 'simulation',
      params: [
        { id: 'a', name: 'A', default: 0.2, min: 0, max: 1, mapping: 'zoom_params.x' },
        { id: 'b', name: 'B', default: 0.5, min: 0, max: 1, mapping: 'zoom_params.y', audio: 'treble' },
      ],
    };

    it('maps only params with explicit audio metadata', () => {
      const targets = resolveAudioTargets(sim);
      expect(targets).toHaveLength(1);
      expect(targets[0]!.slotParamKey).toBe('zoomParam2');
      expect(targets[0]!.audioSource).toBe('treble');
    });

    it('returns no targets (no synthetic fallback) without metadata', () => {
      expect(resolveAudioTargets({ id: 'm', name: 'M', url: 'x', category: 'interactive-mouse' })).toEqual([]);
      expect(resolveAudioTargets(undefined)).toEqual([]);
    });
  });

  describe('computeAudioSlotUpdates', () => {
    const bands = { bass: 1, mid: 0.5, treble: 0, overall: 0.5 };
    const targets = resolveAudioTargets(shader).slice(0, 2);

    it('produces one update per active slot', () => {
      const out = computeAudioSlotUpdates({
        slots: [
          { slot: 0, targets, defaults: [0.4, 0.5] },
          { slot: 2, targets, defaults: [0.4, 0.5] },
        ],
        bands,
        fftBins: null,
        amount: 1,
        smoothed: {},
        isHeld: () => false,
        baseFor: () => undefined,
        smoothing: 1,
      });
      expect(out.map(o => o.slot)).toEqual([0, 2]);
      expect(out[1]!.updates.zoomParam1).toBeCloseTo(0.9); // 0.4 + (1 - 0.5)
      expect(out[1]!.updates.zoomParam2).toBeCloseTo(0.5);
    });

    it('skips held params and modulates around the performer base', () => {
      const smoothed: Record<string, number> = {};
      const out = computeAudioSlotUpdates({
        slots: [{ slot: 1, targets, defaults: [0.4, 0.5] }],
        bands,
        fftBins: null,
        amount: 0.5,
        smoothed,
        isHeld: (slot, key) => slot === 1 && key === 'zoomParam2',
        baseFor: (slot, key) => (key === 'zoomParam1' ? 0.1 : undefined),
        smoothing: 1,
      });
      expect(Object.keys(out[0]!.updates)).toEqual(['zoomParam1']);
      expect(out[0]!.updates.zoomParam1).toBeCloseTo(0.35); // 0.1 + (1 - 0.5) * 0.5
      expect(smoothed['1:zoomParam2']).toBeUndefined();
    });

    it('omits slots whose params are all held', () => {
      const out = computeAudioSlotUpdates({
        slots: [{ slot: 0, targets, defaults: [] }],
        bands,
        fftBins: null,
        amount: 1,
        smoothed: {},
        isHeld: () => true,
        baseFor: () => undefined,
      });
      expect(out).toEqual([]);
    });
  });
});
