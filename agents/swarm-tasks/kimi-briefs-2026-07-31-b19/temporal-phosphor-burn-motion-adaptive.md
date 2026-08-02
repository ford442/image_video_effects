# Swarm Brief: temporal-phosphor-burn-motion-adaptive

**Role:** Optimizer
**Name:** Temporal Phosphor Burn (Motion Adaptive)
**Category:** post-processing
**Description:** Motion-adaptive CRT phosphor burn. Fast-moving pixels get slow decay (long bright trails); still areas clear quickly. Green/amber warm tint follows the motion glow for vivid CRT ambiance.
**Current lines:** 101
**Target lines:** 151–191 (expand by +50 to +90)

## Role Instructions

You are the Optimizer. This motion-adaptive phosphor burn is the real deal - honest decay params, proper history ring - but it's tagged 'mouse-driven' and never touches the mouse, and clicks do nothing. Give it touch without breaking the ring:
- Mouse phosphor lens (priority 1): near the cursor, locally bias the decay toward decayMax (longer trails, e.g. `decay = mix(decay, decayMax, mouseMask * 0.5)`, aspect-corrected smoothstep falloff ~0.3 radius) so moving the pointer over a region makes it burn brighter - the mouse 'charges' the phosphor. Also add the mouse distance into the motion term so cursor movement itself leaves a faint trail.
- Click burn stamps: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a decaying bright ghost at its click point into the accumulation (`burned = max(burned, stampColor * exp(-age * 2.0))`, warm-tinted, ~2s fade), so clicks brand the screen like a CRT flash.
- Per-band decay drift: let the 8 FFT bins (`plasmaBuffer[bin + 1].x`, bin = vertical screen band `u32(uv.y * 8.0)`) subtly modulate decay per band (+-0.005 around the computed decay, clamped to [decayMin, 0.999]) so the trails breathe with the spectrum; keep it subtle enough that static areas still clear.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: the history-ring indexing ((historyHead + HISTORY_DEPTH - age) % HISTORY_DEPTH), binding 13 declaration, and the extraBuffer[4] historyHead read are ENGINE CONTRACTS - preserve VERBATIM. extraBuffer is READ-ONLY for this shader (engine owns [0..4]); do not write it. Keep the max()-based burn accumulation and the warmTint math verbatim; dataTextureA stays DISPLAY color (raw).

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
  "id": "temporal-phosphor-burn-motion-adaptive",
  "name": "Temporal Phosphor Burn (Motion Adaptive)",
  "url": "shaders/temporal-phosphor-burn-motion-adaptive.wgsl",
  "description": "Motion-adaptive CRT phosphor burn. Fast-moving pixels get slow decay (long bright trails); still areas clear quickly. Green/amber warm tint follows the motion glow for vivid CRT ambiance.",
  "tags": [
    "temporal",
    "crt",
    "phosphor",
    "motion",
    "adaptive",
    "glow",
    "amber",
    "reactive"
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
      "name": "Motion Sensitivity",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param2",
      "name": "Max Decay (Fast)",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param3",
      "name": "Min Decay (Still)",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param4",
      "name": "Warm Tint",
      "default": 0.6,
      "min": 0,
      "max": 1,
      "step": 0.01
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Motion Sensitivity",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Max Decay (Fast)",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Min Decay (Still)",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Warm Tint",
      "default": 0.6,
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
//  Temporal Phosphor Burn — Motion Adaptive
//  Category: post-processing
//  Features: mouse-driven, audio-reactive, temporal, history-ring, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-23
//  Requires: binding 13 (historyTexture — HISTORY_DEPTH=8 ring buffer)
//  Created: 2026-05-23
//  By: Copilot
//
//  Like temporal-phosphor-burn but the per-pixel decay rate adapts
//  to local motion. Fast-moving regions get slow decay (0.99), so
//  they blaze bright trails. Still regions clear quickly (0.85),
//  preventing static burn-in. A green/amber tint is applied to the
//  persistence glow for CRT ambiance.
//
//  zoom_params layout:
//    x = motion sensitivity (0→gentle, 1→sharp, default 0.5)
//    y = max decay (slow end, 0→0.90, 1→0.999, default 0.5→0.99)
//    z = min decay (fast end, 0→0.70, 1→0.90, default 0.5→0.85)
//    w = warm tint strength (0→none, 1→full green/amber, default 0.5)
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
  zoom_params: vec4<f32>, // x=motionSens, y=maxDecay, z=minDecay, w=warmTint
  ripples: array<vec4<f32>, 50>,
};

const HISTORY_DEPTH: u32 = 8u;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res   = vec2<f32>(u.config.z, u.config.w);
  let coord = vec2<i32>(global_id.xy);
  if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  // Parameters; bass amplifies motion sensitivity for reactive trails
  let motionSens  = (1.0 + u.zoom_params.x * 9.0) * (1.0 + bass * 0.5);
  let decayMax    = clamp(0.90 + u.zoom_params.y * 0.099 + bass * 0.03, 0.0, 0.999);
  let decayMin    = 0.70 + u.zoom_params.z * 0.20;
  let warmStrength = u.zoom_params.w * (1.0 + mids * 0.4);

  let historyHead = u32(extraBuffer[4]);
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Compute per-pixel motion from most recent history frame
  let layerRecent = (historyHead + HISTORY_DEPTH - 1u) % HISTORY_DEPTH;
  let recent = textureSampleLevel(historyTexture, u_sampler, uv, i32(layerRecent), 0.0);
  let motion = clamp(length(current.rgb - recent.rgb) * motionSens, 0.0, 1.0);

  // Motion-adaptive decay: high motion → decayMax (slow decay → long bright trail)
  //                        no  motion → decayMin (fast decay → static areas clear quickly)
  let decay = mix(decayMin, decayMax, motion);

  // Accumulate phosphor burn
  var burned = current.rgb;
  for (var age: u32 = 1u; age <= 7u; age = age + 1u) {
    let layer   = (historyHead + HISTORY_DEPTH - age) % HISTORY_DEPTH;
    let hist    = textureSampleLevel(historyTexture, u_sampler, uv, i32(layer), 0.0);
    let decayed = hist.rgb * pow(decay, f32(age));
    burned = max(burned, decayed);
  }

  // Green/amber warm tint on the phosphor glow (applied proportional to motion)
  // Tint: boost green slightly, reduce blue → classic CRT amber-green
  let warmTint = vec3<f32>(1.0, 1.08, 0.65);
  let glowAmt  = clamp(motion * 1.5, 0.0, 1.0) * warmStrength;
  burned = mix(burned, burned * warmTint, glowAmt);

  let alpha = clamp(motion * 0.5 + current.a * 0.4 + bass * 0.15, 0.0, 1.0);
  let finalOut = vec4<f32>(burned, alpha);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, coord, finalOut);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, finalOut);
}
```
