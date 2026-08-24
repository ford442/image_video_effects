// Spectral Smear — Batch 58D exact-history paint upgrade
// A owns the decayed spectral display history; B is intentionally unwritten.

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

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p); let f = fract(p); let s = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), s.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), s.x), s.y);
}

fn fbm(p: vec2<f32>) -> f32 {
  var sum = 0.0; var amp = 0.5; var q = p;
  for (var i = 0; i < 3; i++) { sum += amp * valueNoise(q); q *= 2.0; amp *= 0.5; }
  return sum;
}

fn spectralPalette(t: f32) -> vec3<f32> {
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

  // Saved mapping: trail decay, brush radius, color speed, intensity.
  let trailDecay = clamp(u.zoom_params.x, 0.0, 1.0);
  let brushRadius = clamp(u.zoom_params.y, 0.0, 0.5) * (1.0 + bass * 0.2);
  let colorSpeed = clamp(u.zoom_params.z, 0.0, 2.0) * (1.0 + mids * 0.8);
  let intensity = clamp(u.zoom_params.w, 0.0, 1.0) * (1.0 + treble * 0.5);

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

  let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let p = uv * aspectVec;
  let mouseDistance = length(p - springPos * aspectVec);
  let edgeNoise = fbm(p * 7.0 + vec2<f32>(time * 0.35, -time * 0.22));
  let held = select(0.45, 1.0, u.zoom_config.w > 0.5);
  let brush = smoothstep(brushRadius, brushRadius * 0.72, mouseDistance * (0.82 + 0.32 * edgeNoise)) * held;

  var clickBloom = 0.0;
  var clickHue = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i++) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age < 0.0 || age > 1.6) { continue; }
    let dist = length((uv - ripple.xy) * aspectVec);
    let radius = 0.03 + age * 0.16;
    let bloom = exp(-pow((dist - radius) * 24.0, 2.0)) * (1.0 - age / 1.6);
    clickBloom += bloom;
    clickHue += bloom * hash21(ripple.xy + vec2<f32>(ripple.z));
  }

  let flow = vec2<f32>(fbm(p * 3.0 + vec2<f32>(time * 0.11, 0.0)),
                       fbm(p * 3.0 + vec2<f32>(5.2, 1.3 - time * 0.08))) - vec2<f32>(0.5);
  let historyUv = clamp(uv - flow * (0.020 + mids * 0.008) - springVel * brush * 0.7, vec2<f32>(0.0), vec2<f32>(1.0));
  let previous = textureLoad(dataTextureC, historyCoord(historyUv, dims), 0);
  let hue = fract(time * colorSpeed + mouseDistance * 1.6 + (edgeNoise - 0.5) * 0.25 + clickHue);
  let paint = mix(source.rgb, spectralPalette(hue), 0.65) * (1.0 + clickBloom * 1.2);
  let paintMask = clamp((brush + clickBloom) * intensity, 0.0, 1.0);
  let decayed = previous.rgb * (0.90 + 0.09 * trailDecay);
  let historyColor = mix(decayed, paint * 1.8, paintMask);
  let hdr = source.rgb + historyColor * 0.5;
  let effectEnergy = clamp(max(max(historyColor.r, historyColor.g), historyColor.b) * 0.35 + paintMask * 0.65, 0.0, 1.0);
  let alpha = clamp(source.a + (1.0 - source.a) * effectEnergy, 0.0, 1.0);
  let display = vec4<f32>(acesToneMap(max(hdr, vec3<f32>(0.0))), alpha);
  textureStore(dataTextureA, pixel, display);
  textureStore(writeTexture, pixel, display);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
