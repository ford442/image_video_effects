// ═══════════════════════════════════════════════════════════════════
//  Neon Snowfall
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            upgraded-rgba, depth-aware, aces-tone-map
//  Complexity: High
//  Created: 2026-05-31
//  Upgraded: 2026-06-06
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

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(31.2, 13.6)));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
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

  let flakeDensity = mix(20.0, 180.0, u.zoom_params.x);
  let fallSpeed = mix(0.08, 2.0, u.zoom_params.y);
  let chroma = mix(0.2, 2.0, u.zoom_params.z);
  let streak = mix(0.0, 1.0, u.zoom_params.w);

  let gridUV = vec2<f32>(uv.x, uv.y + time * fallSpeed) * flakeDensity;
  let cell = floor(gridUV);
  let local = fract(gridUV) - 0.5;
  let rnd = hash22(cell);
  let flakePos = rnd - 0.5 + vec2<f32>(mouse.x * 0.35, 0.0);
  let d = length(local - flakePos * 0.9);

  let flake = exp(-d * d * (40.0 + bass * 30.0));
  let trail = exp(-(local.x - flakePos.x) * (local.x - flakePos.x) * 130.0) * sat(0.45 - (local.y - flakePos.y)) * streak;
  let twinkle = 0.5 + 0.5 * sin(time * (8.0 + treble * 26.0) + rnd.x * 20.0);

  // Chromatic snowfall: each flake gets a hue, trails are shifted
  let hue = rnd.x + time * 0.03 + mids * 0.15;
  let r = 0.5 + 0.5 * sin(6.28318 * (hue + 0.0 + treble * 0.05));
  let g = 0.5 + 0.5 * sin(6.28318 * (hue + 0.33 + bass * 0.03));
  let b = 0.5 + 0.5 * sin(6.28318 * (hue + 0.66 + mids * 0.04));

  var color = vec3<f32>(0.01, 0.02, 0.05);
  color = color + vec3<f32>(r, g, b) * flake * chroma * (0.6 + twinkle * 0.7);
  color = color + vec3<f32>(r * 0.8, g * 1.1, b * 0.9) * trail * 0.55;

  // Temporal snowfall persistence: streaks accumulate
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  color = mix(color, prev.rgb * 0.92, trail * 0.08 + bass * 0.01);

  let presence = sat(flake * 0.95 + trail * 0.6);
  let alpha = sat(0.06 + presence * 0.94);
  let depth = sat(0.92 - flake * 0.65 - trail * 0.25);

  color = acesToneMap(color * 1.1);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(flake, trail, twinkle, alpha));
}
