# Swarm Brief: ascii-glyph

**Role:** Interactivist
**Name:** ASCII Glyphs
**Category:** geometric
**Description:** SDF glyph morph with bass character swap and depth luminance map. Pixels are quantized into glyph cells; depth controls brightness tiering. Bass swaps glyph patterns on beats, treble adds chromatic highlights to dense characters.
**Current lines:** 101
**Target lines:** 151–191 (expand by +50 to +90)

## Role Instructions

You are the Interactivist. This glyph field advertises 'mouse-driven' in its features but NEVER READS THE MOUSE - zoom_config is completely unused. Wire the touch it's already promising:
- WIRE THE MOUSE (priority 1): add an aspect-corrected mouse lens - near the cursor, locally shrink glyphSize (denser, finer glyphs, e.g. `glyphSize /= 1.0 + mouseMask * 1.5` with smoothstep falloff ~0.3 radius) and lift charDensity so the image resolves into finer type under the pointer. Spring-damper the lens center (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so it glides.
- Click glyph scrambles: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple injects a decaying hash-scramble ring at its click point (add `rippleAge * rippleBand` into the glyphPattern hash seed so cells inside the band flip characters chaotically, ~1.2s fade), so clicks scatter the type.
- Fix the stale comments (comment-only): config.y is ripple COUNT (not 'ClickCount'), zoom_config.w is mouseDown (not 'Generic2'), and the header 'Category: stylize' is stale (JSON lives in geometric).
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the hash12/bass_env helpers, the depth-luminance tiering (`depthLuma`), the bass beat-swap (`beatSwap`), and the cross/dot SDF glyph shape select VERBATIM - the typographic identity is hand-tuned. All 4 sliders are honestly wired - keep their roles EXACTLY (saved-preset contract). dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.

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
  "id": "ascii-glyph",
  "name": "ASCII Glyphs",
  "url": "shaders/ascii-glyph.wgsl",
  "description": "SDF glyph morph with bass character swap and depth luminance map. Pixels are quantized into glyph cells; depth controls brightness tiering. Bass swaps glyph patterns on beats, treble adds chromatic highlights to dense characters.",
  "features": [
    "mouse-driven",
    "audio-reactive",
    "sdf-glyph",
    "depth-luminance",
    "upgraded-rgba"
  ],
  "tags": [
    "filter",
    "image-processing",
    "ascii",
    "glyph",
    "SDF",
    "typography"
  ],
  "params": [
    {
      "id": "glyphSize",
      "name": "Glyph Size",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "brightness",
      "name": "Brightness",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "colorAmount",
      "name": "Color Amount",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "densityBoost",
      "name": "Density Boost",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Glyph Size",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Brightness",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Color Amount",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Density Boost",
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
//  ASCII Glyph
//  Category: stylize
//  Features: animated, depth-luminance, bass-character-swap, upgraded-rgba
//  Complexity: High
//  Chunks From: ascii-glyph, bass_env
//  Created: 2024-01-01
//  Upgraded: 2026-05-31
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
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.3 + mids * 0.1;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let glyphSize = mix(4.0, 32.0, u.zoom_params.x) * bass_env(bass, mids);
    let brightness = u.zoom_params.y;
    let colorAmount = u.zoom_params.z;
    let densityBoost = u.zoom_params.w;

    let pixelUV = uv * resolution;
    let cell = floor(pixelUV / glyphSize);
    let cellUV = fract(pixelUV / glyphSize);
    let cellCenter = (cell + 0.5) * glyphSize / resolution;

    // Sample luminance at cell center with depth weighting
    let centerColor = textureSampleLevel(readTexture, u_sampler, cellCenter, 0.0);
    let luma = dot(centerColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let depthLuma = mix(luma, luma * (1.0 - depth), 0.3);

    // Character density: higher for bright areas, boosted by densityBoost
    let charDensity = smoothstep(0.3, 0.9, depthLuma + densityBoost * 0.2);

    // Bass character swap: swap glyph patterns on strong beats
    let beatSwap = hash12(cell + vec2<f32>(floor(bass * 5.0), 0.0));
    let glyphPattern = hash12(cell + vec2<f32>(beatSwap, 0.0));

    let glyphThreshold = glyphPattern;
    let isGlyph = step(glyphThreshold, charDensity);

    // Glyph SDF approximation: simple cross/dot
    let crossDist = min(abs(cellUV.x - 0.5), abs(cellUV.y - 0.5));
    let dotDist = length(cellUV - vec2<f32>(0.5));
    let glyphShape = select(1.0 - smoothstep(0.0, 0.15, crossDist), 1.0 - smoothstep(0.0, 0.2, dotDist), glyphPattern > 0.5);
    let glyphAlpha = glyphShape * isGlyph;

    // Depth-based color: foreground brighter, background darker
    let glyphColor = mix(
        vec3<f32>(0.8, 0.9, 1.0),
        centerColor.rgb * (1.0 + treble * 0.5),
        colorAmount
    );
    let depthColor = mix(vec3<f32>(0.3, 0.4, 0.5), glyphColor, depth);

    let finalRGB = depthColor * glyphAlpha * brightness;
    let alpha = clamp(glyphAlpha * brightness + bass * 0.05, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, alpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```
