import {
  BLEND_MODES,
  DEFAULT_SLOT_OUTPUT,
  decodeSlotOutputCompact,
  encodeSlotOutputCompact,
  isDefaultSlotOutput,
  maskSourceSlot,
  normalizeSlotOutput,
  patchSlotOutput,
  slotOutputsEqual,
  type SlotOutput,
} from './slotOutput';

describe('slotOutput', () => {
  it('fills defaults, clamps numbers and drops unknown enums', () => {
    expect(normalizeSlotOutput(undefined)).toEqual(DEFAULT_SLOT_OUTPUT);
    expect(normalizeSlotOutput({
      mode: 'blend', blend: 'bogus' as never, opacity: 2, feather: -1, keyThreshold: Number.NaN, mask: 'slot9',
    })).toEqual({ ...DEFAULT_SLOT_OUTPUT, mode: 'blend', opacity: 1, feather: 0, mask: 'slot9' });
    expect(normalizeSlotOutput({ mask: 'elsewhere' as never }).mask).toBe('none');
  });

  it('keeps the blend-mode order the WGSL switch depends on', () => {
    expect(BLEND_MODES.indexOf('normal')).toBe(0);
    expect(BLEND_MODES.indexOf('screen')).toBe(2);
    expect(BLEND_MODES.indexOf('depth-key')).toBe(8);
  });

  it('patches onto an existing output', () => {
    const blended = patchSlotOutput(undefined, { mode: 'blend', blend: 'screen' });
    expect(patchSlotOutput(blended, { opacity: 0.5 })).toMatchObject({ mode: 'blend', blend: 'screen', opacity: 0.5 });
    expect(isDefaultSlotOutput(blended)).toBe(false);
    expect(isDefaultSlotOutput({ ...DEFAULT_SLOT_OUTPUT })).toBe(true);
    expect(slotOutputsEqual(blended, { ...blended })).toBe(true);
  });

  it('parses slot mask sources', () => {
    expect(maskSourceSlot('slot3')).toBe(3);
    expect(maskSourceSlot('depth')).toBeNull();
  });

  describe('chain-URL compact params', () => {
    it('writes nothing for a replace slot', () => {
      expect(encodeSlotOutputCompact(DEFAULT_SLOT_OUTPUT)).toEqual({});
      expect(decodeSlotOutputCompact({})).toBeUndefined();
    });

    it('round-trips blend, opacity, mask, feather and key', () => {
      const cases: SlotOutput[] = [
        { ...DEFAULT_SLOT_OUTPUT, mode: 'blend', blend: 'screen', opacity: 0.5 },
        { ...DEFAULT_SLOT_OUTPUT, mode: 'blend', blend: 'luma-key', keyThreshold: 0.25, mask: 'depth', maskInvert: true },
        { ...DEFAULT_SLOT_OUTPUT, mode: 'blend', blend: 'multiply', mask: 'slot2', feather: 0.4 },
        { ...DEFAULT_SLOT_OUTPUT, mode: 'mask' },
      ];
      for (const output of cases) {
        expect(decodeSlotOutputCompact(encodeSlotOutputCompact(output), 6)).toEqual(output);
      }
      expect(encodeSlotOutputCompact(cases[0])).toEqual({ b: 'screen', o: '0.5' });
      expect(encodeSlotOutputCompact(cases[1])).toEqual({ b: 'luma-key', m: '~depth', k: '0.25' });
    });

    it('ignores malformed values', () => {
      expect(decodeSlotOutputCompact({ b: 'nope', o: 'x', m: 'slot99' }, 6)).toEqual(DEFAULT_SLOT_OUTPUT);
    });
  });
});
