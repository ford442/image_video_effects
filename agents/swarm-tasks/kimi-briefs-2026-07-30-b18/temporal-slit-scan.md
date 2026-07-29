# Swarm Brief: temporal-slit-scan

**Role:** Optimizer
**Name:** Temporal Slit Scan
**Category:** post-processing
**Description:** Classic slit-scan time-smear: each column (or row) samples a different point in the 8-frame history ring. One edge shows the current frame, the opposite edge shows 7 frames ago. Creates the flowing painterly time-smear of Radiohead's Street Spirit video on any motion.
**Current lines:** 98
**Target lines:** 148–188 (expand by +50 to +90)

## Role Instructions

You are the Optimizer. This slit-scan is clean and honest - but it's tagged mouse-driven and never uses the mouse, and clicks do nothing. Give it touch without breaking the history ring:
- Mouse scan pivot (priority 1): let the mouse position along the scan axis set WHERE the current-frame edge lives (instead of fixed at scanPos=1) - pixels on one side read progressively older history, the other side reads progressively younger... or simpler and truer to slit-scan: mouse sets the pivot column/row that shows the live frame, with age ramping away from it in both directions (tent map). Keep the axis/reverse params working on top.
- Click temporal tears: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple locally deepens the history offset near its click point (a radial 'tear' that reaches further back in the ring, decaying ~1.5s), so clicks smear time locally.
- Per-column spectral jitter: add a subtle per-scan-column offset jitter driven by FFT bins (`plasmaBuffer[(col % 8) + 1].x * mids-weighted`) so the smear shimmers with the spectrum; keep it sub-frame (max 1 extra history step) so the smear stays smooth.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: the history-ring indexing ((historyHead + HISTORY_DEPTH - t_offset) % HISTORY_DEPTH) and extraBuffer[4] historyHead read are ENGINE CONTRACTS - preserve VERBATIM. Keep binding 13 (historyTexture) declared exactly as-is. extraBuffer is READ-ONLY for this shader (engine owns [0..4]); do not write it. Respect the branchless select() style for scanPos.

## Required Output Format

- Return exactly one fenced WGSL block (` ```wgsl ` ... ` ``` `).
- No prose before or after the fence.
- Preserve the canonical 13-binding compute layout:
  - @binding(0) sampler, (1) readTexture, (2) writeTexture, (3) Uniforms, (4) readDepthTexture, (5) non_filtering_sampler, (6) writeDepthTexture, (7) dataTextureA, (8) dataTextureB, (9) dataTextureC, (10) extraBuffer (read_write), (11) comparison_sampler, (12) plasmaBuffer (read).
- Workgroup size must be `@workgroup_size(16, 16, 1)`.
- Write to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Use `textureSampleLevel(..., 0.0)` for sampler reads and `textureLoad` for storage reads.
- Do not use WGSL reserved keywords as identifiers (e.g. `target`). Do not add or renumber bindings. Binding 13 (historyTexture) is optional - only declare it if the shader already uses it.
- extraBuffer (if ever used): [0..4] reserved, [5..132] = engine FFT bins — persistent shader state goes in [133..255] ONLY.
- Engine uniform truth (verified src/renderer/UniformBuffer.ts): config = [time, rippleCount, resW, resH]; zoom_config = [time, mouseX, mouseY, mouseDown]. Guard ripple loops with `min(u32(u.config.y), 50u)`.

## JSON Parameters / Controls

```json
{
  "id": "temporal-slit-scan",
  "name": "Temporal Slit Scan",
  "url": "shaders/temporal-slit-scan.wgsl",
  "description": "Classic slit-scan time-smear: each column (or row) samples a different point in the 8-frame history ring. One edge shows the current frame, the opposite edge shows 7 frames ago. Creates the flowing painterly time-smear of Radiohead's Street Spirit video on any motion.",
  "tags": [
    "temporal",
    "slit-scan",
    "time-smear",
    "painterly",
    "classic",
    "retro",
    "smear"
  ],
  "features": [
    "temporal",
    "history-ring",
    "mouse-driven",
    "audio-reactive",
    "upgraded-rgba"
  ],
  "requiresHistoryRing": true,
  "params": [
    {
      "id": "param1",
      "name": "Scan Axis",
      "default": 0,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param2",
      "name": "Temporal Spread",
      "default": 1,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param3",
      "name": "Reverse",
      "default": 0,
      "min": 0,
      "max": 1,
      "step": 1
    },
    {
      "id": "param4",
      "name": "Original Blend",
      "default": 0,
      "min": 0,
      "max": 1,
      "step": 0.01
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Scan Axis",
      "default": 0,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Temporal Spread",
      "default": 1,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Reverse",
      "default": 0,
      "min": 0.0,
      "max": 1.0,
      "step": 1
    },
    {
      "index": 3,
      "name": "Original Blend",
      "default": 0,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    }
  ],
  "updated": true
}
```

## Current WGSL Code

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  Temporal Slit Scan
//  Category: post-processing
//  Features: mouse-driven, audio-reactive, temporal, history-ring, upgraded-rgba
//  Complexity: Low
//  Upgraded: 2026-05-23
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
//  zoom_params layout:
//    x = axis (0→horizontal scan, >0.5→vertical scan)
//    y = temporal spread (0→1 frame, 1→7 frames, default 1.0→max)
//    z = reverse direction (0→normal, >0.5→reversed L↔R)
//    w = blend with original (0→pure slit, 1→original, default 0.0)
//
//  extraBuffer layout:
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
const MAX_OFFSET: u32    = 7u;  // maximum history age to reach

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res   = vec2<f32>(u.config.z, u.config.w);
  let coord = vec2<i32>(global_id.xy);
  if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  // Parameters; bass widens the temporal spread for more smear on beats
  let useVertical  = u.zoom_params.x > 0.5;
  let spread       = clamp(u.zoom_params.y * (1.0 + bass * 0.3), 0.0, 1.0); // 0–1 → 0–7 frames
  let doReverse    = u.zoom_params.z > 0.5;
  let origBlend    = u.zoom_params.w;

  // Normalised position along the scan axis [0,1]
  var scanPos = select(uv.x, uv.y, useVertical);
  if (doReverse) { scanPos = 1.0 - scanPos; }

  // Map scan position to temporal offset: left=maxOffset(oldest), right=0(current)
  let maxOffset = u32(spread * f32(MAX_OFFSET) + 0.5);
  // (1-scanPos): scanPos=0(left) → t_offset=maxOffset(oldest); scanPos=1(right) → t_offset=0(current)
  let t_offset = u32((1.0 - scanPos) * f32(maxOffset));

  let historyHead = u32(extraBuffer[4]);
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  var scanColor: vec4<f32>;
  if (t_offset == 0u) {
    // Right edge: live current frame
    scanColor = current;
  } else {
    let layer = (historyHead + HISTORY_DEPTH - t_offset) % HISTORY_DEPTH;
    scanColor = textureSampleLevel(historyTexture, u_sampler, uv, i32(layer), 0.0);
  }

  let output = mix(scanColor, current, origBlend);
  let slitDiff = length(scanColor.rgb - current.rgb);
  let alpha = clamp(slitDiff * 3.0 + (1.0 - origBlend) * 0.5 + bass * 0.2, 0.0, 1.0);
  let finalOut = vec4<f32>(output.rgb, alpha);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, coord, finalOut);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, finalOut);
}
```
