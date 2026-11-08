/**
 * The shader-analysis contract (bind_group0.json shaderUsageFlags +
 * workgroup_dispatch.json unparsedFallback) generates both the bridge's
 * _contracts.ts and C++'s wasm_contracts.h, and loadShader/reloadShader carry
 * the bridge's analysis to C++ so neither backend parses WGSL on its own.
 */
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import type { Mock } from 'vitest';
import bindGroup0 from '../contracts/bind_group0.json';
import workgroupDispatch from '../contracts/workgroup_dispatch.json';
import wasmExports from '../contracts/wasm_exports.json';
import {
  SHADER_USAGE_ALL,
  SHADER_USAGE_BINDINGS,
  SHADER_USAGE_BITS,
  WORKGROUP_UNPARSED_FALLBACK,
} from './bridge/_contracts';
import {
  analyzeShaderBindings,
  CONSERVATIVE_BINDING_USAGE,
  packUsageBits,
  resolveWorkgroupSize,
  unpackUsageBits,
} from './bridge/wgslAnalysis';
import { loadShader, reloadShader, shaderAnalysisArgs } from './bridge/shader';
import { state, wasmRef, type EmscriptenModule } from './bridge/state';
import * as ShaderCompilation from '../renderer/ShaderCompilation';

const ROOT = path.resolve(__dirname, '..', '..');
const requireCjs = createRequire(import.meta.url);
const gen = requireCjs('../../scripts/gen-wasm-contracts.js') as {
  generate: () => Record<string, string>;
  loadUsageFlags: (bg0: unknown) => Array<{ name: string; bit: number; binding: number }>;
  TS_REL: string;
  HEADER_REL: string;
};

describe('wasm contracts generator', () => {
  it('committed _contracts.ts and wasm_contracts.h match a fresh emit', () => {
    for (const [rel, text] of Object.entries(gen.generate())) {
      expect(fs.readFileSync(path.join(ROOT, rel), 'utf8'), rel).toBe(text);
    }
  });

  it('TS constants and the C++ header carry the same bits from one table', () => {
    const header = fs.readFileSync(path.join(ROOT, gen.HEADER_REL), 'utf8');
    let all = 0;
    for (const [name, spec] of Object.entries(bindGroup0.shaderUsageFlags)) {
      const flag = name as keyof typeof SHADER_USAGE_BITS;
      expect(SHADER_USAGE_BITS[flag]).toBe(spec.bit);
      expect(SHADER_USAGE_BINDINGS[flag]).toBe(spec.binding);
      expect(header).toContain(`kUsage_${name} = ${spec.bit}u;`);
      all |= spec.bit;
    }
    expect(SHADER_USAGE_ALL).toBe(all);
    expect(WORKGROUP_UNPARSED_FALLBACK).toEqual(workgroupDispatch.unparsedFallback);
    expect(header).toContain(`kWorkgroupFallbackX = ${workgroupDispatch.unparsedFallback.x}u;`);
    expect(header).toContain(`kWorkgroupFallbackY = ${workgroupDispatch.unparsedFallback.y}u;`);
  });

  it('every usage flag names a declared binding with the canonical WGSL name', () => {
    const names = new Map(bindGroup0.bindings.map((b) => [b.binding, b.name]));
    expect(names.get(SHADER_USAGE_BINDINGS.writesDataA)).toBe('dataTextureA');
    expect(names.get(SHADER_USAGE_BINDINGS.writesDataB)).toBe('dataTextureB');
    expect(names.get(SHADER_USAGE_BINDINGS.readsDataC)).toBe('dataTextureC');
    expect(names.get(SHADER_USAGE_BINDINGS.usesHistory)).toBe('historyTexture');
    expect(names.get(SHADER_USAGE_BINDINGS.writesDepth)).toBe('writeDepthTexture');
  });

  it.each([
    ['a duplicated bit', { a: { bit: 1, binding: 7 }, b: { bit: 1, binding: 8 } }, /used twice/],
    ['a non-power-of-two bit', { a: { bit: 3, binding: 7 } }, /power of two/],
    ['an undeclared binding', { a: { bit: 1, binding: 99 } }, /not in bindings/],
    ['a duplicated binding', { a: { bit: 1, binding: 7 }, b: { bit: 2, binding: 7 } }, /used twice/],
  ])('refuses %s', (_label, table, message) => {
    expect(() => gen.loadUsageFlags({ ...bindGroup0, shaderUsageFlags: table })).toThrow(message);
  });

  it('loadShader/reloadShader take the analysis as int args after the source', () => {
    for (const fn of ['loadShader', 'reloadShader'] as const) {
      expect(wasmExports.exports[fn].args).toEqual([
        'id:const char*',
        'wgslCode:const char*',
        'workgroupX:int',
        'workgroupY:int',
        'usageBits:int',
      ]);
    }
  });

  it('no C++ source keeps its own WGSL dispatch/usage parser', () => {
    const dir = path.join(ROOT, 'wasm_renderer');
    for (const name of fs.readdirSync(dir).filter((n) => /\.(cpp|h)$/.test(n))) {
      expect(fs.readFileSync(path.join(dir, name), 'utf8'), name).not.toMatch(
        /\b(ParseWorkgroupSize|AnalyzeShaderBindings)\b/,
      );
    }
  });
});

describe('wgslAnalysis', () => {
  const header = `
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var feedbackOut: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(13) var historyTexture: texture_2d_array<f32>;
`;

  it('picks main over an earlier 1D helper kernel', () => {
    const src = `@compute @workgroup_size(64, 1, 1) fn update_boids() {}\n@compute @workgroup_size(8, 4, 1) fn main() {}`;
    expect(resolveWorkgroupSize(src)).toEqual({ x: 8, y: 4, parsed: true });
  });

  it('reports the contract fallback as unparsed', () => {
    expect(resolveWorkgroupSize('fn main() {}')).toEqual({ ...WORKGROUP_UNPARSED_FALLBACK, parsed: false });
  });

  it('detects use beyond the declaration, including aliased names and depth writes', () => {
    const src = `${header}
@compute @workgroup_size(16, 16, 1) fn main() {
  textureStore(writeDepthTexture, vec2<i32>(0), vec4<f32>(0.0));
  textureStore(feedbackOut, vec2<i32>(0), vec4<f32>(0.0));
}`;
    expect(analyzeShaderBindings(src)).toEqual({
      writesDataA: false,
      writesDataB: true,
      readsDataC: false,
      usesHistory: false,
      writesDepth: true,
    });
    expect(packUsageBits(analyzeShaderBindings(src))).toBe(SHADER_USAGE_BITS.writesDataB | SHADER_USAGE_BITS.writesDepth);
  });

  it('pack/unpack round-trips and conservative usage packs to every bit', () => {
    expect(packUsageBits(CONSERVATIVE_BINDING_USAGE)).toBe(SHADER_USAGE_ALL);
    for (let bits = 0; bits <= SHADER_USAGE_ALL; bits++) {
      expect(packUsageBits(unpackUsageBits(bits))).toBe(bits);
    }
  });

  it('is the analysis the TS renderer uses', () => {
    expect(ShaderCompilation.analyzeShaderBindings).toBe(analyzeShaderBindings);
    expect(ShaderCompilation.CONSERVATIVE_BINDING_USAGE).toBe(CONSERVATIVE_BINDING_USAGE);
  });
});

describe('bridge loadShader sends the analysis to C++', () => {
  const prev = { initialized: state.initialized, module: wasmRef.module };
  const src = `
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(13) var historyTexture: texture_2d_array<f32>;
@compute @workgroup_size(64, 1, 1) fn helper() {}
@compute @workgroup_size(8, 8, 1) fn main() {
  let c = textureLoad(dataTextureC, vec2<i32>(0), 0);
  let h = textureLoad(historyTexture, vec2<i32>(0), 0, 0);
}`;

  function mockModule(): EmscriptenModule & { ccall: Mock } {
    return {
      ccall: vi.fn(() => 1),
      _malloc: vi.fn(() => 16),
      _free: vi.fn(),
      getValue: vi.fn(() => 0),
      lengthBytesUTF8: (s: string) => s.length,
      stringToUTF8: vi.fn(),
      HEAPU8: new Uint8Array(1),
      HEAPF32: new Float32Array(1),
    };
  }

  beforeEach(() => {
    state.initialized = true;
    wasmRef.module = mockModule();
    vi.spyOn(console, 'log').mockImplementation(() => {});
  });

  afterEach(() => {
    state.initialized = prev.initialized;
    wasmRef.module = prev.module;
    vi.restoreAllMocks();
  });

  it('computes main-entry dispatch and usage bits', () => {
    expect(shaderAnalysisArgs(src)).toEqual({
      workgroupX: 8,
      workgroupY: 8,
      usageBits: SHADER_USAGE_BITS.readsDataC | SHADER_USAGE_BITS.usesHistory,
    });
  });

  it.each([
    ['loadShader', loadShader],
    ['reloadShader', reloadShader],
  ] as const)('%s passes workgroupX/Y and usageBits as ccall ints', async (op, fn) => {
    const module = wasmRef.module as ReturnType<typeof mockModule>;
    expect(await fn('probe', src)).toBe(true);
    const call = module.ccall.mock.calls.find((c) => c[0] === op);
    expect(call).toBeDefined();
    expect(call![2]).toEqual(['number', 'number', 'number', 'number', 'number']);
    expect((call![3] as number[]).slice(2)).toEqual([8, 8, SHADER_USAGE_BITS.readsDataC | SHADER_USAGE_BITS.usesHistory]);
  });
});
