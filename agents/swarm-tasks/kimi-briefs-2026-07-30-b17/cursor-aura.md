# Swarm Brief: cursor-aura

**Role:** Optimizer
**Name:** Cursor Aura
**Category:** interactive-mouse
**Description:** Glowing aura around cursor with customizable colors, edge detection, and audio-reactive bass pulsing.
**Current lines:** 97
**Target lines:** 147–187 (expand by +50 to +90)

## Role Instructions

You are the Optimizer. Two of this aura's four sliders are LIES - 'Edge Softness' actually mixes the effect, 'Color Hue' actually drives pulse speed while the hue is hardcoded blue. Make them honest:
- REWIRE THE MISLABELED SLIDERS (priority 1): z ('Edge Softness', default 0.5) must control the aura edge feather (map to the smoothstep width currently hardcoded 0.05, e.g. mix(0.01, 0.20, z)); w ('Color Hue', default 0.5) must hue-rotate the glow color currently hardcoded (0.0, 0.5, 1.0) - IQ cosine palette or Rodrigues hue rotation keyed on w, default 0.5 landing on the CURRENT blue. Keep ids/names/defaults EXACTLY (saved-preset contract). The old z-as-mix behavior can move to a fixed sensible constant (e.g. mixVal 0.5).
- Fix the stale uniform comments (comment-only): config.y is ripple COUNT, zoom_config.w is mouseDown, not 'Generic2'.
- Click aura rings + spectral edges: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple spawns an expanding second aura ring at its click point (decaying ~1.5s); drive the 4-tap edge glow intensity from per-bin mids (`plasmaBuffer[2..5]`) per direction so the edge shimmer is directional.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the 4-tap (left/right/top/bottom) edge-detection kernel and the pulse-radius sinusoid structure VERBATIM. The ring alpha can sum > 1 pre-clamp - existing final clamp(0,1) handles it, keep it. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.

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
  "id": "cursor-aura",
  "name": "Cursor Aura",
  "url": "shaders/cursor-aura.wgsl",
  "description": "Glowing aura around cursor with customizable colors, edge detection, and audio-reactive bass pulsing.",
  "params": [
    {
      "id": "size",
      "name": "Aura Size",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "intensity",
      "name": "Glow Intensity",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "softness",
      "name": "Edge Softness",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "hue",
      "name": "Color Hue",
      "default": 0.5,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
    "mouse-driven",
    "glow",
    "audio-reactive",
    "upgraded-rgba"
  ],
  "tags": [
    "filter",
    "image-processing",
    "interactive",
    "audio-reactive"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Aura Size",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Glow Intensity",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Edge Softness",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Color Hue",
      "default": 0.5,
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
//  Cursor Aura
//  Category: interactive-mouse
//  Features: mouse-driven, glow, audio-reactive, upgraded-rgba
//  Complexity: Low
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
  let texel = vec2<i32>(global_id.xy);
  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / max(resolution, vec2<f32>(0.001));
  let time = u.config.x;

  // Audio reactivity
  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Params
  let radius     = clamp(u.zoom_params.x * (1.0 + bass * 0.2), 0.0, 1.0) * 0.5;
  let intensity  = clamp(u.zoom_params.y * (1.0 + mids * 0.15), 0.0, 1.0);
  let mixVal     = u.zoom_params.z;
  let pulseSpeed = clamp(u.zoom_params.w * (1.0 + treble * 0.1), 0.0, 1.0) * 5.0;

  let mousePos = u.zoom_config.yz;

  // Aspect ratio correction with guard
  let aspect = resolution.x / max(resolution.y, 0.001);
  let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouseCorrected = vec2<f32>(mousePos.x * aspect, mousePos.y);

  let dist = distance(uvCorrected, mouseCorrected);

  // Pulsing radius with audio reactivity
  let currentRadius = max(radius + sin(time * pulseSpeed) * 0.02 * (1.0 + bass), 0.001);

  // Aura Mask
  let mask = 1.0 - smoothstep(currentRadius, currentRadius + 0.05, dist);

  // Base Color
  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Effect Color (Edge Detection / High Pass)
  let offset = 1.0 / max(resolution.x, 0.001);
  let left   = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(-offset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let right  = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>( offset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let top    = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, -offset), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let bottom = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0,  offset), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

  let edges = abs(left - right) + abs(top - bottom);
  let glowStrength = intensity * (1.0 + bass * 0.5);
  let effectColor = edges * 2.0 + vec4<f32>(vec3<f32>(0.0, 0.5, 1.0) * glowStrength, glowStrength);

  // Combine
  let inside = mix(baseColor, effectColor, mixVal);

  // Glowing ring at the edge
  let ring = smoothstep(currentRadius - 0.01, currentRadius, dist) * smoothstep(currentRadius + 0.01, currentRadius, dist);
  let ringStrength = ring * intensity * 2.0 * (1.0 + bass);
  let ringColor = vec4<f32>(ringStrength, ringStrength, ringStrength, ringStrength);

  let preFinal = mix(baseColor, inside, mask) + ringColor;
  let finalAlpha = clamp(preFinal.a, 0.0, 1.0);
  let finalColor = vec4<f32>(preFinal.rgb, finalAlpha);

  // Depth read and mandatory writes
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, texel, finalColor);
  textureStore(dataTextureA, global_id.xy, finalColor);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```
