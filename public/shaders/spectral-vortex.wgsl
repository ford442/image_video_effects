// ═══════════════════════════════════════════════════════════════════
//  Spectral Vortex
//  Category: distortion
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-05
//  Ideas: 1) isophote advection of the phase/curl/energy state 2) signed spectral arms (counter-spinning hue by curl × radial) 3) depth-shelved curl gain
//  A packing: raw sim state (phase, curl.xy, energy) — Batch 58D state ownership; ACES only on writeTexture; B unwritten
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

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

// Exact bilinear read of the raw C state at a fractional pixel position
// (textureLoad ×4, no sampler on rgba32float). Phase is a wrapped [0,1) field,
// so it is interpolated as a unit vector and returned in .x as an angle/TAU.
fn loadStateBilinear(pos: vec2<f32>, res: vec2<f32>) -> vec4<f32> {
  let maxP = vec2<i32>(res) - vec2<i32>(1);
  let p0f = floor(pos - 0.5);
  let f = pos - 0.5 - p0f;
  let p0 = clamp(vec2<i32>(p0f), vec2<i32>(0), maxP);
  let p1 = clamp(vec2<i32>(p0f) + vec2<i32>(1), vec2<i32>(0), maxP);
  let s00 = textureLoad(dataTextureC, vec2<i32>(p0.x, p0.y), 0);
  let s10 = textureLoad(dataTextureC, vec2<i32>(p1.x, p0.y), 0);
  let s01 = textureLoad(dataTextureC, vec2<i32>(p0.x, p1.y), 0);
  let s11 = textureLoad(dataTextureC, vec2<i32>(p1.x, p1.y), 0);
  let w00 = (1.0 - f.x) * (1.0 - f.y); let w10 = f.x * (1.0 - f.y);
  let w01 = (1.0 - f.x) * f.y;         let w11 = f.x * f.y;
  let lin = s00 * w00 + s10 * w10 + s01 * w01 + s11 * w11;
  let ph = vec2<f32>(cos(s00.x * TAU), sin(s00.x * TAU)) * w00 + vec2<f32>(cos(s10.x * TAU), sin(s10.x * TAU)) * w10
         + vec2<f32>(cos(s01.x * TAU), sin(s01.x * TAU)) * w01 + vec2<f32>(cos(s11.x * TAU), sin(s11.x * TAU)) * w11;
  let phase = select(s00.x, fract(atan2(ph.y, ph.x) / TAU + 1.0), dot(ph, ph) > 1e-8);
  return vec4<f32>(phase, lin.yzw);
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
  // Idea 3: depth-shelved curl — the depth map is quantised into three shelves
  // with soft risers; nearer shelves (higher depth) spin harder, far ones calmer.
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let shelfQ = clamp(depth, 0.0, 1.0) * 2.999;
  let shelf = (floor(shelfQ) + smoothstep(0.8, 1.0, fract(shelfQ))) / 3.0;
  let shelfGain = mix(0.65, 1.45, shelf);
  var curl = vec2<f32>(gy, -gx) * mix(1.0, 20.0, curlAmp) * shelfGain * (1.0 + bass * 2.0);

  let pointerDelta = (uv - springPos) * aspectVec; let pointerDist = length(pointerDelta);
  let held = select(0.35, 1.0, u.zoom_config.w > 0.5);
  curl += vec2<f32>(-pointerDelta.y, pointerDelta.x) / max(pointerDist, 0.001) * exp(-pointerDist * 6.0) * held * (0.4 + mids);
  var clickEnergy = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i++) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age < 0.0 || age > 1.8) { continue; }
    let deltaR = (uv - ripple.xy) * aspectVec; let dist = length(deltaR);
    let ringD = (dist - age * 0.2) * 20.0;  // floor: was pow(negative base, 2.0) → NaN
    let front = exp(-ringD * ringD) * (1.0 - age / 1.8);
    curl += vec2<f32>(-deltaR.y, deltaR.x) / max(dist, 0.001) * front * 0.9;
    clickEnergy += front;
  }

  // Exact C restores the authoritative state written to A last frame.
  let here = textureLoad(dataTextureC, pixel, 0);
  // Idea 1: isophote advection — curl is (∂y L, −∂x L), i.e. tangent to the
  // luminance contours, so reading C upstream along last frame's curl streams
  // phase/curl/energy along isophotes instead of letting them sit per-pixel.
  var advect = here.yz * 0.6;
  let advLen = length(advect);
  if (advLen > 2.5) { advect = advect * (2.5 / advLen); }
  let previous = loadStateBilinear(vec2<f32>(pixel) + 0.5 - advect, res);
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
  // Idea 2: signed spectral arms — the sign of curl × radial (around the sprung
  // pointer) picks the hue-rotation direction, so neighbouring arms counter-spin.
  let radial = pointerDelta / max(pointerDist, 0.001);
  let armCross = curlState.x * radial.y - curlState.y * radial.x;
  let armDir = clamp(armCross * 6.0, -1.0, 1.0);
  let armSign = select(-1.0, 1.0, armCross >= 0.0);
  let spin = mix(armSign, armDir, 0.35);
  hsv.x = fract(hsv.x + phase * colorShift * spin + time * colorShift * 0.03 + treble * 0.05 + 1.0);
  hsv.z *= 1.0 + energy * 1.2;
  var hdr = hsv2rgb(hsv);
  hdr += (vec3<f32>(0.5) + vec3<f32>(0.5) * cos(vec3<f32>(phase * TAU * armSign) + vec3<f32>(0.0, 2.09, 4.18))) * energy * 0.35;
  let effectEnergy = clamp(energy + length(offset) * 18.0 + clickEnergy * 0.25, 0.0, 1.0);
  let alpha = clamp(source.a + (1.0 - source.a) * effectEnergy, 0.0, 1.0);
  let display = vec4<f32>(acesToneMap(max(hdr, vec3<f32>(0.0))), alpha);
  textureStore(writeTexture, pixel, display);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
