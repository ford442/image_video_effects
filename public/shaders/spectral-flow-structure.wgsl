// Spectral Flow Structure — Batch 58D truthful temporal LIC upgrade
// A owns exact display RGBA history; B is intentionally unwritten.

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

const TAU: f32 = 6.28318530718;

fn luma(c: vec3<f32>) -> f32 { return dot(c, vec3<f32>(0.299, 0.587, 0.114)); }

fn sampleLuma(uv: vec2<f32>) -> f32 {
  return luma(textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
}

fn flowDirection(uv: vec2<f32>, texel: vec2<f32>) -> vec4<f32> {
  let gx = sampleLuma(uv + vec2<f32>(texel.x, 0.0)) - sampleLuma(uv - vec2<f32>(texel.x, 0.0));
  let gy = sampleLuma(uv + vec2<f32>(0.0, texel.y)) - sampleLuma(uv - vec2<f32>(0.0, texel.y));
  let jxx = gx * gx; let jyy = gy * gy; let jxy = gx * gy;
  let trace = jxx + jyy;
  let delta = sqrt(max((jxx - jyy) * (jxx - jyy) + 4.0 * jxy * jxy, 0.0));
  let l1 = 0.5 * (trace + delta); let l2 = 0.5 * (trace - delta);
  var dir = vec2<f32>(1.0, 0.0);
  if (abs(jxy) > 0.00001 || abs(jxx - l1) > 0.00001) { dir = normalize(vec2<f32>(l1 - jyy, jxy)); }
  let coherency = clamp((l1 - l2) / max(l1 + l2, 0.0001), 0.0, 1.0);
  return vec4<f32>(dir, coherency, trace);
}

fn lic(uv: vec2<f32>, dir: vec2<f32>, texel: vec2<f32>, steps: i32, stride: f32) -> f32 {
  var sum = 0.0; var weight = 0.0;
  for (var i = -steps; i <= steps; i++) {
    let w = 1.0 - abs(f32(i)) / f32(steps + 1);
    sum += sampleLuma(uv + dir * texel * stride * f32(i)) * w;
    weight += w;
  }
  return sum / max(weight, 0.001);
}

fn palette(t: f32) -> vec3<f32> {
  return vec3<f32>(0.5) + vec3<f32>(0.5) * cos(TAU * (vec3<f32>(t) + vec3<f32>(0.0, 0.33, 0.67)));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn historyCoord(uv: vec2<f32>, dims: vec2<i32>) -> vec2<i32> {
  return clamp(vec2<i32>(uv * vec2<f32>(dims)), vec2<i32>(0), dims - vec2<i32>(1));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw; let pixel = vec2<i32>(gid.xy);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let texel = 1.0 / res; let time = u.config.x;
  let dims = vec2<i32>(textureDimensions(dataTextureC));
  let aspectVec = vec2<f32>(res.x / max(res.y, 1.0), 1.0);
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;

  // Saved mapping: LIC steps, coherency boost, sort threshold, temporal smoothing.
  let licSteps = i32(mix(6.0, 24.0, u.zoom_params.x));
  let coherencyBoost = mix(0.5, 3.0, u.zoom_params.y);
  let sortThreshold = u.zoom_params.z * 0.5;
  let smoothing = mix(0.0, 0.9, u.zoom_params.w);

  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let hasSpring = arrayLength(&extraBuffer) >= 139u;
  var springPos = rawMouse; var springVel = vec2<f32>(0.0); var lastTime = time; var initialized = false;
  if (hasSpring) {
    springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]); springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    lastTime = extraBuffer[137]; initialized = extraBuffer[138] > 0.5;
  }
  if (!initialized) { springPos = rawMouse; springVel = vec2<f32>(0.0); }
  let dt = select(0.0, clamp(time - lastTime, 0.0, 0.05), initialized);
  let omega = 8.0; let decay = exp(-omega * dt); let delta = springPos - rawMouse;
  let temp = (springVel + omega * delta) * dt;
  springVel = (springVel - omega * temp) * decay; springPos = rawMouse + (delta + temp) * decay;
  if (hasSpring && gid.x == 0u && gid.y == 0u) {
    extraBuffer[133] = springPos.x; extraBuffer[134] = springPos.y; extraBuffer[135] = springVel.x; extraBuffer[136] = springVel.y;
    extraBuffer[137] = time; extraBuffer[138] = 1.0;
  }

  let tensor = flowDirection(uv, texel);
  let coherence = pow(tensor.z, 1.0 / coherencyBoost);
  var dir = tensor.xy;
  let mouseDelta = (uv - springPos) * aspectVec;
  let mouseDist = length(mouseDelta);
  let held = select(0.45, 1.0, u.zoom_config.w > 0.5);
  let vortex = vec2<f32>(-mouseDelta.y, mouseDelta.x) / max(mouseDist, 0.001) * exp(-mouseDist * 6.0) * held;

  var rippleTurbulence = vec2<f32>(0.0); var rippleEnergy = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i++) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age < 0.0 || age > 2.2) { continue; }
    let deltaR = (uv - ripple.xy) * aspectVec; let dist = length(deltaR);
    let front = exp(-pow((dist - age * 0.24) * 18.0, 2.0)) * (1.0 - age / 2.2);
    rippleTurbulence += vec2<f32>(-deltaR.y, deltaR.x) / max(dist, 0.001) * front;
    rippleEnergy += front;
  }
  dir = normalize(dir + vortex * (1.0 + bass) + rippleTurbulence * 1.4 + vec2<f32>(mids, -treble) * 0.05);
  let audioRotation = time * (0.10 + bass * 0.13) + mids * 0.25;
  let c = cos(audioRotation); let s = sin(audioRotation);
  dir = mat2x2<f32>(c, -s, s, c) * dir;

  let licValue = lic(uv, dir, texel, licSteps, 1.2 + treble * 1.8);
  let sortExtent = (0.015 + coherence * 0.07) * (1.0 + bass * 0.7);
  var sorted = vec3<f32>(0.0); var weights = 0.0;
  for (var i = -4; i <= 4; i++) {
    let sampleUv = clamp(uv + dir * sortExtent * f32(i) / 4.0, vec2<f32>(0.0), vec2<f32>(1.0));
    let sample = textureSampleLevel(readTexture, u_sampler, sampleUv, 0.0).rgb;
    let weight = select(0.0, luma(sample), luma(sample) > sortThreshold * (1.0 - coherence * 0.5));
    sorted += sample * weight; weights += weight;
  }
  let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let sortedColor = select(source.rgb, sorted / max(weights, 0.001), weights > 0.001);
  var hdr = mix(source.rgb, sortedColor, clamp(coherence * (0.35 + smoothing * 0.65), 0.0, 1.0));
  hdr *= 0.65 + licValue * (0.5 + mids * 0.2);
  hdr += palette(atan2(dir.y, dir.x) / TAU + 0.5 + time * 0.03) * coherence * (0.22 + treble * 0.16);

  // Temporal Smoothing is now a real exact-C display-history blend.
  let historyUv = clamp(uv - dir * texel * (2.0 + bass * 5.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let previous = textureLoad(dataTextureC, historyCoord(historyUv, dims), 0);
  hdr = mix(hdr, previous.rgb * 0.965, smoothing * (0.35 + coherence * 0.45));
  let effectEnergy = clamp(coherence * 0.55 + rippleEnergy * 0.35 + length(vortex) * 0.2 + previous.a * smoothing * 0.2, 0.0, 1.0);
  let alpha = clamp(source.a + (1.0 - source.a) * effectEnergy, 0.0, 1.0);
  let display = vec4<f32>(acesToneMap(max(hdr, vec3<f32>(0.0))), alpha);
  textureStore(dataTextureA, pixel, display); textureStore(writeTexture, pixel, display);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
