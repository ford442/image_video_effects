# Swarm Brief: long-exposure

**Role:** Algorithmist
**Name:** Long Exposure Light Painting
**Category:** post-processing
**Description:** Simulates an open camera shutter accumulating light over time. Bright regions of each frame persist and blend into a glowing exposure buffer stored in dataTextureC; darker regions fade slowly, leaving luminous light-painting trails. Mouse click resets the exposure. Bass brightens incoming frames for punchier accumulation; mids control bloom halo radius; treble adds sparkle to the brightest traces.
**Current lines:** 105
**Target lines:** 155–195 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. This light-painting shader's 'Glow Radius' slider is FAKE - gOff is computed from it and never used; the bloom is a fixed 3x3 +-1-texel blur no matter what. And the description promises 'mouse click resets the exposure' but the reset is a global fade that ignores WHERE you click. Make it honest:
- REAL GLOW RADIUS (priority 1): scale the bloom taps by gOff - sample the 4 neighbors at `coord +- vec2<i32>(i32(glowR), 0)` / `(0, i32(glowR))` (clamped as today, glowR already derived from the slider, clamp i32(glowR) to [1, 64]) instead of +-1. Default 0.3 maps glowR to ~0.0024*res.x (~5px at 2048) - the blur genuinely widens with the slider. Delete the dead gOff (or use it - no unused vars).
- POSITIONAL CLICK RESET: the current reset is mouseDown * 0.15 globally. Make it a brush: while mouseDown, the resetMix is full strength near the cursor (aspect-corrected smoothstep ~0.25 radius) and 0 elsewhere, so holding the button ERASES TRAILS WHERE YOU DRAG (light-painting eraser) - the global gentle reset can stay at 10% strength as a base. Loop ripples[] too (guard `min(u32(u.config.y), 50u)`): each live ripple stamps a bright exposure flash at its click point (adds a decaying white-warm blob into `accumulated`, ~1.5s fade), so single clicks paint light.
- Per-band decay drift: modulate decayRate per vertical band by FFT bins (`plasmaBuffer[u32(uv.y * 8.0) + 1u].x * 0.002`) so trails linger differently across the spectrum; clamp final decay to [0.95, 0.999]. Fix the stale header comment ('Category: temporal' -> post-processing, comment-only).
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: the accumulation feedback contract is SACRED - dataTextureA stores RAW HDR accumulated color (clamped 1.5) and dataTextureC is textureLoad'd as prev accumulation; never tonemap the A write, keep the Reinhard only on the display path. Preserve the threshold/contribution/decay math, the luminance helper, and the clamp structure VERBATIM. All 4 sliders honestly wired - keep roles EXACTLY. extraBuffer (if used) in [133..255] ONLY.

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
  "id": "long-exposure",
  "name": "Long Exposure Light Painting",
  "url": "shaders/long-exposure.wgsl",
  "description": "Simulates an open camera shutter accumulating light over time. Bright regions of each frame persist and blend into a glowing exposure buffer stored in dataTextureC; darker regions fade slowly, leaving luminous light-painting trails. Mouse click resets the exposure. Bass brightens incoming frames for punchier accumulation; mids control bloom halo radius; treble adds sparkle to the brightest traces.",
  "tags": [
    "long-exposure",
    "light-painting",
    "temporal",
    "accumulation",
    "glow",
    "audio-reactive",
    "mouse-driven"
  ],
  "features": [
    "mouse-driven",
    "audio-reactive",
    "temporal",
    "upgraded-rgba"
  ],
  "params": [
    {
      "id": "accumSpeed",
      "name": "Accumulation Speed",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x"
    },
    {
      "id": "decayRate",
      "name": "Decay Rate",
      "default": 0.6,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y"
    },
    {
      "id": "glowRadius",
      "name": "Glow Radius",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z"
    },
    {
      "id": "threshold",
      "name": "Brightness Threshold",
      "default": 0.2,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w"
    }
  ],
  "coordinate": 890,
  "updatedParams": [
    {
      "index": 0,
      "name": "Accumulation Speed",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Decay Rate",
      "default": 0.6,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Glow Radius",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Brightness Threshold",
      "default": 0.2,
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
//  Long Exposure Light Painting
//  Category: temporal
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba
//  Complexity: Medium
//  Description: Simulates an open camera shutter accumulating light over
//    time. Bright regions of each frame persist and blend into a glowing
//    exposure buffer; darker regions fade slowly, leaving luminous trails.
//    Mouse click resets the exposure. Bass brightens incoming frames for
//    punchier accumulation; mids control the glow bloom radius; treble
//    adds fine sparkle to the brightest traces.
// ═══════════════════════════════════════════════════════════════════
//  zoom_params: x=accumulation_speed, y=decay_rate, z=glow_radius, w=threshold

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
  config:      vec4<f32>,  // x=time, y=rippleCount, z=resX, w=resY
  zoom_config: vec4<f32>,  // x=time, y=mouseX, z=mouseY, w=mouseDown
  zoom_params: vec4<f32>,  // x=accum_speed, y=decay, z=glow_r, w=threshold
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530718;

fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res   = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
    let coord = vec2<i32>(gid.xy);
    let uv    = vec2<f32>(gid.xy) / res;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Current camera frame
    let current  = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let curRGB   = current.rgb * (1.0 + bass * 0.4);  // bass brightens incoming

    // Accumulated exposure from previous frame (stored in dataTextureC)
    let prevAccum = textureLoad(dataTextureC, coord, 0);
    let prevRGB   = prevAccum.rgb;

    // Threshold: only pixels brighter than threshold contribute
    let threshold  = 0.05 + u.zoom_params.w * 0.35;
    let luma       = luminance(curRGB);
    let aboveThresh = clamp((luma - threshold) / max(1.0 - threshold, 0.001), 0.0, 1.0);

    // Contribution: bright pixels accumulate; dim ones don't add
    let accumSpeed = 0.04 + u.zoom_params.x * 0.20;
    let contribution = curRGB * aboveThresh * accumSpeed * (1.0 + treble * 0.25);

    // Decay: accumulated buffer slowly fades
    let decayRate = 0.97 + u.zoom_params.y * 0.029;  // 0.97–0.999
    let decayed   = prevRGB * clamp(decayRate, 0.0, 0.999);

    // Mouse click resets the buffer (mouseDown drives to zero)
    let mouseDown  = u.zoom_config.w;
    let resetMix   = clamp(mouseDown * 0.15, 0.0, 1.0);  // gradual reset
    let afterReset = mix(decayed, vec3<f32>(0.0), resetMix);

    // Accumulate new contribution; clamp to avoid runaway brightness
    var accumulated = clamp(afterReset + contribution, vec3<f32>(0.0), vec3<f32>(1.5));

    // Glow bloom: simple 3x3 blur of accumulated buffer contributes a halo
    let glowR = max(0.002, u.zoom_params.z * 0.008) * res.x;
    let gOff  = glowR / res;
    var glow  = accumulated;
    glow += textureLoad(dataTextureC, clamp(coord + vec2<i32>(1, 0), vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1)), 0).rgb;
    glow += textureLoad(dataTextureC, clamp(coord + vec2<i32>(-1, 0), vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1)), 0).rgb;
    glow += textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, 1), vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1)), 0).rgb;
    glow += textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, -1), vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1)), 0).rgb;
    let glowAmt  = (0.1 + mids * 0.3) * u.zoom_params.z;
    let glowBlend = glow * (1.0 / 5.0) * glowAmt;
    accumulated   = clamp(accumulated + glowBlend, vec3<f32>(0.0), vec3<f32>(1.5));

    // Final output: tone-map accumulation back to [0,1] (Reinhard)
    let finalRGB = accumulated / (accumulated + vec3<f32>(1.0));

    // Alpha: bright trails are opaque; fresh dark areas stay transparent
    let accumLuma = luminance(finalRGB);
    let alpha     = clamp(accumLuma * 1.4 + bass * 0.08, 0.0, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, coord, vec4<f32>(finalRGB, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(accumulated, 1.0));  // store raw HDR for next frame
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```
