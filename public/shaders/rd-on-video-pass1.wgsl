// ═══════════════════════════════════════════════════════════════════
//  RD on Video (Pass 1: Gray-Scott Update)
//  Category: simulation
//  Features: multi-pass-1, temporal, video-driven
// ═══════════════════════════════════════════════════════════════════

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

fn safeState(uv: vec2<f32>) -> vec4<f32> {
  return textureSampleLevel(dataTextureC, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let px = 1.0 / res;
  let coord = vec2<i32>(gid.xy);
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let luma = dot(src.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));

  var state = textureLoad(dataTextureC, coord, 0);
  var a = state.r;
  var b = state.g;

  if (u.config.x < 0.1 || (a < 0.001 && b < 0.001)) {
    let seed = smoothstep(0.2, 0.85, luma);
    a = 1.0 - seed * 0.35;
    b = seed * 0.65;
  }

  let l = safeState(uv - vec2<f32>(px.x, 0.0));
  let r = safeState(uv + vec2<f32>(px.x, 0.0));
  let d = safeState(uv - vec2<f32>(0.0, px.y));
  let up = safeState(uv + vec2<f32>(0.0, px.y));

  let lapA = l.r + r.r + d.r + up.r - 4.0 * a;
  let lapB = l.g + r.g + d.g + up.g - 4.0 * b;

  let feedBase = mix(0.015, 0.070, clamp(u.zoom_params.x, 0.0, 1.0));
  let killBase = mix(0.030, 0.080, clamp(u.zoom_params.y, 0.0, 1.0));
  let diffusionScale = mix(0.75, 1.40, clamp(u.zoom_params.z, 0.0, 1.0));
  let dt = mix(0.60, 1.20, clamp(u.zoom_params.w, 0.0, 1.0));

  let drive = smoothstep(0.10, 0.90, luma);
  let feed = feedBase + drive * 0.020;
  let kill = killBase - drive * 0.012;

  let dA = (1.00 * diffusionScale) * lapA - a * b * b + feed * (1.0 - a);
  let dB = (0.45 * diffusionScale) * lapB + a * b * b - (kill + feed) * b;

  a = clamp(a + dA * dt, 0.0, 1.0);
  b = clamp(b + dB * dt, 0.0, 1.0);

  textureStore(dataTextureA, coord, vec4<f32>(a, b, luma, 1.0));
  textureStore(writeTexture, coord, src);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
