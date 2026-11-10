// ═══════════════════════════════════════════════════════════════════
//  Spectral Vortex
//  Category: distortion
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-05, 2026-11-10
//  Ideas: 1) isophote advection of the phase/curl/energy state 2) signed spectral arms (counter-spinning hue by curl × radial) 3) depth-shelved curl gain 4) Lamb–Oseen pointer vortex (calm eye, 1/r arms) 5) luma-preserving hue spin (YIQ chroma rotation)
//  A packing: raw sim state (phase, curl.xy, energy) — Batch 58D state ownership; ACES only on writeTexture; B unwritten
//  The pointer is the raw cursor: the old extraBuffer spring never persisted (the buffer is re-zeroed every frame) and was removed.
//  Lamb–Oseen footprint (declared): core rc = 0.12 (card said 0.06–0.08; wider so it reads at default sliders), peak 0.74× HEAD's exp(−6d) peak,
//  far field 1.8× HEAD's at d = 0.2–0.3, 2.2× at 0.5, 6× at 1.0 (absolute 0.40 vs 0.22 at d = 0.25, 0.11 vs 0.05 at 0.5, 0.015 vs 0.0025 at 1.0).
//  A steeper envelope (exp(−3.5d), far field ≈1.3× HEAD) was tried and dropped: held visibility fell 10.9% → 3.5%.
//  Hue spin: same direction and turn count as HEAD's HSV H += turns (angle negated in spinChroma), but chroma-only, so mean Y stays put.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const TAU: f32 = 6.28318530718;

// Rotate the chroma plane (I,Q) of YIQ about the luma axis by `turns` full turns:
// a hue spin that keeps Y, unlike HSV hue rotation at constant V. In the I/Q plane the hues
// sit R(~20°) → B(~136°) → G(~242°), i.e. increasing angle runs R→B→G, the opposite sense to
// HSV's R→G→B, so the angle is negated below to spin the same direction HEAD's H += turns did.
fn spinChroma(c: vec3<f32>, turns: f32) -> vec3<f32> {
  let y = dot(c, vec3<f32>(0.299, 0.587, 0.114));
  let i = dot(c, vec3<f32>(0.596, -0.274, -0.322));
  let q = dot(c, vec3<f32>(0.211, -0.523, 0.312));
  let ang = -turns * TAU;
  let ca = cos(ang); let sa = sin(ang);
  let i2 = i * ca - q * sa;
  let q2 = i * sa + q * ca;
  return vec3<f32>(y + 0.956 * i2 + 0.621 * q2, y - 0.272 * i2 - 0.647 * q2, y - 1.106 * i2 + 1.703 * q2);
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

  let pointerDelta = (uv - rawMouse) * aspectVec; let pointerDist = length(pointerDelta);
  let held = select(0.35, 1.0, u.zoom_config.w > 0.5);
  // ── Idea 4: Lamb–Oseen pointer vortex (native) ──
  // HEAD's swirl was a unit tangent × exp(−6d):
  // full strength with an undefined direction at d→0 (a point sink of curl).
  // A real vortex has a calm eye: v ∝ (1 − exp(−d²/rc²))/d, zero on the axis, peak
  // at ≈1.12·rc, 1/d beyond. Normalised to peak 1 before the exp(−2.5d) envelope (peak 0.74).
  // Far field is deliberately wider than HEAD's (see header footprint): the visible gain lives there.
  let rc = 0.12;
  let lamb = (1.0 - exp(-pointerDist * pointerDist / (rc * rc))) * (1.567 * rc / max(pointerDist, 1e-4)) * exp(-pointerDist * 2.5);
  curl += vec2<f32>(-pointerDelta.y, pointerDelta.x) / max(pointerDist, 0.001) * lamb * held * (0.4 + mids);
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
  // Idea 2: signed spectral arms — the sign of curl × radial (around the pointer) picks
  // the hue-rotation direction, so neighbouring arms counter-spin.
  let radial = pointerDelta / max(pointerDist, 0.001);
  let armCross = curlState.x * radial.y - curlState.y * radial.x;
  let armDir = clamp(armCross * 6.0, -1.0, 1.0);
  let armSign = select(-1.0, 1.0, armCross >= 0.0);
  let spin = mix(armSign, armDir, 0.35);
  // ── Idea 5: luma-preserving hue spin (native) ──
  // HEAD rotated H in HSV at constant V, which swings luminance between yellow and blue.
  // The same turn count, in the same direction as HEAD's H += turns (hence the negated angle in
  // spinChroma), now rotates the chroma plane of YIQ about the luma axis, so the cycle keeps Y.
  let turns = phase * colorShift * spin + time * colorShift * 0.03 + treble * 0.05;
  var hdr = spinChroma(max(source.rgb, vec3<f32>(0.0)), turns) * (1.0 + energy * 1.2);
  hdr = max(hdr, vec3<f32>(0.0));
  hdr += (vec3<f32>(0.5) + vec3<f32>(0.5) * cos(vec3<f32>(phase * TAU * armSign) + vec3<f32>(0.0, 2.09, 4.18))) * energy * 0.35;
  let effectEnergy = clamp(energy + length(offset) * 18.0 + clickEnergy * 0.25, 0.0, 1.0);
  let alpha = clamp(source.a + (1.0 - source.a) * effectEnergy, 0.0, 1.0);
  let display = vec4<f32>(acesToneMap(max(hdr, vec3<f32>(0.0))), alpha);
  textureStore(writeTexture, pixel, display);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
