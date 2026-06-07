// ═══════════════════════════════════════════════════════════════════
//  Lava Lamp Blobs
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            upgraded-rgba, aces-tone-map, depth-aware
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
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(29.5, 11.3)));
}

fn blobField(p: vec2<f32>, time: f32, count: f32, speed: f32) -> f32 {
  var field = 0.0;
  for (var i = 0u; i < u32(count); i = i + 1u) {
    let fi = f32(i);
    let seed = hash22(vec2<f32>(fi, 11.7));
    let phase = fi * 6.28318 / count;
    let bx = sin(phase + time * speed * (0.3 + seed.x * 0.5)) * (0.5 + seed.x * 0.3);
    let by = -0.8 + fract(fi / count + time * speed * (0.1 + seed.y * 0.2)) * 1.6;
    let bpos = vec2<f32>(bx, by);
    let d = length(p - bpos);
    let size = 0.12 + seed.y * 0.08;
    field = field + exp(-d * d / (size * size));
  }
  return field;
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

  let blobCount = mix(2.0, 10.0, u.zoom_params.x);
  let riseSpeed = mix(0.05, 0.6, u.zoom_params.y);
  let melt = mix(0.0, 1.0, u.zoom_params.z);
  let heat = mix(0.3, 2.0, u.zoom_params.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  p = p + mouse * 0.1;

  let blobs = blobField(p, time, blobCount, riseSpeed);
  let blobShape = smoothstep(0.5, 1.2, blobs);
  let blobHalo = smoothstep(0.2, 0.8, blobs) * (1.0 - blobShape);

  let warm = 0.5 + 0.5 * sin(blobs * 3.0 + time + bass * 3.0);
  let cool = 0.5 + 0.5 * cos(blobs * 2.0 - time * 0.7 + mids * 2.0);

  // Chromatic: warm red-orange blobs, cool blue-green halo, white-hot centers
  var color = vec3<f32>(0.02, 0.02, 0.05);
  color = color + vec3<f32>(0.95, 0.35, 0.08) * blobShape * heat * warm * (1.0 + bass * 0.2);
  color = color + vec3<f32>(0.15, 0.75, 0.55) * blobHalo * melt * cool * (1.0 + mids * 0.15);
  color = color + vec3<f32>(1.0, 0.9, 0.7) * smoothstep(1.0, 1.5, blobs) * treble * 0.5;

  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  color = mix(color, prev.rgb * 0.9, 0.03 + bass * 0.01);

  let presence = sat(blobShape * 0.9 + blobHalo * 0.5);
  let alpha = sat(0.12 + presence * 0.88);
  let depth = sat(0.9 - blobShape * 0.55 - blobHalo * 0.2);

  color = acesToneMap(color * 1.1);
  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(blobShape, blobHalo, warm, alpha));
}
