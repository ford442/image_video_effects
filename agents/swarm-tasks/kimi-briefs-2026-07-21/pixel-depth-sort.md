# Swarm Brief: pixel-depth-sort

**Role:** Optimizer
**Name:** Pixel Depth Sort
**Category:** post-processing
**Description:** Directional pixel sorting by depth with a 25-comparator sorting network, mouse-following sort angle, depth-weighted color selection, distance-based LOD, chromatic aberration at boundaries, bass-driven sort length, depth-layered alpha, temporal feedback, and ACES tone mapping.
**Current lines:** 197
**Target lines:** 247–287 (expand by +50 to +90)

## Role Instructions

You are the Optimizer. Focus on performance, structure, and polish without disturbing the core algorithm:
- Depth-weighted sort radius is already present — wire it to a param and add audio mids (plasmaBuffer[0].y) modulation on top.
- Temporal smear polish: clamp feedback writes (same luma-echo-warp lesson — clamp pre-tint at ~1.2) so the accumulation buffer stays stable.
- Chromatic edge accent on sort boundaries: subtle RGB fringing where sorted spans begin/end.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w, replacing the 4 most important hardcoded constants. Add them to the JSON updatedParams with index 0-3, sensible name/default/min/max/step.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: Keep the sorting network and the LOD-distance logic intact — comparator sequence and the distance-based detail falloff must not change.

## Required Output Format

- Return exactly one fenced WGSL block (` ```wgsl ` ... ` ``` `).
- No prose before or after the fence.
- Preserve the canonical 13-binding compute layout:
  - @binding(0) sampler, (1) readTexture, (2) writeTexture, (3) Uniforms, (4) readDepthTexture, (5) non_filtering_sampler, (6) writeDepthTexture, (7) dataTextureA, (8) dataTextureB, (9) dataTextureC, (10) extraBuffer (read_write), (11) comparison_sampler, (12) plasmaBuffer (read).
- Workgroup size must be `@workgroup_size(16, 16, 1)`.
- Write to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Use `textureSampleLevel(..., 0.0)` for sampler reads and `textureLoad` for storage reads.
- Do not use WGSL reserved keywords as identifiers (e.g. `target`). Do not add or renumber bindings. Binding 13 (historyTexture) is optional — only declare it if the shader already uses it.

## JSON Parameters / Controls

```json
{
  "id": "pixel-depth-sort",
  "name": "Pixel Depth Sort",
  "url": "shaders/pixel-depth-sort.wgsl",
  "description": "Directional pixel sorting by depth with a 25-comparator sorting network, mouse-following sort angle, depth-weighted color selection, distance-based LOD, chromatic aberration at boundaries, bass-driven sort length, depth-layered alpha, temporal feedback, and ACES tone mapping.",
  "features": [
    "upgraded-rgba",
    "mouse-driven",
    "audio-reactive",
    "depth-aware",
    "temporal-feedback",
    "aces-tone-map",
    "branchless-sort",
    "sorting-network",
    "depth-weighted",
    "lod-distance"
  ],
  "tags": [
    "filter",
    "depth-aware",
    "pixel-sort",
    "chromatic-aberration",
    "audio-reactive",
    "optimized",
    "sorting-network",
    "lod"
  ],
  "params": [
    {
      "id": "param1",
      "name": "Depth Threshold",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param2",
      "name": "Sort Length",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param3",
      "name": "Sort Angle",
      "default": 0,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param4",
      "name": "Aberration",
      "default": 0.2,
      "min": 0,
      "max": 1,
      "step": 0.01
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Sort Radius",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Mids Modulation",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Chromatic Accent",
      "default": 0.2,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Feedback Clamp",
      "default": 1.2,
      "min": 1.0,
      "max": 2.0,
      "step": 0.05
    }
  ],
  "updated": true
}
```

## Current WGSL Code

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  Pixel Depth Sort — Multi-Pass Architect Upgrade
//  Category: post-processing
//  Features: upgraded-rgba, mouse-driven, audio-reactive, depth-aware,
//            temporal-feedback, aces-tone-map, branchless-sort,
//            sorting-network, depth-weighted, lod-distance
//  Complexity: Medium
//  Upgraded: 2026-07-08
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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const MAX_SAMPLES: u32 = 9u;

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

// ── Main compute kernel ───────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv = vec2<f32>(pixel) / res;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;

  let depthThresh = u.zoom_params.x;
  let sortLenBase = u.zoom_params.y * 40.0;
  let sortAngle = u.zoom_params.z * TAU;
  let aberration = u.zoom_params.w;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let centerDepth = textureLoad(readDepthTexture, pixel, 0).r;
  let bg = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Branchless background mask: keep sky/background pixels unchanged
  let isBg = f32(centerDepth < depthThresh || centerDepth > 0.995);
  if (isBg > 0.5) {
    textureStore(dataTextureA, pixel, bg);
    textureStore(writeTexture, pixel, vec4<f32>(bg.rgb, centerDepth));
    textureStore(writeDepthTexture, pixel, vec4<f32>(centerDepth, 0.0, 0.0, 0.0));
    return;
  }

  // Precompute sort direction and LOD factor from mouse distance
  let jitter = (hash21(uv * 1337.0 + time) - 0.5) * 0.04;
  let angleFromMouse = fast_atan2(mouse.y - 0.5, mouse.x - 0.5);
  let angle = angleFromMouse + sortAngle + jitter;
  let dir = vec2<f32>(cos(angle), sin(angle));
  let invRes = 1.0 / res;

  let mouseDist = length(uv - mouse);
  let lod = 1.0 - smoothstep(0.15, 0.55, mouseDist);
  let sortLength = sortLenBase * (1.0 + bass * 2.0) * (0.5 + 0.5 * lod);
  let sampleCount = u32(5.0 + lod * 4.0);
  let depthSharp = 8.0 + lod * 24.0;

  // Sample taps along sort direction with depth-weighted accumulation
  var colors: array<vec4<f32>, 9>;
  var depths: array<f32, 9>;
  var weights: array<f32, 9>;
  var wsum: f32 = 0.0;
  for (var i: u32 = 0u; i < MAX_SAMPLES; i = i + 1u) {
    let sampleActive = f32(i < sampleCount);
    let offset = dir * f32(i) * sortLength * invRes;
    let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
    let c = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
    let w = sampleActive / (1.0 + abs(d - centerDepth) * depthSharp);
    colors[i] = c;
    depths[i] = d;
    weights[i] = w;
    wsum = wsum + w;
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
  let sortedColor = mix(colors[rank].rgb, avgColor, 0.35);

  // Directional chromatic aberration at depth boundaries
  let depthRange = abs(depths[8] - depths[0]);
  let boundaryStrength = smoothstep(0.05, 0.3, depthRange);
  let caOffset = dir * aberration * boundaryStrength * 4.0 * invRes;

  let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + caOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(uv - caOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  var color = vec3<f32>(r, sortedColor.g, b);

  // Temporal feedback for slot chaining
  let prev = textureLoad(dataTextureC, pixel, 0);
  color = mix(prev.rgb, color, 0.88);

  // ACES tone map + semantic alpha
  color = acesToneMap(color * (0.95 + mids * 0.12));
  let alpha = clamp(luma(color) * 1.2 + centerDepth * 0.5, 0.2, 0.95);

  textureStore(dataTextureA, pixel, vec4<f32>(color, centerDepth));
  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(centerDepth, 0.0, 0.0, 0.0));
}
```
