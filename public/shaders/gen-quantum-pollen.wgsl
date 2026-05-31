// ═══════════════════════════════════════════════════════════════════
//  Quantum Pollen
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

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(23.7, 11.9)));
}

fn particleLayer(uv: vec2<f32>, time: f32, scale: f32, drift: vec2<f32>) -> vec3<f32> {
  let gridUV = uv * scale + drift * time;
  let cell = floor(gridUV);
  let local = fract(gridUV) - 0.5;
  let rnd = hash22(cell);
  let center = rnd - 0.5;
  let d = length(local - center * 0.7);
  let core = exp(-d * d * 36.0);
  let halo = exp(-d * d * 8.0);
  return vec3<f32>(core, halo, rnd.x);
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

  let swarmDensity = mix(10.0, 90.0, u.zoom_params.x);
  let driftSpeed = mix(0.05, 1.4, u.zoom_params.y);
  let bloom = mix(0.2, 2.0, u.zoom_params.z);
  let trail = mix(0.1, 1.2, u.zoom_params.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;

  let vortex = vec2<f32>(-p.y, p.x) * (0.08 + bass * 0.12);
  let mouseDrift = mouse * vec2<f32>(0.25, 0.2);
  let driftVec = vec2<f32>(0.06, -0.18) * driftSpeed + vortex + mouseDrift;

  let l0 = particleLayer(uv, time, swarmDensity * 0.5, driftVec);
  let l1 = particleLayer(uv + vec2<f32>(0.27, 0.13), time * 1.2, swarmDensity, driftVec * 1.3);
  let l2 = particleLayer(uv + vec2<f32>(0.59, 0.41), time * 1.7, swarmDensity * 1.6, driftVec * 1.9);

  let core = l0.x + l1.x + l2.x;
  let haze = l0.y * 0.6 + l1.y * 0.8 + l2.y;
  let sparkle = 0.5 + 0.5 * sin(time * (8.0 + treble * 24.0) + (l0.z + l1.z + l2.z) * 8.0);

  // Chromatic pollen: each layer its own color, R shifted
  var color = vec3<f32>(0.0);
  color = color + vec3<f32>(0.65, 0.95, 0.75) * l0.x * (1.0 + treble * 0.1);
  color = color + vec3<f32>(0.95, 0.65, 1.0) * l1.x * (1.0 + mids * 0.1);
  color = color + vec3<f32>(0.6, 0.8, 1.0) * l2.x * (1.0 + bass * 0.1);
  color = color + vec3<f32>(0.1, 0.2, 0.15) * haze * trail;
  color = color * (1.0 + bloom * 0.6) * (0.9 + mids * 0.8) * (0.7 + sparkle * 0.4);

  // Temporal trail persistence: pollen drift echoes
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  color = mix(color, prev.rgb * 0.92, trail * 0.05 + bass * 0.01);

  let presence = sat(core * 0.9 + haze * 0.4);
  let alpha = sat(presence * 0.92);
  let depth = sat(0.85 - core * 0.5 + haze * 0.1);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(core, haze, sparkle, alpha));
}
