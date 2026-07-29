# Swarm Brief: chronos-brush

**Role:** Algorithmist
**Name:** Chronos Brush
**Category:** interactive-mouse
**Description:** Freeze time by painting over the video feed with chromatic brush tints that cycle per click. Audio boosts brush size and opacity; depth modulates paint intensity.
**Current lines:** 94
**Target lines:** 144–184 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. Three of this brush's four sliders are LIES - the labels say Decay/Distort/Mode but the code reads hue-speed/fade/opacity. Make the labels honest:
- REWIRE THE MISLABELED SLIDERS (priority 1): y ('Freeze Decay', default 0.9) must control the history decay rate (map default 0.9 to the CURRENT look, e.g. decay = mix(0.90, 0.999, y)); z ('Time Edge Distort', default 0.5) must drive a real temporal distortion - wobble the history sample UV with a time-varying sinusoid scaled by z (0 at default-ish low end); w ('Mode (Paint/Erase)', default 0) must switch paint/erase: when w > 0.5 the brush ERASES history (decays history toward the live frame) instead of painting tinted color. Keep ids/names/defaults EXACTLY (saved-preset contract) - defaults must reproduce today's painted look.
- Fix the stale uniform comments (comment-only): config.y is ripple COUNT, zoom_config.w is mouseDown, not 'Generic2'.
- Click stamp blooms: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple stamps a soft round brush bloom at its click point into the history (same tint pipeline as the mouse brush, radius ~ brushSize * 1.5, decaying with age), so clicks paint even without dragging.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: the dataTextureC-read / dataTextureA-write history feedback contract is SACRED - history stays RAW (never tonemap/clamp the A write beyond the existing clamps), and display = history. Preserve the inline HSV->RGB math and bass_env helper VERBATIM. Erase mode must still write history every frame (no early returns).

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
  "id": "chronos-brush",
  "name": "Chronos Brush",
  "category": "interactive-mouse",
  "url": "shaders/chronos-brush.wgsl",
  "description": "Freeze time by painting over the video feed with chromatic brush tints that cycle per click. Audio boosts brush size and opacity; depth modulates paint intensity.",
  "params": [
    {
      "id": "brushSize",
      "name": "Brush Size",
      "default": 0.3,
      "min": 0,
      "max": 1
    },
    {
      "id": "decay",
      "name": "Freeze Decay",
      "default": 0.9,
      "min": 0,
      "max": 1
    },
    {
      "id": "distortion",
      "name": "Time Edge Distort",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "mode",
      "name": "Mode (Paint/Erase)",
      "default": 0,
      "min": 0,
      "max": 1,
      "labels": [
        "Freeze",
        "Unfreeze"
      ]
    }
  ],
  "features": [
    "mouse-driven",
    "temporal-persistence",
    "audio-reactive",
    "depth-aware",
    "chromatic-brush",
    "upgraded-rgba"
  ],
  "tags": [
    "filter",
    "image-processing",
    "brush",
    "temporal",
    "audio-reactive",
    "depth-aware",
    "chromatic"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Brush Size",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Freeze Decay",
      "default": 0.9,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Time Edge Distort",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Mode (Paint/Erase)",
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
//  Chronos Brush
//  Category: artistic
//  Features: mouse-driven, audio-reactive, temporal-painting, depth-aware-opacity, chromatic-brush, upgraded-rgba
//  Complexity: High
//  Chunks From: chronos-brush, bass_env, temporal-feedback
//  Created: 2024-01-01
//  Upgraded: 2026-06-28
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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let clickCount = u.config.y;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthOpacity = mix(0.7, 1.0, depth);

    let brushSize = mix(0.0, 1.0, clamp(u.zoom_params.x, 0.0, 1.0)) * bass_env(bass, mids);
    let colorShiftSpeed = clamp(u.zoom_params.y, 0.0, 1.0);
    let fadeAmount = clamp(u.zoom_params.z, 0.0, 1.0);
    let opacity = mix(0.0, 1.0, clamp(u.zoom_params.w, 0.0, 1.0)) * depthOpacity;

    let aspect = resolution.x / resolution.y;
    let aspectCorrection = vec2<f32>(aspect, 1.0);
    let diff = (uv - mousePos) * aspectCorrection;
    let dist = length(diff);

    let radius = 0.02 + brushSize * 0.15;
    let brush = 1.0 - smoothstep(radius * 0.8, radius, dist);

    let historyColor = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let liveColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Chromatic brush: cycle HSL hue per click via time
    let hue = fract(sin(clickCount * 0.5 + time * colorShiftSpeed * 0.5 + bass * 0.1) * 43758.5453);
    let sat = 0.8 + mids * 0.2;
    let val = 0.9 + treble * 0.1;

    // HSV to RGB inline
    let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
    let p = abs(fract(vec3<f32>(hue) + k) * 6.0 - vec3<f32>(3.0));
    let brushTint = clamp(p - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0));
    let tintColor = vec3<f32>(sat * val) * mix(vec3<f32>(val), brushTint, sat);

    let tintedLive = vec4<f32>(liveColor.rgb * tintColor, liveColor.a);

    let decay = 1.0 - fadeAmount * 0.05 * (1.0 - bass * 0.03);
    var newHistoryColor = historyColor * decay;

    let mixFactor = brush * opacity * (1.0 + bass * 0.3);
    newHistoryColor = mix(newHistoryColor, tintedLive, mixFactor);

    let alpha = clamp(newHistoryColor.a + brush * 0.15 + bass * 0.05, 0.0, 1.0);
    let finalColor = vec4<f32>(newHistoryColor.rgb, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```
