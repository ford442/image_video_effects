/**
 * #1314 D — C++ measurement exports read through the bridge: per-pass GPU
 * timings and the uncaptured-error ring. Mocked Module; every reader must
 * survive an artifact built before the exports existed and malformed JSON.
 */

import {
  clearErrorRing,
  parseErrorRingJson,
  parsePassTimingsJson,
  readErrorRing,
  readPassTimings,
} from './bridge/diagnostics';
import { EmscriptenModule, wasmRef } from './bridge/state';

/** Fake heap: each C string lives at a pointer; UTF8ToString looks it up. */
function mockModule(strings: Partial<Record<'pass' | 'ring' | 'last', string>>, withExports = true) {
  const heap = new Map<number, string>();
  let next = 64;
  const put = (s: string) => {
    const ptr = next;
    next += 64;
    heap.set(ptr, s);
    return ptr;
  };
  const base: EmscriptenModule = {
    ccall: jest.fn(),
    _malloc: jest.fn(() => 16),
    _free: jest.fn(),
    getValue: jest.fn(() => 0),
    stringToUTF8: jest.fn(),
    HEAPU8: new Uint8Array(1),
    HEAPF32: new Float32Array(1),
    UTF8ToString: jest.fn((ptr: number) => heap.get(ptr) ?? ''),
  };
  if (!withExports) return base;
  return {
    ...base,
    _getPassTimingsJson: jest.fn(() => put(strings.pass ?? '[]')),
    _getErrorRingJson: jest.fn(() => put(strings.ring ?? '{"count":0,"messages":[]}')),
    _getLastError: jest.fn(() => put(strings.last ?? '')),
    _clearErrorRing: jest.fn(),
  };
}

describe('parsePassTimingsJson', () => {
  it('maps C++ entries onto the shared PassTiming shape', () => {
    const passes = parsePassTimingsJson(
      '[{"slot":0,"shaderId":"plasma","label":"plasma","gpuMs":1.2500,"iterations":1},' +
        '{"slot":2,"shaderId":"blur","label":"blur-h","gpuMs":0.5,"iterations":3}]',
    );
    expect(passes).toEqual([
      {
        key: '0:plasma',
        label: 'plasma',
        kind: 'compute',
        slot: 0,
        shaderId: 'plasma',
        entry: 'plasma',
        scale: 1,
        gpuMs: 1.25,
        iterations: 1,
      },
      {
        key: '2:blur-h',
        label: 'blur-h',
        kind: 'compute',
        slot: 2,
        shaderId: 'blur',
        entry: 'blur-h',
        scale: 1,
        gpuMs: 0.5,
        iterations: 3,
      },
    ]);
  });

  it("keys the legacy single-shader pass (slot -1) as '-'", () => {
    const [p] = parsePassTimingsJson('[{"slot":-1,"shaderId":"x","label":"x","gpuMs":0,"iterations":1}]');
    expect(p).toBeDefined();
    expect(p!.slot).toBeUndefined();
    expect(p!.key).toBe('-:x');
  });

  it('drops malformed entries and tolerates garbage', () => {
    expect(parsePassTimingsJson(null)).toEqual([]);
    expect(parsePassTimingsJson('')).toEqual([]);
    expect(parsePassTimingsJson('not json')).toEqual([]);
    expect(parsePassTimingsJson('{"slot":0}')).toEqual([]);
    const passes = parsePassTimingsJson(
      '[null, 3, {"label":"","gpuMs":1}, {"label":"neg","gpuMs":-1}, {"label":"nan","gpuMs":"x"},' +
        ' {"label":"ok","gpuMs":2,"iterations":0}]',
    );
    expect(passes.map((p) => [p.key, p.iterations])).toEqual([['-:ok', 1]]);
  });
});

describe('parseErrorRingJson', () => {
  it('returns count, last and oldest-first recent', () => {
    expect(parseErrorRingJson('{"count":7,"messages":["Validation: a","OutOfMemory: b"]}', 'OutOfMemory: b')).toEqual({
      count: 7,
      last: 'OutOfMemory: b',
      recent: ['Validation: a', 'OutOfMemory: b'],
    });
  });

  it('falls back to the newest recent message and never reports count < recent', () => {
    expect(parseErrorRingJson('{"count":"x","messages":["a",2,"b"]}')).toEqual({
      count: 2,
      last: 'b',
      recent: ['a', 'b'],
    });
    expect(parseErrorRingJson('garbage')).toEqual({ count: 0, last: '', recent: [] });
  });
});

describe('bridge measurement readers', () => {
  const prev = wasmRef.module;
  afterEach(() => {
    wasmRef.module = prev;
  });

  it('read nothing without a module', () => {
    wasmRef.module = null;
    expect(readPassTimings()).toEqual([]);
    expect(readErrorRing()).toEqual({ count: 0, last: '', recent: [] });
    expect(clearErrorRing()).toBe(false);
  });

  it('guard artifacts that predate the exports', () => {
    const mod = mockModule({}, false);
    wasmRef.module = mod;
    expect(readPassTimings()).toEqual([]);
    expect(readErrorRing()).toEqual({ count: 0, last: '', recent: [] });
    expect(clearErrorRing()).toBe(false);
    expect(mod.UTF8ToString).not.toHaveBeenCalled();
  });

  it('decode the C strings the exports return', () => {
    const mod = mockModule({
      pass: '[{"slot":1,"shaderId":"plasma","label":"plasma","gpuMs":0.1000,"iterations":1}]',
      ring: '{"count":3,"messages":["Validation: x","DeviceLost(Unknown): gone"]}',
      last: 'DeviceLost(Unknown): gone',
    });
    wasmRef.module = mod;
    expect(readPassTimings()).toEqual([
      expect.objectContaining({ key: '1:plasma', slot: 1, shaderId: 'plasma', gpuMs: 0.1, kind: 'compute' }),
    ]);
    expect(readErrorRing()).toEqual({
      count: 3,
      last: 'DeviceLost(Unknown): gone',
      recent: ['Validation: x', 'DeviceLost(Unknown): gone'],
    });
    expect(clearErrorRing()).toBe(true);
    expect(mod._clearErrorRing).toHaveBeenCalledTimes(1);
  });

  it('swallow a throwing export (e.g. module aborted)', () => {
    const mod = mockModule({});
    mod._getPassTimingsJson = jest.fn(() => {
      throw new Error('abort');
    });
    mod._clearErrorRing = jest.fn(() => {
      throw new Error('abort');
    });
    wasmRef.module = mod;
    expect(readPassTimings()).toEqual([]);
    expect(clearErrorRing()).toBe(false);
  });
});
