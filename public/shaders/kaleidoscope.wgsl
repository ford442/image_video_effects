// ═══════════════════════════════════════════════════════════════════
//  Rose FBM Kaleidoscope — Steerable Mirror Bank
//  Category: distortion
//  Features: mouse-driven, held-drag, bounded-click-ripples, audio-reactive,
//            per-band-fft, rose-segments, mirror-pivot, chromatic-aberration,
//            temporal-persistence, depth-aware, upgraded-rgba,
//            semantic-alpha, aces
//  Complexity: High
//  Date: 2026-05-03
//  Upgraded: 2026-08-23 (Batch 60)
// ═══════════════════════════════════════════════════════════════════
//  FIXED IN THIS PASS — the shader never read the mouse. `zoom_config` appeared
//  only in the Uniforms struct declaration; a kaleidoscope with a fixed centre
//  and no pointer input is a screensaver, not an effect. The pointer is now the
//  mirror pivot: the segment fan rotates and re-centres around it, holding
//  tightens the aperture, and clicks fire bounded shockwaves through the fan.
//
//  Also added: dataTextureA writeback (nothing was written before, so the slot
//  was dead), exact-load temporal persistence through dataTextureC, and ACES.
//
//  TWO NEW STRUCTURES
//
//    1. Steerable mirror pivot — the mirror bank's origin and rotation follow
//       the pointer instead of being pinned to frame centre, so the kaleidoscope
//       can be aimed. The pivot is spring-damped through extraBuffer[133..134]
//       so it glides rather than snapping on every cursor jump.
//
//    2. Per-segment FFT bands — each mirror segment owns one of the eight
//       spectrum bins, which drives its own rose-petal amplitude and Gabor
//       texture gain. Segments therefore breathe independently with the music
//       rather than the whole fan scaling by one global `audioReact`.
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Segments, y=Speed, z=Zoom, w=EdgeSoftness
  ripples: array<vec4<f32>, 50>,
};

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
fn valueNoise2D(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var v = 0.0; var a = 0.5;
  var rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
  var pos = p;
  for(var i: i32 = 0; i < octaves; i = i + 1) {
    v = v + a * valueNoise2D(pos);
    pos = rot * pos * 2.0 + 100.0;
    a = a * 0.5;
  }
  return v;
}
fn superellipseMask(d: vec2<f32>, a: f32, b: f32, n: f32) -> f32 {
  let xn = pow(abs(d.x) / max(a, 0.001), n);
  let yn = pow(abs(d.y) / max(b, 0.001), n);
  return 1.0 - smoothstep(0.8, 1.0, xn + yn);
}
fn roseModulation(angle: f32, n: f32, a: f32) -> f32 {
  return a * abs(cos(n * angle * 0.5));
}
fn lissajousOffset(t: f32, A: f32, B: f32, a: f32, b: f32, delta: f32) -> vec2<f32> {
  return vec2<f32>(A * sin(a * t + delta), B * sin(b * t));
}
fn epicycloidPoint(t: f32, R: f32, r: f32) -> vec2<f32> {
  let k = (R + r) / max(r, 0.001);
  return vec2<f32>((R + r) * cos(t) - r * cos(k * t), (R + r) * sin(t) - r * sin(k * t));
}
fn hypocycloidPoint(t: f32, R: f32, r: f32) -> vec2<f32> {
  let k = (R - r) / max(r, 0.001);
  return vec2<f32>((R - r) * cos(t) + r * cos(k * t), (R - r) * sin(t) - r * sin(k * t));
}
fn gaborTexture(p: vec2<f32>, freq: f32, angle: f32) -> f32 {
  let g = exp(-dot(p, p) * 12.0);
  let ca = cos(angle);
  let sa = sin(angle);
  return g * cos(freq * (p.x * ca + p.y * sa));
}
fn hypocycloidRadius(angle: f32, time: f32, speed: f32) -> f32 {
  let t = angle + time * speed * 0.5;
  let p = hypocycloidPoint(t, 0.5, 0.1);
  return length(p) * 0.42;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dimsI = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dimsI.x) || global_id.y >= u32(dimsI.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let resolution = vec2<f32>(dimsI);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;
  let audioBass = plasmaBuffer[0].x;
  let audioMids = plasmaBuffer[0].y;
  let audioTreble = plasmaBuffer[0].z;
  let audioReact = 1.0 + audioTreble * 0.3 + audioBass * 0.2;
  let held = step(0.5, u.zoom_config.w);

  // ── Structure 1: spring-damped mirror pivot (was never read) ──────────────
  // extraBuffer[133..134] = smoothed pointer; only invocation (0,0) writes.
  let rawMouse = u.zoom_config.yz;
  if (global_id.x == 0u && global_id.y == 0u) {
    var sm = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    if (sm.x == 0.0 && sm.y == 0.0) { sm = rawMouse; }
    let k = 1.0 - exp(-8.0 * 0.016);
    sm = sm + (rawMouse - sm) * k;
    extraBuffer[133] = sm.x;
    extraBuffer[134] = sm.y;
  }
  let pivot = vec2<f32>(extraBuffer[133], extraBuffer[134]);

  // ── Bounded click shockwaves through the fan ──────────────────────────────
  var clickWave = 0.0;
  var waveGlow = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    if (age >= 0.0 && age < 2.3) {
      let r = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      let front = r - age * 0.5;
      let env = exp(-front * front * 160.0) * exp(-age * 1.5);
      clickWave += env;
      waveGlow += env * env;
    }
  }
  clickWave = min(clickWave, 1.5);
  waveGlow = min(waveGlow, 1.2);

  let segments = max(u.zoom_params.x * 16.0, 4.0);
  let speed = u.zoom_params.y * 0.5;
  let zoom = max(u.zoom_params.z, 0.1);
  let edgeSoft = max(u.zoom_params.w * 0.05, 0.0001);

  // Centered coordinates for mirror operations — origin follows the pointer,
  // blended toward frame centre so an idle cursor still gives a centred fan.
  let mirrorOrigin = mix(vec2<f32>(0.5), pivot, 0.65 + held * 0.35);
  var centered = uv - mirrorOrigin;
  let radius = length(centered);
  var angle = atan2(centered.y, centered.x);
  // Holding rotates the whole bank around the pivot.
  let pivotSpin = held * (time * 0.35) + (pivot.x - 0.5) * 3.0;

  // 1. Lissajous displacement field (breathing wobble)
  let liss = lissajousOffset(time * speed, 0.025, 0.02, 3.0, 2.0, 0.5);
  centered = centered + liss * audioReact;
  let dispRadius = length(centered);
  var dispAngle = atan2(centered.y, centered.x);

  // 2. FBM turbulent mirror distortion (organic liquid-like)
  let turb = fbm(vec2<f32>(dispRadius * 5.0, dispAngle * 3.0) + time * 0.4, 4);
  dispAngle = dispAngle + turb * 0.12 * audioReact;

  // 3. Rose curve segment boundaries (petal-shaped mirrors)
  // Structure 2: the segment this pixel falls in owns one FFT bin, so petals
  // breathe independently instead of the whole fan scaling together.
  let preSegAngle = 6.2831853 / segments;
  let preIndex = floor(select(dispAngle, dispAngle + 6.2831853, dispAngle < 0.0) / preSegAngle);
  let segBandIdx = u32(abs(preIndex)) % 8u;
  let segBand = plasmaBuffer[segBandIdx + 1u].x;

  let roseK = segments;
  let roseA = 0.25 * audioReact * (0.6 + segBand * 1.6 + clickWave * 0.5);
  let roseWarp = roseModulation(dispAngle, roseK, roseA);
  let warpedAngle = dispAngle + roseWarp * sin(dispRadius * 8.0);

  // Normalize angle to positive range for consistent mirroring
  let normAngle = select(warpedAngle, warpedAngle + 6.2831853, warpedAngle < 0.0);

  // Standard angular mirror within rose-warped segments
  let segAngle = 6.2831853 / segments;
  let segIndex = floor(normAngle / segAngle);
  let segFrac = fract(normAngle / segAngle);
  let mirrorFrac = select(segFrac, 1.0 - segFrac, abs(segIndex % 2.0) > 0.5);
  let mirrorAngle = mirrorFrac * segAngle + segIndex * segAngle + pivotSpin;

  // 4. Epicycloid inner pattern distortion (spirograph wobble)
  let epiT = time * speed + dispRadius * 12.0 + audioTreble * 2.0;
  let epi = epicycloidPoint(epiT, 0.025, 0.008) * audioReact;
  let zoomed = vec2<f32>(cos(mirrorAngle), sin(mirrorAngle)) * dispRadius / zoom + epi;

  // 5. Superellipse zoom window (squircle aperture)
  let sqN = mix(2.0, 10.0, u.zoom_params.w);
  let sqMask = superellipseMask(zoomed, 0.55, 0.55, sqN);
  let finalUV = zoomed + mirrorOrigin;

  // Edge fade for sampled texture bounds
  let fadeX = smoothstep(0.0, edgeSoft, finalUV.x) * smoothstep(1.0, 1.0 - edgeSoft, finalUV.x);
  let fadeY = smoothstep(0.0, edgeSoft, finalUV.y) * smoothstep(1.0, 1.0 - edgeSoft, finalUV.y);
  let edgeFade = fadeX * fadeY;

  // 6. Gabor anisotropic segment texture (fabric-like interiors)
  let segCenter = vec2<f32>(cos(segIndex * segAngle), sin(segIndex * segAngle)) * 0.25;
  let gabor = gaborTexture(centered - segCenter, 10.0, segIndex * segAngle * 0.5) * 0.12;
  let gaborTint = vec3<f32>(0.9, 0.85, 0.7) * gabor * audioReact * (0.5 + segBand * 2.0);

  // 7. RGB channel separation per segment index
  let segMod = f32(segIndex % 3.0);
  let shift = edgeSoft * 0.4 * segMod;
  let rUV = finalUV + vec2<f32>(shift, 0.0);
  let gUV = finalUV;
  let bUV = finalUV - vec2<f32>(shift, 0.0);
  let rSamp = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
  let gSamp = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
  let bSamp = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
  var rgb = vec3<f32>(rSamp, gSamp, bSamp) + gaborTint;

  // 8. Hypocycloid outer frame mask (star/flower aperture)
  let frameR = hypocycloidRadius(angle, time, speed);
  let frameMask = 1.0 - smoothstep(frameR - 0.03, frameR, radius);

  // Compose color with superellipse and frame masking
  rgb = rgb * edgeFade * sqMask * frameMask;

  // Edge glow intensity stored in alpha
  let segmentEdge = abs(sin(mirrorFrac * 3.14159265));
  let edgeGlow = (1.0 - edgeFade) * 1.5 + segmentEdge * 0.25 * audioTreble;
  let alpha = edgeFade * frameMask + edgeGlow * edgeSoft * 8.0;

  rgb += vec3<f32>(0.85, 0.95, 1.0) * waveGlow * (0.4 + audioMids * 0.7);

  // Temporal persistence (exact load — dataTextureC is rgba32float).
  let prev = textureLoad(dataTextureC, coord, 0);
  rgb = max(rgb, prev.rgb * (0.72 + edgeSoft * 4.0));

  rgb = acesFilm(rgb);

  let finalColor = vec4<f32>(rgb, clamp(alpha + waveGlow * 0.25, 0.0, 1.0));
  textureStore(writeTexture, coord, finalColor);
  textureStore(dataTextureA, coord, finalColor);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, finalUV, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
