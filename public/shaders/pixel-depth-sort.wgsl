// ═══════════════════════════════════════════════════════════════════
//  Pixel Depth Sort — Multi-Pass Architect Upgrade
//  Category: post-processing
//  Features: upgraded-rgba, mouse-driven, audio-reactive, depth-aware,
//            temporal-feedback, aces-tone-map, branchless-sort,
//            sorting-network, depth-weighted, lod-distance
//  Complexity: Medium
//  Upgraded: 2026-07-08
//  Optimizer pass: 2026-07-21 — slider-wired sort radius, mids-driven
//    radius modulation, span-seam chromatic accent, clamped temporal
//    feedback (accumulation stability), dead-code removal.
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=SortRadius, y=MidsMod, z=ChromaAccent, w=FeedbackClamp
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const MAX_SAMPLES: u32 = 9u;

// Legacy constants folded in from the previous slider wiring so the
// default look is preserved bit-for-bit (old defaults: thresh 0.5,
// angle 0.0, aberration 0.2).
const DEPTH_THRESHOLD: f32 = 0.5;
const BASE_ABERRATION: f32 = 0.2;
const SORT_RADIUS_SCALE: f32 = 40.0;
const UV_LO: vec2<f32> = vec2<f32>(0.0, 0.0);
const UV_HI: vec2<f32> = vec2<f32>(1.0, 1.0);

// ── Fast math helpers ─────────────────────────────────────────────
fn fast_atan2(y: f32, x: f32) -> f32 {
  let a = min(abs(x), abs(y)) / (max(abs(x), abs(y)) + 1e-6);
  let s = a * a;
  var r = ((-0.0464964749 * s + 0.15931422) * s - 0.327622764) * s * a + a;
  if (abs(y) > abs(x)) { r = 1.5707963 - r; }
  if (x < 0.0) { r = 3.1415927 - r; }
  if (y < 0.0) { r = -r; }
  return r;
}

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn luma(rgb: vec3<f32>) -> f32 {
  return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ── Branchless comparator for sorting network ─────────────────────
fn comp(
  i: u32,
  j: u32,
  depths: ptr<function, array<f32, 9>>,
  colors: ptr<function, array<vec4<f32>, 9>>
) {
  let di = (*depths)[i];
  let dj = (*depths)[j];
  let swap = f32(di > dj);
  let ci = (*colors)[i];
  let cj = (*colors)[j];
  (*depths)[i] = mix(di, dj, swap);
  (*depths)[j] = mix(dj, di, swap);
  (*colors)[i] = mix(ci, cj, swap);
  (*colors)[j] = mix(cj, ci, swap);
}

// ── 25-comparator optimal sorting network for 9 elements ──────────
// (Comparator sequence is load-bearing — do not reorder.)
fn sort_network(
  depths: ptr<function, array<f32, 9>>,
  colors: ptr<function, array<vec4<f32>, 9>>
) {
  comp(0u, 1u, depths, colors); comp(3u, 4u, depths, colors); comp(6u, 7u, depths, colors);
  comp(1u, 2u, depths, colors); comp(4u, 5u, depths, colors); comp(7u, 8u, depths, colors);
  comp(0u, 1u, depths, colors); comp(3u, 4u, depths, colors); comp(6u, 7u, depths, colors);
  comp(0u, 3u, depths, colors); comp(3u, 6u, depths, colors); comp(0u, 3u, depths, colors);
  comp(1u, 4u, depths, colors); comp(4u, 7u, depths, colors); comp(1u, 4u, depths, colors);
  comp(2u, 5u, depths, colors); comp(5u, 8u, depths, colors); comp(2u, 5u, depths, colors);
  comp(1u, 3u, depths, colors); comp(5u, 7u, depths, colors); comp(2u, 6u, depths, colors);
  comp(4u, 6u, depths, colors); comp(2u, 4u, depths, colors); comp(2u, 3u, depths, colors);
  comp(5u, 6u, depths, colors);
}

// ── Span-seam mask: 1.0 where centerDepth sits at either end of the
//    sorted depth span (i.e. where a sorted run begins or ends). ────
fn spanEdgeMask(centerDepth: f32, near: f32, far: f32) -> f32 {
  let spanExtent = max(far - near, 1e-5);
  let seamWidth = spanExtent * 0.25;
  let nearEdge = 1.0 - smoothstep(0.0, seamWidth, abs(centerDepth - near));
  let farEdge = 1.0 - smoothstep(0.0, seamWidth, abs(centerDepth - far));
  return max(nearEdge, farEdge);
}

// ── Main compute kernel ───────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv = vec2<f32>(pixel) / res;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;

  // ── Slider params (re-scoped 2026-07-21) ────────────────────────
  let sortRadius = clamp(u.zoom_params.x, 0.0, 1.0);        // tap spacing
  let midsMod = clamp(u.zoom_params.y, 0.0, 1.0);           // audio mids → radius
  let chromaAccent = clamp(u.zoom_params.z, 0.0, 1.0);      // seam fringe strength
  let feedbackClamp = clamp(u.zoom_params.w, 1.0, 2.0);     // temporal stability cap

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let centerDepth = textureLoad(readDepthTexture, pixel, 0).r;
  let bg = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Branchless background mask: keep sky/background pixels unchanged
  let isBg = f32(centerDepth < DEPTH_THRESHOLD || centerDepth > 0.995);
  if (isBg > 0.5) {
    textureStore(dataTextureA, pixel, bg);
    textureStore(writeTexture, pixel, vec4<f32>(bg.rgb, centerDepth));
    textureStore(writeDepthTexture, pixel, vec4<f32>(centerDepth, 0.0, 0.0, 0.0));
    return;
  }

  // Precompute sort direction and LOD factor from mouse distance
  let jitter = (hash21(uv * 1337.0 + time) - 0.5) * 0.04;
  let angleFromMouse = fast_atan2(mouse.y - 0.5, mouse.x - 0.5);
  let angle = angleFromMouse + jitter;
  let dir = vec2<f32>(cos(angle), sin(angle));
  let invRes = 1.0 / res;

  // LOD-distance falloff (unchanged): near mouse = full detail
  let mouseDist = length(uv - mouse);
  let lod = 1.0 - smoothstep(0.15, 0.55, mouseDist);
  // Sort radius: slider base × bass drive × mids modulation × LOD
  let sortLenBase = sortRadius * SORT_RADIUS_SCALE;
  let midsGain = 1.0 + mids * midsMod;
  let sortLength = sortLenBase * (1.0 + bass * 2.0) * midsGain * (0.5 + 0.5 * lod);
  let sampleCount = u32(5.0 + lod * 4.0);
  let depthSharp = 8.0 + lod * 24.0;

  // Sample taps along sort direction with depth-weighted accumulation
  var colors: array<vec4<f32>, 9>;
  var depths: array<f32, 9>;
  var weights: array<f32, 9>;
  for (var i: u32 = 0u; i < MAX_SAMPLES; i = i + 1u) {
    let sampleActive = f32(i < sampleCount);
    let offset = dir * f32(i) * sortLength * invRes;
    let sampleUV = clamp(uv + offset, UV_LO, UV_HI);
    let c = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
    let w = sampleActive / (1.0 + abs(d - centerDepth) * depthSharp);
    colors[i] = c;
    depths[i] = d;
    weights[i] = w;
  }

  // Sort active samples by depth (near to far)
  sort_network(&depths, &colors);

  // Find insertion rank of centerDepth
  var rank: u32 = 0u;
  for (var i: u32 = 0u; i < MAX_SAMPLES; i = i + 1u) {
    rank = rank + u32(centerDepth > depths[i]);
  }
  rank = clamp(rank, 0u, 8u);

  // Depth-weighted blend around the insertion rank
  var weightedColor = vec3<f32>(0.0);
  var weightTotal: f32 = 0.0;
  for (var i: u32 = 0u; i < MAX_SAMPLES; i = i + 1u) {
    let w = weights[i];
    weightedColor = weightedColor + colors[i].rgb * w;
    weightTotal = weightTotal + w;
  }
  let avgColor = weightedColor / max(weightTotal, 1e-6);
  var sortedColor = mix(colors[rank].rgb, avgColor, 0.35);

  // Branchless zero-radius fallback: with the radius slider at 0 the
  // taps collapse onto the center pixel — fall back to the raw frame
  // instead of smearing the same sample through the network.
  let hasSpan = smoothstep(0.0, 0.5, sortLength);
  sortedColor = mix(bg.rgb, sortedColor, hasSpan);

  // Directional chromatic aberration at depth boundaries
  let depthRange = abs(depths[8] - depths[0]);
  let boundaryStrength = smoothstep(0.05, 0.3, depthRange);

  // Chromatic edge accent: extra RGB split exactly on sorted-span seams
  let spanEdge = spanEdgeMask(centerDepth, depths[0], depths[8]) * boundaryStrength;
  let seamSplit = chromaAccent * spanEdge * 2.0;
  let caOffset = dir * (BASE_ABERRATION + seamSplit) * boundaryStrength * 4.0 * invRes;

  let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + caOffset, UV_LO, UV_HI), 0.0).r;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(uv - caOffset, UV_LO, UV_HI), 0.0).b;
  // Green channel: pull a half-offset sample on seams so the fringe is
  // a full three-channel split rather than an R/B-only artifact.
  let gSeam = textureSampleLevel(readTexture, u_sampler, clamp(uv + caOffset * 0.5, UV_LO, UV_HI), 0.0).g;
  let gChan = mix(sortedColor.g, gSeam, clamp(seamSplit, 0.0, 1.0));
  var color = vec3<f32>(r, gChan, b);

  // Subtle seam tint: faint magenta-cyan fringe riding the span edges,
  // shimmering lightly with treble energy.
  let seamTint = vec3<f32>(0.9, 0.4, 1.0) * (0.7 + treble * 0.3);
  let seamMix = clamp(spanEdge * chromaAccent, 0.0, 1.0) * 0.35;
  color = mix(color, color * seamTint + seamTint * 0.08, seamMix);

  // Temporal feedback for slot chaining — clamp the previous frame
  // pre-mix so a hot upstream slot cannot blow out the accumulator
  // (luma-echo-warp lesson: cap pre-tint at ~1.2 by default).
  let prev = textureLoad(dataTextureC, pixel, 0);
  let prevStable = clamp(prev.rgb, vec3<f32>(0.0), vec3<f32>(feedbackClamp));
  color = mix(prevStable, color, 0.88);

  // 1-LSB hash dither: breaks up banding in the feedback accumulator
  // on slow gradients without visibly changing the signal.
  let dither = (hash21(uv * 7919.0 + fract(time) * 17.0) - 0.5) / 255.0;
  color = color + vec3<f32>(dither);

  // ACES tone map + semantic alpha
  color = acesToneMap(color * (0.95 + mids * 0.12));
  let alpha = clamp(luma(color) * 1.2 + centerDepth * 0.5, 0.2, 0.95);

  textureStore(dataTextureA, pixel, vec4<f32>(color, centerDepth));
  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(centerDepth, 0.0, 0.0, 0.0));
}
