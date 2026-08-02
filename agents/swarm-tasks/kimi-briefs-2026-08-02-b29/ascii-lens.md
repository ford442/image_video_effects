# Swarm Brief: ascii-lens

**Role:** Interactivist
**Name:** ASCII Lens
**Category:** interactive-mouse
**Description:** Reveals the image as procedural ASCII characters within a lens radius around the mouse.
**Current lines:** 119
**Target lines:** 169–209 (expand by +50 to +90)

## Role Instructions

You are the Interactivist. This lens renders honest procedural glyphs - but it never writes dataTextureA (breaking the every-frame contract), never samples audio, and the lens snaps to the cursor. Tighten it up:
- FIX THE FRAME CONTRACT + SPRING THE LENS (priority 1): add the missing `textureStore(dataTextureA, ...)` every frame (display color, same value as writeTexture). Ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the lens glides; raw mouse (with the existing negative-coord center fallback) stays the spring target.
- Click glyph scrambles: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple scrambles glyphs near its click point (a decaying hash jitter added to the luma tier selection inside an aspect-corrected ~0.2 radius, exp(-age * 2.5), ~1s), so clicks glitch the text even outside the lens (scramble applies inside the lens region; outside the lens a brief RGB split flicker marks the click).
- Wire the dead audio: per-cell flicker - each glyph cell's charVal shimmers by its own bin (`plasmaBuffer[(u32(cellHash * 8.0) % 8u) + 1u].x * 0.4`) so the text dances with the music; bass subtly breathes the lens radius (lensRadius * (1.0 + bass * 0.15)). Fix the stale header ('Category: distortion' -> interactive-mouse, comment-only).
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the grid/cellUV/localUV construction, the aspect-corrected cell sizing, the luma tier glyph selection (keep its branchy if/else form - pixel-crisp character), the width mapping, the depth-weighted alpha, and the outside-lens passthrough VERBATIM. All 4 slider ids/names/defaults EXACTLY (radius/density/line_width/brightness_bias with mapping fields). extraBuffer in [133..255] ONLY.

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
  "id": "ascii-lens",
  "name": "ASCII Lens",
  "url": "shaders/ascii-lens.wgsl",
  "description": "Reveals the image as procedural ASCII characters within a lens radius around the mouse.",
  "params": [
    {
      "id": "radius",
      "name": "Lens Radius",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x",
      "description": "Radius of the ASCII lens"
    },
    {
      "id": "density",
      "name": "Character Density",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y",
      "description": "Density of ASCII characters in the lens"
    },
    {
      "id": "line_width",
      "name": "Glyph Line Width",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z",
      "description": "Width of glyph lines in the ASCII characters"
    },
    {
      "id": "brightness_bias",
      "name": "Brightness Threshold Bias",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w",
      "description": "Bias for brightness threshold comparisons"
    }
  ],
  "features": [
    "mouse-driven"
  ],
  "tags": [
    "filter",
    "image-processing"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Lens Radius",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Character Density",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Glyph Line Width",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Brightness Threshold Bias",
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
//  ascii-lens
//  Category: distortion
//  Features: upgraded-rgba, depth-aware
//  Upgraded: 2026-03-22
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

// ASCII Lens
// Param 1: Lens Radius (0.0 to 1.0)
// Param 2: Grid Density (High values = smaller chars)

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    var mouse = u.zoom_config.yz;
    if (mouse.x < 0.0) { mouse = vec2<f32>(0.5, 0.5); }

    let lensRadius = u.zoom_params.x; // Default 0.3
    let density = 50.0 + u.zoom_params.y * 150.0; // 50 to 200 grid cells vertical

    // Calculate distance to mouse for lens effect
    let dist = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(mouse.x * aspect, mouse.y));

    // Sample depth for alpha calculation
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    var finalColor: vec3<f32>;
    var finalAlpha: f32;

    if (dist < lensRadius) {
        // Inside Lens: ASCII Effect

        // Define grid
        let grid = vec2<f32>(density * aspect, density); // Adjust X for aspect to make square cells
        let cellUV = floor(uv * grid) / grid;
        let localUV = fract(uv * grid);

        // Sample color at cell center (pixelated look)
        // Add half pixel offset to sample center of block
        let sampleUV = cellUV + (vec2<f32>(0.5) / grid);
        var col = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
        let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114)) + (u.zoom_params.w - 0.5) * 0.4;

        var charVal = 0.0;
        var center = vec2<f32>(0.5, 0.5);
        let distCenter = length(localUV - center);

        // Line width proportional to density? Constant is better for pixel crispness.
        // In UV space (0-1), 1 pixel width is roughly 1.0 / (res.y / density * 8.0).
        // Let's use a fixed relative width.
        let width = mix(0.02, 0.25, u.zoom_params.z);

        // Procedural Glyphs
        // Sorted by brightness
        if (luma > 0.8) {
            // # Block / Full
            charVal = 1.0;
        } else if (luma > 0.6) {
            // @ Square Frame + Dot
            if (abs(localUV.x - 0.5) > 0.2 || abs(localUV.y - 0.5) > 0.2) { charVal = 1.0; }
            if (distCenter < 0.1) { charVal = 1.0; }
        } else if (luma > 0.4) {
            // + Plus
            if (abs(localUV.x - 0.5) < width || abs(localUV.y - 0.5) < width) { charVal = 1.0; }
        } else if (luma > 0.25) {
            // - Minus
             if (abs(localUV.y - 0.5) < width) { charVal = 1.0; }
        } else if (luma > 0.1) {
            // . Dot
            if (distCenter < 0.15) { charVal = 1.0; }
        }

        finalColor = col * charVal;

        // Calculate luminance-based alpha
        let lumaFinal = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
        let alpha = mix(0.7, 1.0, lumaFinal);
        finalAlpha = mix(alpha * 0.8, alpha, depth);

    } else {
        // Outside Lens: Normal
        var col = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
        finalColor = col.rgb;
        finalAlpha = col.a;
    }

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
    
    // Pass depth
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```
