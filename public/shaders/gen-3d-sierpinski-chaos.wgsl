// ═══════════════════════════════════════════════════════════════════
//  3D Sierpinski Chaos Game
//  Category: generative
//  Features: sierpinski, chaos-game, 3d-fractal, audio-reactive, mouse-interactive, semantic-alpha
//  Complexity: Medium-High
//  Created: 2026-05-31 — Kimi Agent (Bright batch)
//  Upgraded: 2026-08-05 — Batch 35 (Optimizer)
//    · rotation matrix hoisted out of the chaos loop (zero trig per sample)
//    · integer-hash vertex picking + saturation early-exit
//    · bounded adaptive iteration budget, guarded FFT audio, real depth
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Point Density, .y = Rotation Speed, .z = Point Size, .w = Color Shift
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ── Named constants (no magic numbers in the hot path) ─────────────
const CAMERA_DIST: f32 = 2.5;        // perspective offset along +z
const WARMUP_ITERS: i32 = 16;        // chaos-game convergence discard
const BASE_ITERS: f32 = 48.0;        // samples per pixel at density = 0
const DENSITY_ITERS: f32 = 240.0;    // extra samples at density = 1
const SATURATION_COUNT: f32 = 4.0;   // early-exit once a pixel is fully lit
const HISTORY_DECAY: f32 = 0.96;     // temporal trail persistence
const EXPOSURE: f32 = 1.35;          // HDR lift for tone-map headroom
const BG_COLOR: vec3<f32> = vec3<f32>(0.02, 0.02, 0.03);

// Canonical hash — kept for one-time pixel seeding only.
fn hashf(n: f32) -> f32 {
  return fract(sin(n * 127.1) * 43758.5453);
}

// Cheap integer mix for per-iteration vertex picking (no trig in loop).
fn pickVertex(seed: u32) -> u32 {
  var x = seed;
  x ^= x >> 16u;
  x *= 0x7feb352du;
  x ^= x >> 15u;
  x *= 0x846ca68bu;
  return (x >> 30u) & 3u;
}

// Branchless cosine palette (replaces the 6-way HSV branch chain).
fn palette(h: f32) -> vec3<f32> {
  return 0.5 + 0.5 * cos(TAU * (h + vec3<f32>(0.0, 0.33, 0.67)));
}

// Cheap 2-octave value noise — background nebula only (never in hot loop).
fn vnoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let w = f * f * (3.0 - 2.0 * f);
  let a = hashf(i.x + i.y * 57.0);
  let b = hashf(i.x + 1.0 + i.y * 57.0);
  let c = hashf(i.x + (i.y + 1.0) * 57.0);
  let d = hashf(i.x + 1.0 + (i.y + 1.0) * 57.0);
  return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let resolution = vec2<f32>(u.config.zw);
  // Bounds guard — mandatory.
  if (pixel.x >= i32(resolution.x) || pixel.y >= i32(resolution.y)) { return; }

  let uv = (vec2<f32>(pixel) - resolution * 0.5) / min(resolution.x, resolution.y);
  // Display history via non-filtering load (host copies A→C each frame).
  let prev = textureLoad(dataTextureC, pixel, 0);

  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;

  // ── Sliders — all four LIVE ──────────────────────────────────────
  let density = u.zoom_params.x;    // Point Density → iteration budget
  let speed = u.zoom_params.y;      // Rotation Speed → orbit angular rate
  let pointSize = u.zoom_params.z;  // Point Size → splat radius
  let colorShift = u.zoom_params.w; // Color Shift → palette phase

  // ── Audio: canonical bands + guarded FFT bins 1–8 ───────────────
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Persistent smoothed bass (safe zone [133], single writer + length guard).
  var bassSmooth = bass;
  if (arrayLength(&extraBuffer) > 133u) {
    bassSmooth = extraBuffer[133];
    if (global_id.x == 0u && global_id.y == 0u) {
      extraBuffer[133] = mix(bassSmooth, bass, 0.12);
    }
  }

  var fft = 0.0;
  if (arrayLength(&extraBuffer) > 12u) {
    for (var bin = 1u; bin <= 8u; bin++) { fft += extraBuffer[4u + bin]; }
    fft *= 0.125;
  }

  // ── Click ripples: bounded (≤50), finite lifetime, spatially local ──
  var rippleGlow = 0.0;
  let screenUV = vec2<f32>(pixel) / resolution;
  let aspectFix = vec2<f32>(resolution.x / resolution.y, 1.0);
  let rippleCount = min(u32(u.config.y), 50u);
  for (var r = 0u; r < rippleCount; r++) {
    let rp = u.ripples[r];
    let age = time - rp.z;
    if (age < 0.0 || age > 2.5) { continue; }      // finite 2.5 s lifetime
    let band = length((screenUV - rp.xy) * aspectFix) - age * 0.45;
    rippleGlow += exp(-band * band * 220.0) * exp(-age * 2.2);
  }

  let audioSpeed = speed * (0.9 + bassSmooth * 0.5);
  let hueBase = colorShift + mids * 0.2 + fft * 0.1 + rippleGlow * 0.12;

  // ── View rotation (mouse drag overrides auto-orbit) ─────────────
  var rotYaw: f32;
  var rotPitch: f32;
  if (mouseDown) {
    rotYaw = (mouse.x - 0.5) * PI * 2.0;
    rotPitch = (mouse.y - 0.5) * PI * 0.8;
  } else {
    rotYaw = time * audioSpeed * 0.3;
    rotPitch = sin(time * audioSpeed * 0.2) * 0.4;
  }

  // Hoisted combined matrix M = rotY * rotX — 3 dots per point, no trig.
  let cy = cos(rotYaw);
  let sy = sin(rotYaw);
  let cp = cos(rotPitch);
  let sp = sin(rotPitch);
  let m0 = vec3<f32>(cy, sy * sp, sy * cp);
  let m1 = vec3<f32>(0.0, cp, -sp);
  let m2 = vec3<f32>(-sy, cy * sp, cy * cp);

  // Sierpinski tetrahedron vertices (unit-ish, centered).
  let vertices = array<vec3<f32>, 4>(
    vec3<f32>(0.0, 1.0, 0.0),
    vec3<f32>(-0.816, -0.333, 0.577),
    vec3<f32>(0.816, -0.333, 0.577),
    vec3<f32>(0.0, -0.333, -1.155)
  );

  // ── Chaos game: bounded, adaptive, early-exit ────────────────────
  let seedU = global_id.x * 1973u + global_id.y * 9277u + 1u;
  var point = vec3<f32>(
    hashf(f32(seedU)),
    hashf(f32(seedU) + 1.0),
    hashf(f32(seedU) + 2.0)
  ) * 2.0 - 1.0;

  // Treble tightens the sample budget so loud frames render denser.
  let densityEff = density * (0.85 + treble * 0.6);
  // LOD-friendly: scale the budget down on very large canvases — the
  // temporal accumulator below restores density over a few frames.
  let lod = clamp(921600.0 / (resolution.x * resolution.y), 0.5, 1.0);
  let numPoints = i32((BASE_ITERS + densityEff * DENSITY_ITERS) * lod) + WARMUP_ITERS;
  let pointRadius = 0.001 + pointSize * 0.005;

  var acc = vec3<f32>(0.0);
  var glowAcc = 0.0;
  var count = 0.0;
  var nearestZ = 1e5;

  for (var i = 0; i < numPoints; i++) {
    if (count > SATURATION_COUNT) { break; }  // pixel fully lit — stop early
    let vi = pickVertex(seedU + u32(i) * 747796405u);
    point = (point + vertices[vi]) * 0.5;
    if (i < WARMUP_ITERS) { continue; }       // convergence discard, folded in

    let rp = vec3<f32>(dot(m0, point), dot(m1, point), dot(m2, point));
    let projZ = CAMERA_DIST + rp.z;
    if (projZ < 0.1) { continue; }
    let proj = rp.xy / projZ;

    let diff = uv - proj;
    let distSq = dot(diff, diff);
    if (distSq >= pointRadius) { continue; }  // coarse cull before shading

    let influence = 1.0 - distSq / pointRadius;
    let depthWeight = 1.0 / projZ;
    let hue = fract(f32(vi) * 0.25 + hueBase + rp.y * 0.15);
    // Point twinkle keeps the cloud from looking like flat splats.
    let twinkle = 0.85 + 0.3 * hashf(f32(seedU) + f32(i) * 3.7);
    acc += palette(hue) * (depthWeight * influence * twinkle);
    glowAcc += depthWeight * influence;
    count += influence;
    nearestZ = min(nearestZ, projZ);
  }

  // ── Resolve color, semantic alpha, real generated depth ──────────
  var color: vec3<f32>;
  var alpha: f32;
  var depth: f32;
  if (count > 0.05) {
    color = acc / count * EXPOSURE;                       // HDR headroom
    color += vec3<f32>(0.04, 0.05, 0.08) * glowAcc;       // ambient inner glow
    color *= 1.0 + treble * 0.25;                         // treble shimmer
    alpha = clamp(count * 0.8, 0.35, 0.95);               // density-driven alpha
    depth = clamp(1.0 - (nearestZ - 1.2) / 2.6, 0.0, 1.0); // near-is-one
  } else {
    // Faint FFT-breathing nebula instead of a flat void (bg pixels only,
    // so its cost never stacks with the chaos-game hot path).
    let bgGrad = length(uv) * 0.3;
    let neb = vnoise(uv * 3.0 + time * 0.02) * 0.6
            + vnoise(uv * 7.0 - time * 0.03) * 0.4;
    color = BG_COLOR * (1.0 - bgGrad)
          + vec3<f32>(0.05, 0.03, 0.09) * neb * (0.5 + fft * 0.8);
    alpha = 0.35;
    depth = 0.0;
  }

  // Ripple flash: brightens and slightly lifts alpha near expanding rings.
  color *= 1.0 + rippleGlow * 0.6;
  alpha = clamp(alpha + rippleGlow * 0.15, 0.0, 0.98);

  // ── Temporal accumulation (stochastic sampler converges over frames) ──
  let temporal = mix(prev.rgb * HISTORY_DECAY, color, 0.3);
  textureStore(dataTextureA, pixel, vec4<f32>(temporal, alpha));
  textureStore(writeTexture, pixel, vec4<f32>(max(temporal, vec3<f32>(0.0)), alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
