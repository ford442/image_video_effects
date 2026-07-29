// ═══════════════════════════════════════════════════════════════════
//  Temporal Slit Scan
//  Category: post-processing
//  Features: mouse-driven, audio-reactive, temporal, history-ring, upgraded-rgba
//  Complexity: Low
//  Upgraded: 2026-07-30 (Batch 18 — Optimizer)
//  Requires: binding 13 (historyTexture — HISTORY_DEPTH=8 ring buffer)
//  Created: 2026-05-23
//  By: Copilot
//
//  Classic slit-scan time-smear (Radiohead "Street Spirit" style).
//  Each column (or row) samples a different point in the history ring:
//  one edge = current frame; opposite edge = 7 frames ago.
//  This stretches the temporal axis across the spatial axis, creating
//  a flowing painterly smear on any moving content.
//
//  Batch 18 upgrades (Optimizer):
//   1. MOUSE SCAN PIVOT — the mouse position along the scan axis becomes
//      the "live edge": that column/row shows the current frame and age
//      ramps away from it in BOTH directions (tent map). With no mouse
//      input the classic fixed edge ramp is used (blend, branchless).
//   2. CLICK TEMPORAL TEARS — each live ripple tears time locally:
//      pixels near the click reach deeper into the history ring, with a
//      radial falloff decaying over ~1.5 s. Clicks smear time on demand.
//   3. PER-COLUMN SPECTRAL JITTER — each scan column jitters its history
//      offset by up to one extra frame, driven by FFT bins
//      (plasmaBuffer[(col % 8) + 1].x weighted by mids), so the smear
//      shimmers with the spectrum while staying smooth (sub-frame cap).
//
//  zoom_params layout:
//    x = axis (0→horizontal scan, >0.5→vertical scan)
//    y = temporal spread (0→1 frame, 1→7 frames, default 1.0→max)
//    z = reverse direction (0→normal, >0.5→reversed L↔R)
//    w = blend with original (0→pure slit, 1→original, default 0.0)
//
//  extraBuffer layout (READ-ONLY here; engine owns [0..4]):
//    [0]=bass  [1]=mid  [2]=treble  [3]=reserved  [4]=historyHead
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
@group(0) @binding(13) var historyTexture: texture_2d_array<f32>;

struct Uniforms {
  config: vec4<f32>,      // x=time, y=rippleCount, z=resX, w=resY
  zoom_config: vec4<f32>, // x=time, y=mouseX, z=mouseY, w=mouseDown
  zoom_params: vec4<f32>, // x=axis, y=spread, z=reverse, w=origBlend
  ripples: array<vec4<f32>, 50>,
};

const HISTORY_DEPTH: u32 = 8u;
const MAX_OFFSET: u32    = 7u;   // maximum history age to reach
const TEAR_FRAMES: f32   = 3.0;  // extra history depth a click tear can reach
const TEAR_RADIUS: f32   = 0.35; // uv-space radius of a click tear
const TEAR_DECAY: f32    = 1.5;  // seconds a tear stays alive

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res   = vec2<f32>(u.config.z, u.config.w);
  let coord = vec2<i32>(global_id.xy);
  if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  // ── Parameters ───────────────────────────────────────────────────
  // bass widens the temporal spread for more smear on beats
  let useVertical = u.zoom_params.x > 0.5;
  let spread      = clamp(u.zoom_params.y * (1.0 + bass * 0.3), 0.0, 1.0); // 0–1 → 0–7 frames
  let doReverse   = u.zoom_params.z > 0.5;
  let origBlend   = u.zoom_params.w;

  // ── Scan position (branchless select style) ──────────────────────
  var scanPos = select(uv.x, uv.y, useVertical);
  scanPos = select(scanPos, 1.0 - scanPos, doReverse);

  // ── 1. Mouse scan pivot (tent map) ───────────────────────────────
  // The mouse position along the scan axis selects the column/row that
  // shows the LIVE frame; history age ramps away from it both ways.
  let mouseUV   = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let mouseDown = u.zoom_config.w > 0.5;
  // Treat (0,0)+not-down as "no mouse yet": fall back to classic edge ramp
  let hasMouse  = mouseDown || (mouseUV.x + mouseUV.y) > 0.002;
  var pivot = select(mouseUV.x, mouseUV.y, useVertical);
  pivot = select(pivot, 1.0 - pivot, doReverse);

  // Classic ramp: age = 1 at scanPos=0 (oldest), 0 at scanPos=1 (live)
  let rampAge = 1.0 - scanPos;
  // Tent map: age = 0 at the pivot, rising to 1 at the farthest edge
  let tentAge = clamp(abs(scanPos - pivot) * 2.0, 0.0, 1.0);
  let age01   = select(rampAge, tentAge, hasMouse);

  let maxOffset = u32(spread * f32(MAX_OFFSET) + 0.5);
  var offsetF   = age01 * f32(maxOffset);

  // ── 2. Click temporal tears ──────────────────────────────────────
  // Each live ripple locally deepens the history offset near its click
  // point: a radial tear that reaches further back in the ring and
  // decays over ~TEAR_DECAY seconds. Clicks smear time locally.
  var tear = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp     = u.ripples[i];
    let rDist  = distance(uv, rp.xy);
    let rAge   = u.config.x - rp.z;
    if (rAge >= 0.0 && rAge < TEAR_DECAY) {
      let radial = smoothstep(TEAR_RADIUS, 0.0, rDist);
      let decay  = 1.0 - rAge / TEAR_DECAY;
      tear = max(tear, radial * decay * decay); // ease-out decay
    }
  }
  offsetF = offsetF + tear * TEAR_FRAMES;

  // ── 3. Per-column spectral jitter ────────────────────────────────
  // Each scan column jitters its history offset by up to ONE extra
  // frame, driven by its FFT bin weighted by mids. Sub-frame cap keeps
  // the smear smooth while the spectrum makes it shimmer.
  let scanCol  = select(global_id.x, global_id.y, useVertical);
  let binIdx   = (scanCol % 8u) + 1u; // engine FFT bins live in plasmaBuffer[1..]
  let spectral = plasmaBuffer[binIdx].x * mids;
  offsetF = offsetF + clamp(spectral, 0.0, 1.0);

  // ── Resolve final history offset ─────────────────────────────────
  let t_offset = u32(clamp(offsetF, 0.0, f32(MAX_OFFSET)) + 0.5);

  let historyHead = u32(extraBuffer[4]);
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  var scanColor: vec4<f32>;
  if (t_offset == 0u) {
    // Live column: current frame (pivot / live edge / untouched area)
    scanColor = current;
  } else {
    let layer = (historyHead + HISTORY_DEPTH - t_offset) % HISTORY_DEPTH;
    scanColor = textureSampleLevel(historyTexture, u_sampler, uv, i32(layer), 0.0);
  }

  let output = mix(scanColor, current, origBlend);
  let slitDiff = length(scanColor.rgb - current.rgb);
  // Tears flash slightly in alpha so a fresh click reads as a time-rift
  let alpha = clamp(slitDiff * 3.0 + (1.0 - origBlend) * 0.5 + bass * 0.2 + tear * 0.15, 0.0, 1.0);
  let finalOut = vec4<f32>(output.rgb, alpha);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, coord, finalOut);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, finalOut);
}
