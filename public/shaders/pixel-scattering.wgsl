// ═══════════════════════════════════════════════════════════════════
//  Pixel Scattering v2
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba, velocity-field
//  Complexity: High
//  Chunks From: pixel-scattering, curl-noise, fibonacci
//  Created: 2026-05-31
//  By: 4-Agent Shader Upgrade Swarm
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

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash12(i), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn curl(p: vec2<f32>, t: f32) -> vec2<f32> {
  let eps = 0.01;
  let n = noise2(p + vec2<f32>(0.0, eps) + t);
  let s = noise2(p - vec2<f32>(0.0, eps) + t);
  let e = noise2(p + vec2<f32>(eps, 0.0) + t);
  let w = noise2(p - vec2<f32>(eps, 0.0) + t);
  return vec2<f32>(n - s, e - w) / (2.0 * eps);
}

fn fibonacciDir(idx: f32, count: f32) -> vec2<f32> {
  let angle = idx * 2.39996;
  let radius = sqrt(idx / count);
  return vec2<f32>(cos(angle) * radius, sin(angle) * radius);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;

  let baseRadius = u.zoom_params.x * 0.5 + 0.02;
  let scatterStrength = u.zoom_params.y * 0.25;
  let trailLength = u.zoom_params.z;
  let chaos = u.zoom_params.w;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;
  let toMouse = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(toMouse);

  let curlVel = curl(uv * 3.0, time * 0.3) * 0.02 * chaos;
  let fibIdx = hash12(uv * 50.0) * 64.0;
  let fibDir = fibonacciDir(fibIdx, 64.0);

  let interact = smoothstep(baseRadius, 0.0, dist);
  let dir = select(normalize(toMouse), vec2<f32>(1.0, 0.0), dist < 0.001);

  let noise = hash12(uv * 50.0 + time) - 0.5;
  let angleJitter = noise * chaos * 3.14159;
  let c = cos(angleJitter);
  let s = sin(angleJitter);
  let rotDir = vec2<f32>(dir.x * c - dir.y * s, dir.x * s + dir.y * c);

  let bassBurst = 1.0 + step(0.6, bass) * 2.0;
  let mouseWind = select(1.0, 2.5, mouseDown);

  let velocity = rotDir * interact * scatterStrength * bassBurst * mouseWind + curlVel + fibDir * interact * 0.01;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFactor = 1.0 + (1.0 - depth) * 0.8;

  let finalUV = uv + velocity * depthFactor;

  var accum = vec3<f32>(0.0);
  let samples = 4;
  let stepSize = trailLength * 0.015;
  for (var i = 0; i < samples; i = i + 1) {
    let t = f32(i) / f32(samples - 1);
    let sampleUV = finalUV - velocity * stepSize * t * depthFactor;
    let samp = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
    let falloff = 1.0 - t * 0.7;
    accum = accum + samp * falloff;
  }
  accum = accum / f32(samples);

  let chromaOffset = length(velocity) * 0.03 * (1.0 + mids);
  let r = textureSampleLevel(readTexture, u_sampler, finalUV + vec2<f32>(chromaOffset, 0.0), 0.0).r;
  let b = textureSampleLevel(readTexture, u_sampler, finalUV - vec2<f32>(chromaOffset, 0.0), 0.0).b;
  accum = vec3<f32>(r * 0.5 + accum.r * 0.5, accum.g, b * 0.5 + accum.b * 0.5);

  let velMag = length(velocity) * 10.0;
  let glow = vec3<f32>(0.5 + rotDir.x * 0.5, 0.3 + rotDir.y * 0.3, 0.6) * interact * velMag * 0.3;
  let hdrAccum = (accum + glow) * (1.0 + treble * 0.3);

  let alpha = clamp(velMag * depthFactor * 0.5 + 0.4, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(hdrAccum, alpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(velocity, velMag, alpha));
}
