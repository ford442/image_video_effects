// Spectral Glitch Sort — Batch 58D canonical temporal upgrade
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

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
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
  let res = u.config.zw;
  let pixel = vec2<i32>(gid.xy);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let dims = vec2<i32>(textureDimensions(dataTextureC));
  let time = u.config.x;
  let aspectVec = vec2<f32>(res.x / max(res.y, 1.0), 1.0);
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Saved mapping: x sort length, y threshold, z direction, w noise.
  let strength = mix(0.0, 0.5, u.zoom_params.x) * (1.0 + bass * 0.4);
  let threshold = u.zoom_params.y;
  let baseAngle = u.zoom_params.z * TAU;
  let noiseAmount = u.zoom_params.w;

  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let hasSpring = arrayLength(&extraBuffer) >= 139u;
  var springPos = rawMouse;
  var springVel = vec2<f32>(0.0);
  var lastTime = time;
  var initialized = false;
  if (hasSpring) {
    springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    lastTime = extraBuffer[137];
    initialized = extraBuffer[138] > 0.5;
  }
  if (!initialized) { springPos = rawMouse; springVel = vec2<f32>(0.0); }
  let dt = select(0.0, clamp(time - lastTime, 0.0, 0.05), initialized);
  let omega = 10.0;
  let decay = exp(-omega * dt);
  let delta = springPos - rawMouse;
  let temp = (springVel + omega * delta) * dt;
  springVel = (springVel - omega * temp) * decay;
  springPos = rawMouse + (delta + temp) * decay;
  if (hasSpring && gid.x == 0u && gid.y == 0u) {
    extraBuffer[133] = springPos.x; extraBuffer[134] = springPos.y;
    extraBuffer[135] = springVel.x; extraBuffer[136] = springVel.y;
    extraBuffer[137] = time; extraBuffer[138] = 1.0;
  }

  var tearBoost = 0.0;
  var tearAngle = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i++) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age < 0.0 || age > 0.9) { continue; }
    let dist = length((uv - ripple.xy) * aspectVec);
    let front = exp(-pow((dist - age * 0.22) * 18.0, 2.0));
    let energy = front * (1.0 - age / 0.9);
    tearBoost += energy * 1.7;
    tearAngle += energy * (hash12(ripple.xy + vec2<f32>(ripple.z)) - 0.5) * 2.4;
  }

  let mouseDist = length((uv - springPos) * aspectVec);
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  let influence = (1.0 - smoothstep(0.05, 0.5, mouseDist)) * (1.0 + held);
  let sortAngle = baseAngle + tearAngle + mids * 0.12;
  let dir = vec2<f32>(cos(sortAngle), sin(sortAngle));
  let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let sortable = smoothstep(threshold, threshold + 0.2, luma(source.rgb));
  let block = floor(uv * vec2<f32>(24.0, 18.0));
  let noise = hash12(block + floor(time * 8.0) * vec2<f32>(0.17, 0.11));
  let fftIndex = 5u + (u32(max(block.x, 0.0)) * 7u + u32(max(block.y, 0.0)) * 13u) % 128u;
  let fftVoice = extraBuffer[fftIndex];
  let voicedNoise = noise * (1.0 + fftVoice * 1.5 + treble * 0.35);
  let localStrength = strength * (1.0 + influence * 2.0) + tearBoost * strength;
  let offset = -dir * localStrength * sortable * mix(1.0, voicedNoise * 2.0, noiseAmount);
  let sortedUv = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));

  var hdr = textureSampleLevel(readTexture, u_sampler, sortedUv, 0.0).rgb;
  let split = smoothstep(0.004, 0.04, length(offset));
  hdr.r = mix(hdr.r, textureSampleLevel(readTexture, u_sampler, clamp(sortedUv + dir * 0.003, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r, split);
  hdr.b = mix(hdr.b, textureSampleLevel(readTexture, u_sampler, clamp(sortedUv - dir * 0.003, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b, split);

  let trailUv = clamp(uv - dir * (0.008 + tearBoost * 0.025), vec2<f32>(0.0), vec2<f32>(1.0));
  let previous = textureLoad(dataTextureC, historyCoord(trailUv, dims), 0);
  let trailMix = clamp(0.1 + tearBoost * 0.35 + noiseAmount * 0.16, 0.0, 0.72);
  hdr = mix(hdr, previous.rgb * (0.91 + 0.04 * mids), trailMix);
  hdr += vec3<f32>(0.08, 0.025, 0.14) * treble * voicedNoise * sortable;

  let effectEnergy = clamp(length(offset) * 7.0 + tearBoost * 0.6 + split * 0.3 + previous.a * trailMix, 0.0, 1.0);
  let alpha = clamp(source.a + (1.0 - source.a) * effectEnergy, 0.0, 1.0);
  let display = vec4<f32>(acesToneMap(max(hdr, vec3<f32>(0.0))), alpha);
  textureStore(dataTextureA, pixel, display);
  textureStore(writeTexture, pixel, display);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
