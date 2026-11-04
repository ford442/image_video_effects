// ═══════════════════════════════════════════════════════════════════
//  Chrono Slit Scan
//  Category: image
//  Features: temporal-persistence, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-01
//  Ideas: jaw lip; transport weave
//  A packing: linear history RGBA (ACES on writeTexture only)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const PHI: f32 = 1.61803398875;

// ── Canonical hash & fBM ──────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
  var s = 0.0;
  var a = 0.5;
  var f = 1.0;
  for (var i = 0; i < oct; i++) {
    s += a * valueNoise(p * f);
    f *= 2.0;
    a *= 0.5;
  }
  return s;
}

// ── Color / SDF helpers ───────────────────────────────────────────
fn luma(rgb: vec3<f32>) -> f32 {
  return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}

// ── Slit field helpers ────────────────────────────────────────────
fn slitPosition(i: i32, t: f32, s: f32) -> f32 {
  let offset = fract(f32(i + 1) * PHI);
  let rate = 1.0 + f32(i) * 0.3;
  return fract(t * s * rate + offset);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv = vec2<f32>(pixel) / res;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let held = f32(u.zoom_config.w > 0.5);

  // Audio features
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Tunable parameters mapped to zoom_params
  //   p1 = slitCount (2–3 slits), p2 = slitWidth
  //   p3 = slitSpeed, p4 = feather
  let slitCount = mix(2.0, 3.0, u.zoom_params.x);
  let baseWidth = (u.zoom_params.y * 0.08 + 0.002) * (1.0 + bass * 0.5);
  let slitSpeed = u.zoom_params.z * 0.6 + 0.05;
  let feather = (u.zoom_params.w * 0.5 + 0.01) * (1.0 + treble * 0.6);

  // Audio-reactive speed
  let speed = slitSpeed * (mids * 0.3 + 1.0);

  // Depth-aware scale (load depth, avoid textureSampleLevel on depth)
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let depthBoost = 1.0 + depth * 0.5;

  // ── Coarse multi-slit field ──────────────────────────────────────
  // Build the base distance field without fbm warp. Track the nearest
  // active slit index so the expensive warp can be applied to one slit
  // only and with reduced octaves when far away.
  var dist = 1.0;
  var nearestIdx: i32 = 0;
  for (var i: i32 = 0; i < 3; i = i + 1) {
    let isActive = step(f32(i) + 0.5, slitCount);
    let pos = slitPosition(i, time, speed);
    let d = abs(uv.x - pos);
    let blended = smin(dist, d, 0.15);
    let closer = step(d, dist);
    nearestIdx = select(nearestIdx, i, (closer * isActive) > 0.5);
    dist = mix(dist, blended, isActive);
  }

  // Fractal width modulation
  let widthMod = 1.0 + fbm(vec2<f32>(time, uv.y * 2.0), 3) * 0.5;
  let slitW = baseWidth * widthMod * depthBoost;

  // ── LOD warp refinement ──────────────────────────────────────────
  // Full 3-octave warp is only needed inside the influence radius of a
  // slit. Outside that, a single-octave sample (multiplied by zero)
  // keeps the branchless path cheap.
  let refineRange = slitW * 2.5 + 0.04;
  let needsRefine = f32(dist < refineRange);
  let warpOctaves = select(1, 3, needsRefine > 0.0);
  let warp = fbm(vec2<f32>(uv.y * 3.0 + f32(nearestIdx), time * 0.5), warpOctaves) * 0.05 * needsRefine;

  let nearPos = slitPosition(nearestIdx, time, speed);
  let dragBand = exp(-abs(uv.y - mouse.y) * 24.0) * held;
  let warpedPos = fract(nearPos + warp + (mouse.x - nearPos) * dragBand * 0.35);
  let dWarp = abs(uv.x - warpedPos);
  dist = mix(dist, smin(dist, dWarp, 0.15), needsRefine);

  // Fast moving slit heads and click-launched temporal scan fronts.
  let headY = 0.5 + 0.48 * sin(time * (2.8 + u.zoom_params.z * 4.0) + f32(nearestIdx) * 2.1);
  let slitHead = exp(-abs(uv.y - headY) * 70.0) * exp(-dist * 90.0);
  let crossRunner = exp(-abs(fract(uv.y * 3.0 - time * 0.65) - 0.5) * 35.0) * exp(-dist * 45.0);

  var clickWave = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (rp.z > 0.0 && age >= 0.0 && age < 1.4) {
      clickWave = max(clickWave,
        exp(-abs(distance(uv, rp.xy) - age * 0.48) * 78.0) * (1.0 - age / 1.4));
    }
  }

  // Feathered slit mask enriched by the moving heads and bounded click fronts.
  // ── Idea 1: jaw lip ──────────────────────────────────────────────
  // The metal jaws sit where the distance field meets the slit width.
  // That edge exposes a thin line the smoothstep used to fade to zero.
  let jaw = exp(-abs(dist - slitW) / max(slitW * 0.35, 0.0015));
  let mask = max(max(1.0 - smoothstep(slitW * feather, slitW, dist), jaw * 0.85),
                 max(slitHead * 0.85, max(crossRunner * 0.5, clickWave * 0.75)));

  // Spatially-varying temporal decay
  let decayNoise = fbm(uv * 4.0 + time * 0.1, 3);
  let decay = mix(1.0, 0.92 + decayNoise * 0.04, 0.5);

  // Sample temporal history once (pixel-aligned load)
  let history = textureLoad(dataTextureC, pixel, 0);

  // ── Early exit for sparse slit coverage ──────────────────────────
  // When the slit mask is negligible this pixel only needs decayed
  // history, avoiding the current-frame texture sample entirely.
  if (mask < 0.005) {
    let faded = history.rgb * decay;
    let alpha = history.a * decay;
    textureStore(writeTexture, pixel, vec4<f32>(aces(max(faded, vec3<f32>(0.0))), alpha));
    textureStore(dataTextureA, pixel, vec4<f32>(faded, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    return;
  }

  // ── Idea 2: transport weave ──────────────────────────────────────
  // The gate creeps vertically while the slit is open. Slit Speed sets
  // how far that creep goes; outside the mask this sample is never taken.
  let weave = sin(time * 1.7 + uv.x * 12.0) * slitSpeed * 0.008;
  let weavePx = clamp(pixel + vec2<i32>(0, i32(round(weave * res.y))), vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1));
  let current = textureLoad(readTexture, weavePx, 0);

  // Compose: freshly scanned regions pick up current color and intensity
  let alpha = mix(history.a * decay, saturate(luma(current.rgb) + 0.2), mask);
  var color = mix(history.rgb * decay, current.rgb, mask);
  let spectralHead = 0.5 + 0.5 * cos(TAU * (vec3<f32>(uv.y + time * 0.1)
                                         + vec3<f32>(0.0, 0.33, 0.67)));
  color += spectralHead * (slitHead * 0.22 + clickWave * 0.18) * (0.5 + treble);

  textureStore(writeTexture, pixel, vec4<f32>(aces(max(color, vec3<f32>(0.0))), alpha));
  textureStore(dataTextureA, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
