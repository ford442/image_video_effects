import {
  BLEND_MODES,
  applyLayerChoice,
  compactSlotLayer,
  compactSlotLayerErrors,
  decodeMaskRef,
  defaultSlotLayer,
  encodeMaskRef,
  expandCompactSlotLayer,
  isPassThroughLayer,
  layerChoice,
  layerKeyThreshold,
  normalizeSlotLayer,
  slotLayersEqual,
  type SlotLayer,
} from './layerState';

const blend = (overrides: Partial<SlotLayer> = {}): SlotLayer => ({
  ...defaultSlotLayer(),
  output: 'blend',
  ...overrides,
});

describe('normalizeSlotLayer', () => {
  it('defaults to replace and clamps untrusted input', () => {
    expect(normalizeSlotLayer(undefined)).toEqual(defaultSlotLayer());
    expect(normalizeSlotLayer({ output: 'nope', blend: 'wat', opacity: 7 })).toEqual(defaultSlotLayer());
    expect(normalizeSlotLayer({ output: 'blend', blend: 'screen', opacity: -1, key: 4 })).toEqual({
      output: 'blend',
      blend: 'screen',
      opacity: 0,
      mask: { source: 'none' },
      key: 1,
    });
  });

  it('drops a slot mask that names no valid slot', () => {
    expect(normalizeSlotLayer({ output: 'blend', mask: { source: 'slot', slot: 9 } }).mask).toEqual({ source: 'none' });
    expect(normalizeSlotLayer({ output: 'blend', mask: { source: 'slot', slot: 2, invert: true, feather: 2 } }).mask)
      .toEqual({ source: 'slot', slot: 2, invert: true, feather: 1 });
  });
});

describe('isPassThroughLayer', () => {
  it('treats replace and a plain full-opacity normal blend as the replace path', () => {
    expect(isPassThroughLayer(undefined)).toBe(true);
    expect(isPassThroughLayer(defaultSlotLayer())).toBe(true);
    expect(isPassThroughLayer(blend({ blend: 'normal' }))).toBe(true);
    expect(isPassThroughLayer(blend({ blend: 'normal', opacity: 0.5 }))).toBe(false);
    expect(isPassThroughLayer(blend({ blend: 'screen' }))).toBe(false);
    expect(isPassThroughLayer(blend({ mask: { source: 'luma' } }))).toBe(false);
    expect(isPassThroughLayer({ ...defaultSlotLayer(), output: 'mask' })).toBe(false);
  });
});

describe('mask refs', () => {
  it('round-trips every source with invert and feather', () => {
    for (const mask of [
      { source: 'luma' as const },
      { source: 'depth' as const, invert: true },
      { source: 'slot' as const, slot: 5, feather: 0.25 },
      { source: 'slot' as const, slot: 0, invert: true, feather: 1 },
    ]) {
      const ref = encodeMaskRef(mask)!;
      expect(decodeMaskRef(ref)).toEqual(mask);
    }
    expect(encodeMaskRef({ source: 'depth', invert: true, feather: 0.25 })).toBe('!d~0.25');
    expect(encodeMaskRef({ source: 'none' })).toBeUndefined();
  });

  it('rejects malformed refs', () => {
    for (const bad of ['', 'x', 's6', 's', '!!l', 'l~', 'd~abc']) expect(decodeMaskRef(bad)).toBeNull();
  });
});

describe('compact wire form (b / o / m / k)', () => {
  it('is empty for replace and round-trips blend layers', () => {
    expect(compactSlotLayer(defaultSlotLayer())).toEqual({});
    const layer = blend({ blend: 'screen', opacity: 0.5, mask: { source: 'slot', slot: 1, invert: true }, key: 0.3 });
    const compact = compactSlotLayer(layer);
    expect(compact).toEqual({ b: 'screen', o: 0.5, m: '!s1', k: 0.3 });
    expect(slotLayersEqual(expandCompactSlotLayer(compact), layer)).toBe(true);
  });

  it('keeps only b for a matte', () => {
    const matte: SlotLayer = { ...defaultSlotLayer(), output: 'mask', opacity: 0.2, mask: { source: 'luma' } };
    expect(compactSlotLayer(matte)).toEqual({ b: 'mask' });
    expect(expandCompactSlotLayer({ b: 'mask', o: 0.2 })).toEqual({ ...defaultSlotLayer(), output: 'mask' });
  });

  it('degrades unknown values to defaults instead of failing', () => {
    expect(expandCompactSlotLayer({ b: 'future-mode', o: 0.5 })).toEqual(defaultSlotLayer());
    expect(expandCompactSlotLayer({ b: 'add', m: '???' }).mask).toEqual({ source: 'none' });
  });

  it('validates strictly for project files', () => {
    expect(compactSlotLayerErrors({ b: 'add', o: 0.5, m: 'l', k: 0.2 }, 'slot')).toEqual([]);
    expect(compactSlotLayerErrors({ b: 'blur', o: 2, m: 's9', k: -1 }, 'slot')).toHaveLength(4);
  });

  it('round-trips every blend mode', () => {
    for (const mode of BLEND_MODES) {
      expect(expandCompactSlotLayer(compactSlotLayer(blend({ blend: mode, opacity: 0.75 })))).toEqual(
        blend({ blend: mode, opacity: 0.75 }),
      );
    }
  });
});

describe('layer strip helpers', () => {
  it('maps the single dropdown to output + blend', () => {
    const base = defaultSlotLayer();
    expect(layerChoice(base)).toBe('replace');
    const screen = applyLayerChoice(base, 'screen');
    expect(screen).toMatchObject({ output: 'blend', blend: 'screen' });
    expect(layerChoice(screen)).toBe('screen');
    expect(applyLayerChoice(screen, 'mask').output).toBe('mask');
  });

  it('uses per-mode key defaults', () => {
    expect(layerKeyThreshold(blend({ blend: 'luma-key' }))).toBe(0.08);
    expect(layerKeyThreshold(blend({ blend: 'depth-key' }))).toBe(0.5);
    expect(layerKeyThreshold(blend({ blend: 'depth-key', key: 0.7 }))).toBe(0.7);
  });
});
