// ═══════════════════════════════════════════════════════════════════
//  Plasma Jet Stream
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            upgraded-rgba, depth-aware
//  Complexity: High
//  Created: 2026-05-31
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

  let jetCount = mix(1.0, 8.0, u.zoom_params.x);
  let velocity = mix(0.5, 4.0, u.zoom_params.y);
  let spread = mix(0.02, 0.25, u.zoom_params.z);
  let turbulence = mix(0.0, 1.0, u.zoom_params.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;

  let aim = mouse * 0.4;
  var jetIntensity = 0.0;
  var jetHeat = 0.0;

  for (var j = 0u; j < u32(jetCount); j = j + 1u) {
    let fj = f32(j);
    let seed = hash21(vec2<f32>(fj, 7.3));
    let angle = (fj / jetCount) * 6.28318 + seed * 2.0 + aim.x * 2.0;
    let dir = vec2<f32>(cos(angle), sin(angle));
    let perp = vec2<f32>(-dir.y, dir.x);

    let along = dot(p - aim * 0.5, dir);
    let across = dot(p - aim * 0.5, perp);
    let pulse = 0.5 + 0.5 * sin(time * velocity * (1.0 + seed * 2.0) + fj * 3.7 + bass * 4.0);
    let width = spread * (0.6 + pulse * 0.6) * (1.0 + mids * 0.3);
    let turb = sin(across * 30.0 + along * 5.0 - time * velocity * 2.0) * turbulence * 0.15;
    let dist = abs(across + turb);
    let jcore = exp(-dist * dist / (width * width * 0.2 + 0.001)) * pulse;
    let jhalo = exp(-dist * dist / (width * width * 0.8 + 0.001)) * 0.4;
    jetIntensity = jetIntensity + jcore + jhalo;
    jetHeat = jetHeat + jcore * (1.0 + bass);
  }

  let shock = smoothstep(0.6, 1.0, jetIntensity);
  let spark = step(0.996 - treble * 0.03, hash21(floor((uv + time * 0.1) * 200.0))) * shock;

  // Chromatic: R core, G shock, B sparks
  var color = vec3<f32>(0.01, 0.01, 0.02);
  color = color + vec3<f32>(1.0, 0.35, 0.05) * jetHeat * (1.0 + bass * 0.25);
  color = color + vec3<f32>(0.85, 0.9, 0.3) * shock * 0.5 * (1.0 + mids * 0.15);
  color = color + vec3<f32>(0.4, 0.7, 1.0) * spark * (0.5 + treble);

  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  color = mix(color, prev.rgb * 0.92, 0.03 + bass * 0.015);

  let presence = sat(jetIntensity * 0.85 + spark * 0.8);
  let alpha = sat(0.15 + presence * 0.85);
  let depth = sat(0.95 - jetHeat * 0.6 - spark * 0.2);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(jetIntensity, shock, spark, alpha));
}
