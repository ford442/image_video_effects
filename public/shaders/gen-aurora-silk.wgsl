// ═══════════════════════════════════════════════════════════════════
//  Aurora Silk
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            upgraded-rgba, depth-aware
//  Complexity: High
//  Created: 2026-05-31
//  Upgraded: 2026-05-31
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

fn sat(x: f32) -> f32 {
  return clamp(x, 0.0, 1.0);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u2.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u2.x),
    u2.y
  );
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var q = p;
  for (var i = 0u; i < 5u; i = i + 1u) {
    v = v + a * noise2(q);
    q = q * 2.02 + vec2<f32>(1.7, 9.2);
    a = a * 0.5;
  }
  return v;
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let coord = vec2<i32>(gid.xy);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz * 2.0 - 1.0;

  let bandCount = mix(2.0, 12.0, u.zoom_params.x);
  let flowSpeed = mix(0.15, 1.8, u.zoom_params.y);
  let ribbonWidth = mix(0.08, 0.55, u.zoom_params.z);
  let glow = mix(0.3, 2.3, u.zoom_params.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  p = p + mouse * vec2<f32>(0.35, 0.2);

  let wind = fbm(p * vec2<f32>(1.2, 2.0) + vec2<f32>(time * flowSpeed * 0.12, 0.0));
  let curtain = exp(-abs(p.x) * (1.2 + mids * 0.8));
  let ribbons = sin((p.y + wind * 0.6) * bandCount * 6.0 + time * flowSpeed * (1.0 + bass * 1.4));
  let band = smoothstep(1.0 - ribbonWidth, 1.0, abs(ribbons));
  let shimmer = 0.5 + 0.5 * sin(time * (2.0 + treble * 14.0) + p.y * 9.0);

  let presence = sat(curtain * (band * 0.85 + wind * 0.4) * (0.8 + bass * 0.7));

  // Chromatic aurora palette shifted by audio bands
  var color = palette(
    wind + shimmer * 0.25 + bass * 0.05,
    vec3<f32>(0.35, 0.45, 0.55),
    vec3<f32>(0.35, 0.35, 0.45),
    vec3<f32>(1.0, 1.0, 1.0),
    vec3<f32>(0.0, 0.12 + treble * 0.04, 0.25 + mids * 0.05)
  );
  color = color * (0.2 + 1.5 * presence) * glow;

  // Temporal silk persistence: aurora ribbons fade slowly
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  color = mix(color, prev.rgb * 0.92, 0.03 + bass * 0.01);

  let alpha = sat(presence * 0.9 + shimmer * 0.08);
  let depth = sat(0.9 - presence * 0.75);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(wind, band, shimmer, alpha));
}
