import { applyCalibrationKey } from './calibrationKeys';
import { CALIBRATIONS_KEY, CalibrationStore, LAYOUT_KEY } from './calibrationStore';
import {
  CORNER_MAX,
  defaultOutputConfig,
  nudgeCorner,
  OUTPUT_UNIFORM_BYTES,
  OUTPUT_UNIFORM_FLOATS,
  packOutputUniform,
  sanitizeOutputConfig,
  setCorner,
  TEST_PATTERN_IDS,
} from './outputConfig';

describe('sanitizeOutputConfig', () => {
  it('defaults anything unusable', () => {
    expect(sanitizeOutputConfig(null)).toEqual(defaultOutputConfig());
    expect(sanitizeOutputConfig({ corners: 'nope', testPattern: 'plaid', colour: { gain: NaN } })).toEqual(defaultOutputConfig());
  });

  it('keeps valid values and clamps the rest', () => {
    const c = sanitizeOutputConfig({
      corners: [[0.1, 0.2], [99, 0], [1, 1], ['x', 1]],
      testPattern: 'grid',
      outline: true,
      colour: { gain: 9, gamma: 0.5, blackLevel: -1 },
    });
    expect(c.corners).toEqual([[0.1, 0.2], [CORNER_MAX, 0], [1, 1], [0, 1]]);
    expect(c.testPattern).toBe('grid');
    expect(c.outline).toBe(true);
    expect(c.colour).toEqual({ gain: 4, gamma: 0.5, blackLevel: 0 });
  });

  it('never shares the default corner arrays between configs', () => {
    const a = defaultOutputConfig();
    const b = defaultOutputConfig();
    expect(a.corners).not.toBe(b.corners);
    expect(a.corners[0]).not.toBe(b.corners[0]);
  });
});

describe('corner edits', () => {
  it('nudges one corner and leaves the others', () => {
    const c = nudgeCorner(defaultOutputConfig(), 2, -0.1, 0.05);
    expect(c.corners[2]?.[0]).toBeCloseTo(0.9);
    expect(c.corners[2]?.[1]).toBeCloseTo(1.05);
    expect(c.corners[0]).toEqual([0, 0]);
  });

  it('setCorner places a corner absolutely', () => {
    expect(setCorner(defaultOutputConfig(), 1, 0.8, 0.1).corners[1]).toEqual([0.8, 0.1]);
    expect(setCorner(defaultOutputConfig(), 9, 0.8, 0.1)).toEqual(defaultOutputConfig());
  });
});

describe('packOutputUniform', () => {
  it('matches the OutputParams layout (5 × vec4)', () => {
    expect(OUTPUT_UNIFORM_FLOATS * 4).toBe(OUTPUT_UNIFORM_BYTES);
    expect(OUTPUT_UNIFORM_BYTES).toBe(80);
  });

  it('packs an identity pin, colour, flip and pattern', () => {
    const u = packOutputUniform(
      { ...defaultOutputConfig(), testPattern: 'crosshatch', outline: true, colour: { gain: 1.5, gamma: 1.1, blackLevel: 0.02 } },
      { generative: true, width: 1920, height: 1080 },
    );
    expect([...u.slice(0, 12)].map((v) => Math.round(v * 1e6) / 1e6)).toEqual([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0]);
    expect(u[12]).toBeCloseTo(1.5);
    expect(u[13]).toBeCloseTo(1.1);
    expect(u[14]).toBeCloseTo(0.02);
    expect(u[15]).toBe(1);
    expect([...u.slice(16)]).toEqual([TEST_PATTERN_IDS.crosshatch, 1, 1920, 1080]);
  });

  it('packs the inverse pin: an output corner maps to its program corner', () => {
    const cfg = { ...defaultOutputConfig(), corners: [[0.2, 0.1], [0.9, 0.2], [0.8, 0.9], [0.1, 0.8]] as const };
    const u = packOutputUniform(cfg as never, { generative: false, width: 100, height: 100 });
    const apply = (x: number, y: number) => {
      const qx = (u[0] ?? 0) * x + (u[1] ?? 0) * y + (u[2] ?? 0);
      const qy = (u[4] ?? 0) * x + (u[5] ?? 0) * y + (u[6] ?? 0);
      const qw = (u[8] ?? 0) * x + (u[9] ?? 0) * y + (u[10] ?? 0);
      return [qx / qw, qy / qw];
    };
    const [x, y] = apply(0.8, 0.9);
    expect(x).toBeCloseTo(1, 5);
    expect(y).toBeCloseTo(1, 5);
    expect(u[15]).toBe(0);
  });

  it('falls back to the identity for a degenerate quad', () => {
    const cfg = sanitizeOutputConfig({ corners: [[0.5, 0.5], [0.5, 0.5], [0.5, 0.5], [0.5, 0.5]] });
    const u = packOutputUniform(cfg, { generative: false, width: 1, height: 1 });
    expect([u[0], u[5], u[10]]).toEqual([1, 1, 1]);
  });
});

describe('applyCalibrationKey', () => {
  const size = { width: 1000, height: 500 };
  const base = { config: defaultOutputConfig(), selected: 0 };

  it('selects corners with Tab / Shift+Tab / 1–4', () => {
    expect(applyCalibrationKey(base, 'Tab', {}, size)?.selected).toBe(1);
    expect(applyCalibrationKey(base, 'Tab', { shift: true }, size)?.selected).toBe(3);
    expect(applyCalibrationKey(base, '3', {}, size)?.selected).toBe(2);
  });

  it('nudges the selected corner by output pixels', () => {
    const one = applyCalibrationKey({ ...base, selected: 1 }, 'ArrowLeft', {}, size);
    expect(one?.config.corners[1]?.[0]).toBeCloseTo(1 - 1 / 1000);
    const ten = applyCalibrationKey(base, 'ArrowDown', { shift: true }, size);
    expect(ten?.config.corners[0]?.[1]).toBeCloseTo(10 / 500);
  });

  it('cycles test patterns and toggles the outline', () => {
    const t = applyCalibrationKey(base, 't', {}, size);
    expect(t?.config.testPattern).toBe('grid');
    expect(applyCalibrationKey(base, 'o', {}, size)?.config.outline).toBe(true);
  });

  it('ignores other keys', () => {
    expect(applyCalibrationKey(base, 'q', {}, size)).toBeNull();
  });
});

describe('CalibrationStore', () => {
  const memory = () => {
    const data = new Map<string, string>();
    return {
      data,
      getItem: (k: string) => data.get(k) ?? null,
      setItem: (k: string, v: string) => { data.set(k, v); },
    };
  };

  it('remembers each output layout', () => {
    const storage = memory();
    const store = new CalibrationStore(storage);
    const cfg = nudgeCorner(defaultOutputConfig(), 0, 0.1, 0.1);
    store.saveLayout('stage-1', cfg);
    expect(new CalibrationStore(storage).loadLayout('stage-1')).toEqual(cfg);
    expect(store.loadLayout('stage-2')).toBeNull();
    expect(storage.data.has(LAYOUT_KEY)).toBe(true);
  });

  it('saves, lists, loads and deletes named calibrations', () => {
    const storage = memory();
    const store = new CalibrationStore(storage);
    expect(store.saveNamed('  Club wall ', { ...defaultOutputConfig(), testPattern: 'bars' })).toBe(true);
    expect(store.saveNamed('', defaultOutputConfig())).toBe(false);
    store.saveNamed('Alpha', defaultOutputConfig());
    expect(store.listNamed()).toEqual(['Alpha', 'Club wall']);
    expect(store.loadNamed('Club wall')?.testPattern).toBe('bars');
    store.deleteNamed('Alpha');
    expect(store.listNamed()).toEqual(['Club wall']);
    expect(storage.data.has(CALIBRATIONS_KEY)).toBe(true);
  });

  it('survives broken or throwing storage', () => {
    const storage = memory();
    storage.data.set(LAYOUT_KEY, '{not json');
    expect(new CalibrationStore(storage).loadLayout('stage-1')).toBeNull();
    const throwing = {
      getItem: () => { throw new Error('blocked'); },
      setItem: () => { throw new Error('blocked'); },
    };
    const store = new CalibrationStore(throwing);
    expect(store.loadLayout('x')).toBeNull();
    expect(store.saveNamed('x', defaultOutputConfig())).toBe(false);
    expect(() => store.saveLayout('x', defaultOutputConfig())).not.toThrow();
    expect(new CalibrationStore(null).listNamed()).toEqual([]);
  });
});
