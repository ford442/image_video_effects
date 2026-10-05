import {
  buildVjSetExport,
  parseVjSetExport,
  sanitizeTimeline,
  serializeVjSetExport,
  VJ_SET_EXPORT_VERSION,
  VjTimeline,
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

  describe('timeline', () => {
    const sampleChain = { v: SHARED_CHAIN_VERSION, slots: [{ shaderId: 'liquid-metal' }] };
    const timeline: VjTimeline = {
      hz: 20,
      durationMs: 1500,
      events: [
        { t: 0, slot: 0, kind: 'shader', value: 'liquid-metal' },
        { t: 0, slot: 0, kind: 'param', key: 'zoomParam1', value: 0.3 },
        { t: 500, slot: 1, kind: 'param', key: 'zoomParam4', value: 0.9 },
      ],
    };

    it('round-trips through the v1 file without bumping exportVersion', () => {
      const payload = buildVjSetExport('Rec', sampleChain, { timeline });
      expect(payload.exportVersion).toBe(1);
      const parsed = parseVjSetExport(serializeVjSetExport(payload));
      expect(parsed?.timeline).toEqual(timeline);
    });

    it('legacy files without a timeline still parse', () => {
      const parsed = parseVjSetExport(serializeVjSetExport(buildVjSetExport('Old', sampleChain)));
      expect(parsed).not.toBeNull();
      expect(parsed && 'timeline' in parsed).toBe(false);
    });

    it('drops malformed events and non-monotonic times', () => {
      const t = sanitizeTimeline({
        hz: 999,
        events: [
          { t: 100, slot: 0, kind: 'param', key: 'zoomParam1', value: 0.5 },
          { t: 50, slot: 0, kind: 'param', key: 'zoomParam1', value: 0.6 }, // goes back in time
          { t: 120, slot: 9, kind: 'param', key: 'zoomParam1', value: 0.6 }, // slot out of range
          { t: 130, slot: 0, kind: 'param', key: 'lightStrength', value: 0.6 }, // not a slider
          { t: 140, slot: 0, kind: 'param', key: 'zoomParam2', value: 'x' },
          { t: 150, slot: 0, kind: 'shader', value: '' },
          { t: 160, slot: 2, kind: 'shader', value: 'neon-grid' },
          null,
        ],
      });
      expect(t?.hz).toBe(20);
      expect(t?.events).toEqual([
        { t: 100, slot: 0, kind: 'param', key: 'zoomParam1', value: 0.5 },
        { t: 160, slot: 2, kind: 'shader', value: 'neon-grid' },
      ]);
      expect(t?.durationMs).toBe(160);
    });

    it('returns null for unusable timelines', () => {
      expect(sanitizeTimeline(undefined)).toBeNull();
      expect(sanitizeTimeline({ events: 'nope' })).toBeNull();
      expect(sanitizeTimeline({ events: [{ t: 0, slot: 0, kind: 'bogus' }] })).toBeNull();
    });
  });
});
