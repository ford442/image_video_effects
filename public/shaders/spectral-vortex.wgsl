// Spectral Vortex — Batch 58D state-ownership upgrade
// A packs phase, curl.xy, and energy; B is intentionally unwritten.

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

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
  let mx = max(max(c.r, c.g), c.b); let mn = min(min(c.r, c.g), c.b); let d = mx - mn;
  var h = 0.0;
  if (d > 0.00001) {
    if (mx == c.r) { h = (c.g - c.b) / d + select(0.0, 6.0, c.g < c.b); }
    else if (mx == c.g) { h = (c.b - c.r) / d + 2.0; }
    else { h = (c.r - c.g) / d + 4.0; }
    h /= 6.0;
  }
  return vec3<f32>(h, select(0.0, d / mx, mx > 0.0), mx);
}

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let k = abs(fract(hsv.x + vec3<f32>(0.0, 0.6666667, 0.3333333)) * 6.0 - vec3<f32>(3.0));
  return hsv.z * mix(vec3<f32>(1.0), clamp(k - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0)), hsv.y);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw; let pixel = vec2<i32>(gid.xy);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
  let uv = (vec2<f32>(pixel) + 0.5) / res; let texel = 1.0 / res; let time = u.config.x;
  let aspectVec = vec2<f32>(res.x / max(res.y, 1.0), 1.0);
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;

  // Saved mapping: twist scale, distortion step, color shift, curl amplification.
  let twistScale = u.zoom_params.x; let distortionStep = u.zoom_params.y;
  let colorShift = u.zoom_params.z; let curlAmp = u.zoom_params.w;

  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let hasSpring = arrayLength(&extraBuffer) >= 139u;
  var springPos = rawMouse; var springVel = vec2<f32>(0.0); var lastTime = time; var initialized = false;
  if (hasSpring) {
    springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]); springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    lastTime = extraBuffer[137]; initialized = extraBuffer[138] > 0.5;
  }
  if (!initialized) { springPos = rawMouse; springVel = vec2<f32>(0.0); }
  let dt = select(0.0, clamp(time - lastTime, 0.0, 0.05), initialized);
  let omega = 8.5; let decay = exp(-omega * dt); let springDelta = springPos - rawMouse;
  let temp = (springVel + omega * springDelta) * dt;
  springVel = (springVel - omega * temp) * decay; springPos = rawMouse + (springDelta + temp) * decay;
  if (hasSpring && gid.x == 0u && gid.y == 0u) {
    extraBuffer[133] = springPos.x; extraBuffer[134] = springPos.y; extraBuffer[135] = springVel.x; extraBuffer[136] = springVel.y;
    extraBuffer[137] = time; extraBuffer[138] = 1.0;
  }

  let left = textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  let right = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  let top = textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(0.0, texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  let bottom = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  let gx = dot(right - left, vec3<f32>(0.299, 0.587, 0.114));
  let gy = dot(bottom - top, vec3<f32>(0.299, 0.587, 0.114));
  var curl = vec2<f32>(gy, -gx) * mix(1.0, 20.0, curlAmp) * (1.0 + bass * 2.0);

  let pointerDelta = (uv - springPos) * aspectVec; let pointerDist = length(pointerDelta);
  let held = select(0.35, 1.0, u.zoom_config.w > 0.5);
  curl += vec2<f32>(-pointerDelta.y, pointerDelta.x) / max(pointerDist, 0.001) * exp(-pointerDist * 6.0) * held * (0.4 + mids);
  var clickEnergy = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i++) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age < 0.0 || age > 1.8) { continue; }
    let deltaR = (uv - ripple.xy) * aspectVec; let dist = length(deltaR);
    let front = exp(-pow((dist - age * 0.2) * 20.0, 2.0)) * (1.0 - age / 1.8);
    curl += vec2<f32>(-deltaR.y, deltaR.x) / max(dist, 0.001) * front * 0.9;
    clickEnergy += front;
  }

  // Exact C restores the authoritative state written to A last frame.
  let previous = textureLoad(dataTextureC, pixel, 0);
  let previousPhase = max(previous.x, 0.0);
  let previousCurl = previous.yz;
  let previousEnergy = max(previous.w, 0.0);
  let curlState = mix(previousCurl * 0.94, curl, 0.18 + mids * 0.04);
  let curlEnergy = length(curlState);
  let energy = mix(previousEnergy * 0.96, clamp(curlEnergy * 0.22 + clickEnergy * 0.4, 0.0, 1.0), 0.24);
  let phase = fract(previousPhase + (0.006 + curlEnergy * 0.025 + bass * 0.008));
  textureStore(dataTextureA, pixel, vec4<f32>(phase, curlState, energy));

  let angle = phase * TAU * (0.3 + twistScale * 2.2);
  let c = cos(angle); let s = sin(angle);
  let rotatedCurl = mat2x2<f32>(c, -s, s, c) * curlState;
  let offset = rotatedCurl * distortionStep * (0.003 + energy * 0.018);
  let distortedUv = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
  let source = textureSampleLevel(readTexture, u_sampler, distortedUv, 0.0);
  var hsv = rgb2hsv(max(source.rgb, vec3<f32>(0.0)));
  hsv.x = fract(hsv.x + phase * colorShift + time * colorShift * 0.03 + treble * 0.05);
  hsv.z *= 1.0 + energy * 1.2;
  var hdr = hsv2rgb(hsv);
  hdr += (vec3<f32>(0.5) + vec3<f32>(0.5) * cos(vec3<f32>(phase * TAU) + vec3<f32>(0.0, 2.09, 4.18))) * energy * 0.35;
  let effectEnergy = clamp(energy + length(offset) * 18.0 + clickEnergy * 0.25, 0.0, 1.0);
  let alpha = clamp(source.a + (1.0 - source.a) * effectEnergy, 0.0, 1.0);
  let display = vec4<f32>(acesToneMap(max(hdr, vec3<f32>(0.0))), alpha);
  textureStore(writeTexture, pixel, display);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
