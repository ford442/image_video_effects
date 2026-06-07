// ═══════════════════════════════════════════════════════════════════
//  Spore Galaxy
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
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(43.2, 17.8)));
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

  let arms = mix(2.0, 8.0, u.zoom_params.x);
  let swirl = mix(0.2, 3.0, u.zoom_params.y);
  let density = mix(15.0, 120.0, u.zoom_params.z);
  let nebula = mix(0.0, 1.0, u.zoom_params.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  p = p - mouse * 0.15;

  let r = length(p);
  let a = atan2(p.y, p.x);
  let armAngle = a + r * swirl * (3.0 + bass * 3.0) - time * 0.15;
  let armPhase = fract(armAngle * arms / 6.28318);
  let armDist = abs(armPhase - 0.5) * 2.0;
  let armCore = smoothstep(0.25, 0.0, armDist) * exp(-r * 2.5);

  let gridUV = uv * density + vec2<f32>(time * 0.02, -time * 0.015);
  let cell = floor(gridUV);
  let local = fract(gridUV) - 0.5;
  let rnd = hash22(cell);
  let sporeD = length(local - (rnd - 0.5) * 0.8);
  let spore = exp(-sporeD * sporeD * (50.0 + treble * 40.0)) * step(0.75, hash21(cell + vec2<f32>(13.3, 7.1)));

  let dust = hash21(floor(uv * 300.0 + time * 0.05)) * exp(-r * 1.8) * nebula;

  // Chromatic: R arm core, G spores, B nebula dust
  var color = vec3<f32>(0.01, 0.01, 0.03);
  color = color + vec3<f32>(1.0, 0.55, 0.25) * armCore * (1.0 + bass * 0.3);
  color = color + vec3<f32>(0.35, 0.95, 0.65) * spore * (0.6 + mids * 0.5);
  color = color + vec3<f32>(0.3, 0.5, 1.0) * dust * 0.5 * (1.0 + treble * 0.2);

  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  color = mix(color, prev.rgb * 0.92, 0.02 + bass * 0.01);

  let presence = sat(armCore * 0.9 + spore * 0.7 + dust * 0.4);
  let alpha = sat(0.08 + presence * 0.92);
  let depth = sat(0.92 - armCore * 0.6 - spore * 0.25);

  color = acesToneMap(color * 1.1);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(armCore, spore, dust, alpha));
}
