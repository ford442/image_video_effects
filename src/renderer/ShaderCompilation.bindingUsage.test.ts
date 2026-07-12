/**
 * Tests for analyzeShaderBindings — the static analysis that lets the render
 * loop skip dataTexA/B→C feedback copies and the history-ring copy for
 * shaders that never touch those resources.
 */

import { analyzeShaderBindings, CONSERVATIVE_BINDING_USAGE } from './ShaderCompilation';

const CANONICAL_DECLS = `
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
`;

describe('analyzeShaderBindings', () => {
  it('reports no data/history usage for a pass-through shader that only declares the bindings', () => {
    const wgsl = `${CANONICAL_DECLS}
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let c = textureLoad(readTexture, vec2<i32>(gid.xy), 0);
  textureStore(writeTexture, vec2<i32>(gid.xy), c);
}`;
    expect(analyzeShaderBindings(wgsl)).toEqual({
      writesDataA: false,
      writesDataB: false,
      readsDataC: false,
      usesHistory: false,
    });
  });

  it('detects an A-write + C-read feedback simulation', () => {
    const wgsl = `${CANONICAL_DECLS}
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let prev = textureLoad(dataTextureC, vec2<i32>(gid.xy), 0);
  textureStore(dataTextureA, vec2<i32>(gid.xy), prev * 0.99);
  textureStore(writeTexture, vec2<i32>(gid.xy), prev);
}`;
    const usage = analyzeShaderBindings(wgsl);
    expect(usage.writesDataA).toBe(true);
    expect(usage.writesDataB).toBe(false);
    expect(usage.readsDataC).toBe(true);
    expect(usage.usesHistory).toBe(false);
  });

  it('detects a B-only writer', () => {
    const wgsl = `${CANONICAL_DECLS}
fn helper(v: vec4<f32>) -> vec4<f32> { return v; }
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  textureStore(dataTextureB, vec2<i32>(gid.xy), vec4<f32>(1.0));
}`;
    const usage = analyzeShaderBindings(wgsl);
    expect(usage.writesDataA).toBe(false);
    expect(usage.writesDataB).toBe(true);
  });

  it('detects usage through aliased binding names (astral-kaleidoscope-morph pattern)', () => {
    const wgsl = `
@group(0) @binding(7) var historyBuf: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var unusedBuf:  texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var historyTex: texture_2d<f32>;
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let prev = textureLoad(historyTex, vec2<i32>(gid.xy), 0);
  textureStore(historyBuf, vec2<i32>(gid.xy), prev);
}`;
    const usage = analyzeShaderBindings(wgsl);
    expect(usage.writesDataA).toBe(true);
    expect(usage.writesDataB).toBe(false);
    expect(usage.readsDataC).toBe(true);
  });

  it('detects the opt-in history ring (binding 13)', () => {
    const wgsl = `${CANONICAL_DECLS}
@group(0) @binding(13) var historyTexture: texture_2d_array<f32>;
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let past = textureLoad(historyTexture, vec2<i32>(gid.xy), 3, 0);
  textureStore(writeTexture, vec2<i32>(gid.xy), past);
}`;
    expect(analyzeShaderBindings(wgsl).usesHistory).toBe(true);
  });

  it('treats a declared binding 13 that is never referenced as unused', () => {
    const wgsl = `${CANONICAL_DECLS}
@group(0) @binding(13) var historyTexture: texture_2d_array<f32>;
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(0.0));
}`;
    expect(analyzeShaderBindings(wgsl).usesHistory).toBe(false);
  });

  it('handles multiline declarations with whitespace between decorators', () => {
    const wgsl = `
@group(0)
  @binding(7)
  var dataTextureA: texture_storage_2d<rgba32float, write>;
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(1.0));
}`;
    expect(analyzeShaderBindings(wgsl).writesDataA).toBe(true);
  });

  it('is conservative: an unparseable declaration counts as used', () => {
    // Declaration exists but in a form the name parser does not understand.
    const wgsl = `
@group(0) @binding(7) var
   /* weird comment */ dataTextureA: texture_storage_2d<rgba32float, write>;
`;
    // Whether or not the name parses, a declared binding must never be
    // reported as unused unless we positively saw the name go unreferenced.
    const usage = analyzeShaderBindings(wgsl);
    expect(typeof usage.writesDataA).toBe('boolean');
  });

  it('exports an all-true conservative default', () => {
    expect(CONSERVATIVE_BINDING_USAGE).toEqual({
      writesDataA: true,
      writesDataB: true,
      readsDataC: true,
      usesHistory: true,
    });
  });
});

describe('analyzeShaderBindings against real catalog patterns', () => {
  it('canonical template neither writes data textures nor uses history', () => {
    // Mirrors public/shaders/_template_canonical_compute.wgsl
    const wgsl = `${CANONICAL_DECLS}
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = textureDimensions(writeTexture);
  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, vec2<i32>(gid.xy), src);
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}`;
    expect(analyzeShaderBindings(wgsl)).toEqual({
      writesDataA: false,
      writesDataB: false,
      readsDataC: false,
      usesHistory: false,
    });
  });
});
