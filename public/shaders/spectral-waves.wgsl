// Spectral Waves — Batch 58D caustic-history upgrade
// A owns premultiplied display RGBA history; B is intentionally unwritten.

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

fn palette(t: f32) -> vec3<f32> {
  return vec3<f32>(0.50, 0.49, 0.52) + vec3<f32>(0.48, 0.44, 0.42) *
         cos(TAU * (vec3<f32>(1.0, 0.82, 0.58) * t + vec3<f32>(0.06, 0.30, 0.54)));
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

  // Saved mapping: frequency, speed, amplitude, chromatic split.
  let frequency = 10.0 + u.zoom_params.x * 90.0;
  let speed = u.zoom_params.y * 5.0;
  let maxAmplitude = u.zoom_params.z * 0.1 * (1.0 + bass * 0.3 + treble * 0.15);
  let aberration = u.zoom_params.w * 0.05;

  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let hasSpring = arrayLength(&extraBuffer) >= 139u;
  var springPos = rawMouse; var springVel = vec2<f32>(0.0); var lastTime = time; var initialized = false;
  if (hasSpring) {
    springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    lastTime = extraBuffer[137]; initialized = extraBuffer[138] > 0.5;
  }
  if (!initialized) { springPos = rawMouse; springVel = vec2<f32>(0.0); }
  let dt = select(0.0, clamp(time - lastTime, 0.0, 0.05), initialized);
  let omega = 9.0; let springDecay = exp(-omega * dt); let delta = springPos - rawMouse;
  let temp = (springVel + omega * delta) * dt;
  springVel = (springVel - omega * temp) * springDecay;
  springPos = rawMouse + (delta + temp) * springDecay;
  if (hasSpring && gid.x == 0u && gid.y == 0u) {
    extraBuffer[133] = springPos.x; extraBuffer[134] = springPos.y;
    extraBuffer[135] = springVel.x; extraBuffer[136] = springVel.y;
    extraBuffer[137] = time; extraBuffer[138] = 1.0;
  }

  let p = uv * aspectVec;
  let center = springPos * aspectVec;
  let dist = length(p - center);
  let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let sourceLuma = luma(source.rgb);
  let wave = sin(dist * frequency - time * speed);
  let echo = sin(dist * frequency * 0.47 + time * speed * 0.72 + bass * 3.0);
  var displacement = (wave * 0.78 + echo * 0.22) * maxAmplitude * (0.35 + sourceLuma * 0.95);
  var clickEnergy = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i++) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age < 0.0 || age > 2.0) { continue; }
    let rd = length(p - ripple.xy * aspectVec);
    let fade = exp(-age * 1.5) * (1.0 - smoothstep(1.6, 2.0, age));
    let train = sin(rd * frequency * 0.8 - age * 8.0) * fade * exp(-rd * 3.0);
    displacement += train * maxAmplitude * (0.35 + sourceLuma * 0.95);
    clickEnergy += abs(train);
  }

  let safeDir = ((p - center) / max(dist, 0.001)) / aspectVec;
  let uvR = clamp(uv - safeDir * displacement * (1.0 + aberration), vec2<f32>(0.0), vec2<f32>(1.0));
  let uvG = clamp(uv - safeDir * displacement, vec2<f32>(0.0), vec2<f32>(1.0));
  let uvB = clamp(uv - safeDir * displacement * (1.0 - aberration), vec2<f32>(0.0), vec2<f32>(1.0));
  var hdr = vec3<f32>(textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r,
                      textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g,
                      textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b);

  let crest = smoothstep(0.58, 1.0, wave) + smoothstep(0.74, 1.0, echo) * 0.55;
  let ring = u32(clamp(dist * 16.0, 0.0, 127.0));
  let fftVoice = extraBuffer[5u + ring] * 0.35;
  let caustic = pow(max(crest, 0.0), 2.6) * (0.35 + sourceLuma) * (1.0 + treble * 0.8) +
                 pow(max(crest, 0.0), 2.0) * fftVoice + clickEnergy * 0.4;
  hdr = hdr * (0.94 + crest * 0.2) + palette(wave * 0.18 + dist * 0.7 - time * 0.04 + mids * 0.2) * caustic * 1.55;

  // Persist caustics through exact A→C display history.
  let historyUv = clamp(uv - safeDir * displacement * 0.35, vec2<f32>(0.0), vec2<f32>(1.0));
  let previous = textureLoad(dataTextureC, historyCoord(historyUv, dims), 0);
  let persistence = clamp(0.08 + caustic * 0.16 + u.zoom_config.w * 0.08, 0.0, 0.48);
  hdr = mix(hdr, previous.rgb * 0.96, persistence);

  let effectEnergy = clamp(abs(displacement) * 9.0 + caustic * 0.3 + previous.a * persistence, 0.0, 1.0);
  let alpha = clamp(source.a + (1.0 - source.a) * effectEnergy, 0.0, 1.0);
  let mapped = acesToneMap(max(hdr, vec3<f32>(0.0)));
  let display = vec4<f32>(mapped * alpha, alpha);
  textureStore(dataTextureA, pixel, display);
  textureStore(writeTexture, pixel, display);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
