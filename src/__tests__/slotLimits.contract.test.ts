/**
 * @jest-environment jsdom
 *
 * slot_limits.json: TS PHYSICAL_SLOT_LIMIT and C++ MAX_SHADER_SLOTS share one
 * ceiling (verify:device-policy checks the C++ side). Out-of-range or dropped
 * slots must be logged and visible, never a silent no-op.
 */
import slotLimitsContract from '../contracts/slot_limits.json';
import { PHYSICAL_SLOT_LIMIT, checkPhysicalSlotIndex } from '../renderer/slotOrchestrator';
import * as WasmBridge from '../wasm/wasm_bridge';
import { state, wasmRef, EmscriptenModule } from '../wasm/bridge/state';
import { WASMRenderer } from '../renderer/WASMRenderer';
import { WebGPURenderer } from '../renderer/WebGPURenderer';

/** Fake module that behaves like a C++ build with `slotCount` slots. */
function makeSlotModule(slotCount: number, knownShaders: string[]) {
  const slots: string[] = Array.from({ length: slotCount }, () => '');
  const ccall = jest.fn((name: string, _ret: unknown, _types: unknown, args: unknown[]) => {
    const [i, id] = args as [number, string];
    if (name === 'setSlotShader') {
      if (i < 0 || i >= slotCount) return undefined;
      slots[i] = knownShaders.includes(id) ? id : '';
      return undefined;
    }
    if (name === 'getSlotShaderId') return i >= 0 && i < slotCount ? slots[i] : '';
    return 0;
  });
  return { ccall } as unknown as EmscriptenModule & { ccall: jest.Mock };
}

let warn: jest.SpyInstance;

beforeEach(() => {
  warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
  state.droppedSlots.clear();
});

afterEach(() => {
  warn.mockRestore();
  state.initialized = false;
  wasmRef.module = null;
});

describe('slot_limits.json', () => {
  test('PHYSICAL_SLOT_LIMIT is read from the contract (6, matching share URLs)', () => {
    expect(PHYSICAL_SLOT_LIMIT).toBe(slotLimitsContract.maxPhysicalSlots);
    expect(PHYSICAL_SLOT_LIMIT).toBe(6);
  });

  test('quality cap range sits inside the physical limit', () => {
    const [lo, hi] = slotLimitsContract.qualityCapRange;
    expect(lo).toBeGreaterThanOrEqual(1);
    expect(hi).toBeLessThanOrEqual(PHYSICAL_SLOT_LIMIT);
  });

  test('checkPhysicalSlotIndex accepts 0..limit-1 and warns otherwise', () => {
    for (let i = 0; i < PHYSICAL_SLOT_LIMIT; i++) {
      expect(checkPhysicalSlotIndex('Test', i)).toBe(true);
    }
    expect(warn).not.toHaveBeenCalled();
    expect(checkPhysicalSlotIndex('Test', PHYSICAL_SLOT_LIMIT)).toBe(false);
    expect(checkPhysicalSlotIndex('Test', -1)).toBe(false);
    expect(checkPhysicalSlotIndex('Test', 1.5)).toBe(false);
    expect(warn).toHaveBeenCalledTimes(3);
  });
});

describe('WASM bridge setSlotShader readback', () => {
  test('a 3-slot artifact dropping slot 4 is warned and recorded', () => {
    const mod = makeSlotModule(3, ['a', 'b']);
    wasmRef.module = mod;
    state.initialized = true;

    expect(WasmBridge.setSlotShader(1, 'a')).toBe(true);
    expect(WasmBridge.setSlotShader(4, 'b')).toBe(false);
    expect([...WasmBridge.getDroppedSlots()]).toEqual([4]);
    expect(warn).toHaveBeenCalledWith(expect.stringContaining('setSlotShader(4, "b") dropped'));
  });

  test('a 6-slot artifact accepts every physical slot', () => {
    wasmRef.module = makeSlotModule(6, ['a']);
    state.initialized = true;
    for (let i = 0; i < PHYSICAL_SLOT_LIMIT; i++) {
      expect(WasmBridge.setSlotShader(i, 'a')).toBe(true);
    }
    expect(WasmBridge.getDroppedSlots().size).toBe(0);
    expect(warn).not.toHaveBeenCalled();
  });

  test('a shader with no pipeline is reported; clearing a slot is not', () => {
    wasmRef.module = makeSlotModule(6, []);
    state.initialized = true;
    expect(WasmBridge.setSlotShader(2, 'missing')).toBe(false);
    expect(WasmBridge.getDroppedSlots().has(2)).toBe(true);
    expect(WasmBridge.setSlotShader(2, '')).toBe(true);
    expect(WasmBridge.getDroppedSlots().has(2)).toBe(false);
  });
});

describe('renderer setSlotShader out of range', () => {
  test('WASMRenderer logs and does not reach the module', () => {
    const mod = makeSlotModule(6, ['a']);
    wasmRef.module = mod;
    state.initialized = true;
    const r = new WASMRenderer({ width: 64, height: 64, agentCount: 0 });
    expect(r.setSlotShader(PHYSICAL_SLOT_LIMIT, 'a')).toBe(false);
    expect(mod.ccall).not.toHaveBeenCalled();
    expect(warn).toHaveBeenCalledWith(expect.stringContaining('[WASMRenderer] slot 6 ignored'));

    expect(r.setSlotShader(5, 'a')).toBe(true);
    expect(r.getDroppedSlots()).toEqual([]);
  });

  test('WebGPURenderer logs instead of silently ignoring', () => {
    const fake = { slots: [] as unknown[] };
    WebGPURenderer.prototype.setSlotShader.call(fake, PHYSICAL_SLOT_LIMIT, 'a');
    expect(fake.slots).toEqual([]);
    expect(warn).toHaveBeenCalledWith(expect.stringContaining('[WebGPURenderer] slot 6 ignored'));
  });
});
