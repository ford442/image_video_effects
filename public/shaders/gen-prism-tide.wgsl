// ═══════════════════════════════════════════════════════════════════
//  Prism Tide
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

  let waveScale = mix(1.0, 9.0, u.zoom_params.x);
  let refractAmt = mix(0.0, 0.15, u.zoom_params.y);
  let pulse = mix(0.1, 2.0, u.zoom_params.z);
  let saturation = mix(0.3, 1.6, u.zoom_params.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  p = p + mouse * vec2<f32>(0.3, 0.2);

  let n = noise2(p * 3.0 + vec2<f32>(time * 0.1, -time * 0.14));
  let refracted = p + vec2<f32>(sin(p.y * 8.0 + time), cos(p.x * 7.0 - time)) * refractAmt * (0.4 + n);
  let phase = length(refracted) * waveScale - time * (0.7 + bass * 0.8);

  // Chromatic prism: R/G/B get increasingly displaced phase
  let r = 0.5 + 0.5 * sin(phase + pulse * 1.7 + treble * 1.2);
  let g = 0.5 + 0.5 * sin(phase + 2.094 + pulse * 1.1 + mids * 1.5 + bass * 0.1);
  let b = 0.5 + 0.5 * sin(phase + 4.188 + pulse * 1.4 + bass * 1.6 + treble * 0.1);

  let crest = smoothstep(0.55, 1.0, max(max(r, g), b));
  let foam = smoothstep(0.65, 1.0, sin(phase * 2.3 + n * 2.0));
  let sparkle = 0.5 + 0.5 * sin(time * (4.0 + treble * 22.0) + n * 15.0);

  var color = vec3<f32>(r, g, b) * saturation;
  color = color + vec3<f32>(0.8, 0.9, 1.0) * foam * 0.35 * (1.0 + treble * 0.6);
  color = color * (0.75 + crest * 0.75) * (0.85 + sparkle * 0.25);

  // Temporal tide persistence: crests and foam accumulate
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  color = mix(color, prev.rgb * 0.9, foam * 0.06 + bass * 0.01);

  let presence = sat(crest * 0.85 + foam * 0.5);
  let alpha = sat(0.1 + presence * 0.9);
  let depth = sat(0.8 - crest * 0.55 + noise2(p * 6.0) * 0.12);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(crest, foam, sparkle, alpha));
}
