# Swarm Brief: cyber-magnifier

**Role:** Algorithmist
**Name:** Cyber Magnifier
**Category:** interactive-mouse
**Description:** High-tech magnifying lens with chromatic aberration and HUD overlay.
**Current lines:** 93
**Target lines:** 143–183 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. This lens HUD can blow out its highlights when the grid glow stacks - tame the HDR, then give the lens glide and click flares:
- CLAMP THE ADDITIVE HUD GLOW (priority 1): `hudGlow` (lineMask+ringMask+sweep, up to ~0.5 * gridOpacity) is ADDED to the mixed lens color, then the border mix can push cyan to ~1.0 again - with gridOpacity 1.0 and hot bass this clips ugly. Add a hue-preserving clamp (scale rgb toward max 1.2 preserving ratios) BEFORE the border mix, keeping the border/vignette steps after it.
- Spring-damper the lens: ease the mouse lens center with a critically-damped spring (extraBuffer[133..134]) so the magnifier glides; the raw mouse remains the spring target each frame.
- Click lens flares: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds an expanding cyan flare ring around the lens border (radius grows with ripple age, alpha decays over ~1.5s) plus a brief +25% magnification pulse while young.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the 3-tap r/g/b chromatic-aberration sampling pattern and the aspect-corrected distance math VERBATIM. dataTextureA stores (inLens, border, sweep, alpha) mask data - keep that packing, it is not display color. extraBuffer in [133..255] ONLY.

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
  "id": "cyber-magnifier",
  "name": "Cyber Magnifier",
  "category": "interactive-mouse",
  "url": "shaders/cyber-magnifier.wgsl",
  "description": "High-tech magnifying lens with chromatic aberration and HUD overlay.",
  "features": [
    "mouse-driven",
    "audio-reactive",
    "upgraded-rgba"
  ],
  "params": [
    {
      "id": "magnification",
      "name": "Magnification",
      "type": "float",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "lens_size",
      "name": "Lens Size",
      "type": "float",
      "default": 0.4,
      "min": 0,
      "max": 1
    },
    {
      "id": "aberration",
      "name": "Aberration",
      "type": "float",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "grid_opacity",
      "name": "Grid Opacity",
      "type": "float",
      "default": 0.3,
      "min": 0,
      "max": 1
    }
  ],
  "tags": [
    "mouse-driven",
    "interactive",
    "magnifier",
    "cyber",
    "hud"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Magnification",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Lens Size",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Aberration",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Grid Opacity",
      "default": 0.3,
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
//  Cyber Magnifier
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: cyber-magnifier
//  Upgraded: 2026-05-30
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let magnification = mix(1.0, 4.0, u.zoom_params.x);
    let radius = mix(0.1, 0.45, u.zoom_params.y);
    let aberrationStrength = u.zoom_params.z * 0.05;
    let gridOpacity = u.zoom_params.w;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    let distVec = uv - mouse;
    let distVecAspect = distVec * vec2<f32>(aspect, 1.0);
    let dist = length(distVecAspect);
    let edgeWidth = 0.005;
    let inLens = 1.0 - smoothstep(radius, radius + edgeWidth, dist);
    let uvZoomed = clamp((uv - mouse) / magnification + mouse, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
    let safeDir = distVecAspect / max(dist, 0.0001);
    let aberrationOffset = vec2<f32>(safeDir.x / aspect, safeDir.y) *
        aberrationStrength * (dist / max(radius, 0.001)) * (1.0 + treble * 0.4);

    let rUV = clamp(uvZoomed - aberrationOffset, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
    let gUV = uvZoomed;
    let bUV = clamp(uvZoomed + aberrationOffset, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
    let lensColor = vec4<f32>(
        textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r,
        textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g,
        textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b,
        1.0
    );
    let bgColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    var finalColor = mix(bgColor, lensColor, inLens);

    let gridUV = distVecAspect * (18.0 + mids * 18.0);
    let gridLines = abs(fract(gridUV - 0.5) - 0.5);
    let lineMask = smoothstep(0.48, 0.43, min(gridLines.x, gridLines.y));
    let ringPhase = abs(fract(length(gridUV) - u.config.x * (0.8 + bass * 2.0)) - 0.5);
    let ringMask = smoothstep(0.18, 0.04, ringPhase);
    let scanAngle = atan2(distVecAspect.y, distVecAspect.x);
    let sweep = smoothstep(0.82, 0.99, cos(scanAngle - u.config.x * (1.6 + treble * 3.0)));
    let hudGlow = vec4<f32>(0.0, 1.0, 1.0, 1.0) * (lineMask * 0.18 + ringMask * 0.12 + sweep * 0.2) * gridOpacity * inLens;
    finalColor = finalColor + hudGlow;

    let border = smoothstep(edgeWidth, 0.0, abs(dist - radius));
    finalColor = mix(finalColor, vec4<f32>(0.25, 0.9, 1.0, 1.0), border * (0.8 + bass * 0.2));
    let vignette = smoothstep(radius, radius + 0.2, dist);
    finalColor = mix(finalColor, finalColor * (0.65 - mids * 0.08), vignette * 0.55);

    let alpha = clamp(bgColor.a * 0.28 + inLens * 0.28 + border * 0.28 + sweep * 0.12 + bass * 0.05, 0.08, 1.0);
    let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, gUV, 0.0).r + inLens * 0.04, 0.0, 1.0);
    let outPixel = vec4<f32>(finalColor.rgb, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), outPixel);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(inLens, border, sweep, alpha));
}
```
