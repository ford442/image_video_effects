// ═══════════════════════════════════════════════════════════════════
//  Luminous Cauldron
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

  let boilRate = mix(0.1, 2.2, u.zoom_params.x);
  let convection = mix(0.2, 2.0, u.zoom_params.y);
  let foam = mix(0.0, 1.0, u.zoom_params.z);
  let radiance = mix(0.3, 2.5, u.zoom_params.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  p = p - mouse * 0.2;

  let bowl = smoothstep(1.05, 0.2, length(p));
  let swirl = atan2(p.y, p.x) + time * boilRate;
  let convectionWaves = 0.5 + 0.5 * sin(swirl * 6.0 + length(p) * 12.0 - time * convection * (1.0 + mids));

  let bubbleGrid = floor((uv + vec2<f32>(0.0, time * boilRate * 0.2)) * 80.0);
  let bubbleRnd = hash21(bubbleGrid);
  let bubbleCell = fract((uv + vec2<f32>(0.0, time * boilRate * 0.2)) * 80.0) - 0.5;
  let bubble = exp(-dot(bubbleCell, bubbleCell) * (30.0 + bass * 35.0)) * step(0.82, bubbleRnd);
  let froth = bubble * foam;

  let sparks = step(0.997 - treble * 0.03, hash21(floor((uv + vec2<f32>(time * 0.04, -time * 0.03)) * 260.0)));
  let sparkPulse = 0.5 + 0.5 * sin(time * 18.0 + bubbleRnd * 40.0);

  // Chromatic cauldron: purple bowl, orange heat, white foam, blue sparks
  var color = vec3<f32>(0.02, 0.01, 0.04);
  color = color + vec3<f32>(0.5, 0.15, 0.95) * bowl * convectionWaves * radiance * (1.0 + mids * 0.1);
  color = color + vec3<f32>(1.0, 0.5, 0.15) * bowl * (1.0 - convectionWaves) * (0.4 + bass);
  color = color + vec3<f32>(0.95, 1.0, 0.85) * froth * 0.7 * (1.0 + treble * 0.1);
  color = color + vec3<f32>(0.6, 0.85, 1.0) * sparks * sparkPulse * (0.3 + treble);

  // Temporal boil persistence: previous bubbles linger
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  color = mix(color, prev.rgb * 0.9, 0.03 + bass * 0.01);

  let presence = sat(bowl * 0.8 + froth * 0.7 + sparks);
  let alpha = sat(0.08 + presence * 0.92);
  let depth = sat(0.9 - bowl * 0.6 - froth * 0.25);

  color = acesToneMap(color * 1.1);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(convectionWaves, bubble, sparks, alpha));
}
