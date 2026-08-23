// ═══ CHROMATOGRAPHIC FLUID — DIFFUSE (Jacobi) ══════════════════════════════
//  Per-channel viscosity: R sticky, B runny. Repeat 2× under pass budget.

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

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn load(p: vec2<i32>, resI: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), resI - vec2<i32>(1)), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }

  let split = u.zoom_params.x;
  let visR = mix(0.08, 0.42, 1.0 - split);
  let visG = mix(0.12, 0.28, split);
  let visB = mix(0.18, 0.55, split);
  let vis = vec3<f32>(visR, visG, visB);

  let c = load(pixel, resI);
  let n = load(pixel + vec2<i32>(0, 1), resI).rgb;
  let s = load(pixel + vec2<i32>(0, -1), resI).rgb;
  let e = load(pixel + vec2<i32>(1, 0), resI).rgb;
  let w = load(pixel + vec2<i32>(-1, 0), resI).rgb;
  let lap = (n + s + e + w) * 0.25 - c.rgb;
  let dye = clamp(c.rgb + lap * vis, vec3<f32>(0.0), vec3<f32>(4.0));
  textureStore(dataTextureA, pixel, vec4<f32>(dye, c.a));
}
