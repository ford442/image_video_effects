import {
  buildVjSetExport,
  parseVjSetExport,
  serializeVjSetExport,
  VJ_SET_EXPORT_VERSION,
} from './vjSetExport';
import { SHARED_CHAIN_VERSION, encodeChain, decodeChain, buildSharedChain, expandSharedChain, DEFAULT_SLOT_PARAMS } from './layerChainShare';
import { SlotParams } from '../renderer/types';

describe('vjSetExport', () => {
  const sampleChain = {
    v: SHARED_CHAIN_VERSION,
    slots: [{ shaderId: 'liquid-metal', params: { zoomParam1: 0.3 } }],
  };

  it('round-trips export JSON', () => {
    const payload = buildVjSetExport('Test Set', sampleChain, { vibePrompt: 'neon' });
    const parsed = parseVjSetExport(serializeVjSetExport(payload));
    expect(parsed?.name).toBe('Test Set');
    expect(parsed?.vibePrompt).toBe('neon');
    expect(parsed?.chain).toEqual(sampleChain);
    expect(decodeChain(parsed!.chainString)).toEqual(sampleChain);
  });

  it('rejects invalid JSON', () => {
    expect(parseVjSetExport('')).toBeNull();
    expect(parseVjSetExport('not json')).toBeNull();
    expect(parseVjSetExport(JSON.stringify({ name: 'x' }))).toBeNull();
  });

  it('accepts chainString-only payloads', () => {
    const chainString = encodeChain(sampleChain);
    const parsed = parseVjSetExport(JSON.stringify({
      exportVersion: VJ_SET_EXPORT_VERSION,
      name: 'From URL',
      chainString,
      savedAt: Date.now(),
    }));
    expect(parsed?.chain.slots[0].shaderId).toBe('liquid-metal');
  });
});

describe('layerChainShare — 6-slot full param stress', () => {
  const ALL_PARAM_KEYS: Array<keyof SlotParams> = [
    'zoomParam1', 'zoomParam2', 'zoomParam3', 'zoomParam4',
    'lightStrength', 'ambient', 'normalStrength', 'fogFalloff', 'depthThreshold',
  ];

  function fullNonDefaultParams(seed: number): SlotParams {
    const p = { ...DEFAULT_SLOT_PARAMS };
    ALL_PARAM_KEYS.forEach((key, i) => {
      p[key] = DEFAULT_SLOT_PARAMS[key] + (seed + i + 1) * 0.037;
    });
    return p;
  }

  it('round-trips 6 slots with all params non-default — 100% state preserved', () => {
    const shaderIds = ['sim-fluid-feedback-coupled', 'gen-lichen-reaction-diffusion', 'cyber-ripples', 'plasma', 'liquid', 'cosmic-flow'];
    const modes = shaderIds;
    const slotParams = shaderIds.map((_, i) => fullNonDefaultParams(i));

    const chain = buildSharedChain(modes, slotParams, {
      enabled: [true, true, false, true, true, true],
      slotModes: ['chained', 'parallel', 'chained', 'chained', 'parallel', 'chained'],
    });

    expect(chain.slots.length).toBe(6);

    const encoded = encodeChain(chain);
    const decoded = decodeChain(encoded);
    expect(decoded).not.toBeNull();

    const expanded = expandSharedChain(decoded!);
    expect(expanded.modes).toEqual(shaderIds);
    expect(expanded.enabled).toEqual([true, true, false, true, true, true]);
    expect(expanded.slotModes).toEqual(['chained', 'parallel', 'chained', 'chained', 'parallel', 'chained']);

    for (let i = 0; i < 6; i++) {
      for (const key of ALL_PARAM_KEYS) {
        expect(expanded.slotParams[i][key]).toBeCloseTo(slotParams[i][key], 5);
      }
    }

    expect(decodeChain(encoded)).toEqual(decoded);
  });

  it('keeps encoded chain URL-safe under 6×full params', () => {
    const modes = Array.from({ length: 6 }, (_, i) => `shader-stress-${i}`);
    const slotParams = modes.map((_, i) => fullNonDefaultParams(i));
    const encoded = encodeChain(buildSharedChain(modes, slotParams));
    expect(encoded).not.toMatch(/[+/=]/);
    expect(encoded.length).toBeLessThan(8000);
  });
});
