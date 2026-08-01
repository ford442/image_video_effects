# Swarm Brief: quantum-cursor

**Role:** Visualist
**Name:** Quantum Cursor
**Category:** interactive-mouse
**Description:** Quantized reality field around the cursor with chromatic distortion and audio-reactive pulse.
**Current lines:** 107
**Target lines:** 157–197 (expand by +50 to +90)

## Role Instructions

You are the Visualist. This quantum mosaic is honest - all four sliders real - but the field snaps to the cursor and clicks never collapse the wavefunction. Give it quantum behavior:
- Spring-damper the field center (priority 1): ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the quantized zone trails the cursor; raw mouse stays the spring target.
- Click decoherence bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple spikes `chaos` locally at its click point (a decaying +0.5 chaos bump in a ~0.3 radius smoothstep falloff, ~1.2s fade), so clicks make reality flicker locally - the existing shuffle/invert machinery does the rest.
- Per-block FFT voices: modulate each block's jitter amplitude by its own bin (`plasmaBuffer[(u32(blockHash * 8.0) % 8u) + 1u].x * 0.5`), so different blocks vibrate to different frequencies. Fix the stale comments (comment-only): config.y = ripple COUNT, zoom_config.w = mouseDown.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the hash12 helper, the mosaic blockUV construction, the chaos jitter, the branchless channel shuffle/invert machinery (activeChaos/shuffle1/shuffle2/doInvert/select chain), and the mask smoothstep VERBATIM - the quantum identity is hand-tuned. All 4 sliders honestly wired - keep roles EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.

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
  "id": "quantum-cursor",
  "name": "Quantum Cursor",
  "url": "shaders/quantum-cursor.wgsl",
  "description": "Quantized reality field around the cursor with chromatic distortion and audio-reactive pulse.",
  "params": [
    {
      "id": "radius",
      "name": "Field Radius",
      "default": 0.3,
      "min": 0,
      "max": 1
    },
    {
      "id": "mosaic_size",
      "name": "Block Size",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "aberration",
      "name": "Aberration",
      "default": 0.3,
      "min": 0,
      "max": 1
    },
    {
      "id": "chaos",
      "name": "Chaos",
      "default": 0.2,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
    "mouse-driven",
    "distortion",
    "audio-reactive",
    "upgraded-rgba"
  ],
  "tags": [
    "mouse-driven",
    "interactive",
    "audio-reactive",
    "glitch",
    "distortion"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Field Radius",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Block Size",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Aberration",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Chaos",
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
//  Quantum Cursor
//  Category: interactive-mouse
//  Features: mouse-driven, distortion, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-05-23
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  var p3  = fract(vec3<f32>(p.xyx) * .1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 0.001);
  var mouse = u.zoom_config.yz;

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Params with guards and audio reactivity
  let radius = max(mix(0.05, 0.5, u.zoom_params.x) * (1.0 + bass * 0.3), 0.001);
  let mosaic_scale = mix(50.0, 5.0, clamp(u.zoom_params.y, 0.0, 1.0));
  let aberration = clamp(u.zoom_params.z, 0.0, 1.0) * 0.05;
  let chaos = clamp(u.zoom_params.w * (1.0 + bass * 0.5 + mids * 0.2), 0.0, 1.0);

  let dist_vec = (uv - mouse);
  let dist = length(dist_vec * vec2(aspect, 1.0));

  // Soft edge for the effect
  let mask = smoothstep(radius, radius * 0.8, dist);

  // Sample Original
  let colOrig = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Sample Effect
  let blocks = resolution / max(mosaic_scale, 0.1);
  let blockUV = floor(uv * blocks) / blocks + (0.5 / blocks);

  // Random jitter per block based on chaos
  let blockHash = hash12(blockUV + u.config.x * 0.01 * max(chaos, 0.001));
  let jitter = (blockHash - 0.5) * 0.1 * chaos;
  var activeBlockUV = clamp(blockUV + jitter, vec2<f32>(0.0), vec2<f32>(1.0));

  // Aberration on Block UV with clamped sample coordinates
  let rUV = clamp(activeBlockUV + vec2(aberration, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let bUV = clamp(activeBlockUV - vec2(aberration, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, activeBlockUV, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
  var colEffect = vec4<f32>(r, g, b, mask);

  // Branchless color channel shuffle and inversion based on chaos
  let activeChaos = step(0.2, chaos);
  let shuffle1 = step(0.6, blockHash);
  let shuffle2 = step(blockHash, 0.3);
  let doInvert = step(0.7, chaos) * step(0.8, blockHash);

  let shuffled1 = vec4<f32>(colEffect.g, colEffect.b, colEffect.r, mask);
  let shuffled2 = vec4<f32>(colEffect.b, colEffect.r, colEffect.g, mask);
  let anyShuffle = max(shuffle1, shuffle2);
  let chosenShuffle = select(shuffled2, shuffled1, shuffle1 > 0.5);
  let afterShuffle = mix(colEffect, chosenShuffle, activeChaos * anyShuffle);

  let inverted = vec4<f32>(1.0 - afterShuffle.rgb, mask);
  colEffect = mix(afterShuffle, inverted, activeChaos * doInvert);

  let finalRGB = mix(colOrig.rgb, colEffect.rgb, mask);
  let effectStrength = mask * (0.5 + chaos * 0.3 + treble * 0.1);
  let alpha = clamp(effectStrength + dot(finalRGB, vec3<f32>(0.299, 0.587, 0.114)) * 0.3, 0.0, 1.0);
  let finalColor = vec4<f32>(finalRGB, alpha);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
  textureStore(dataTextureA, global_id.xy, finalColor);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```
