# Swarm Brief: digital-haze

**Role:** Algorithmist
**Name:** Digital Haze
**Category:** interactive-mouse
**Description:** (no description field)
**Current lines:** 119
**Target lines:** 169–209 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. This volumetric haze has a DEAD SLIDER - the JSON advertises 'Haze Density' (w) but the WGSL never reads zoom_params.w; the extinction is hardcoded. Wire what you sell, then give the fog a hand:
- WIRE THE DEAD SLIDER (priority 1 - bit-exact at default 0.5): scale the haze extinction by the slider (`hazeDensity *= mix(0.4, 1.6, u.zoom_params.w)` - default 0.5 = 1.0, bit-identical to today). Now 'Haze Density' is real.
- Spring-damper the clear window: ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the clearing drags behind the cursor like wiping fogged glass; raw mouse stays the spring target. Keep the aspect correction.
- Click clear pulses + per-cell FFT static: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple punches a temporary clear hole at its click point (mask reduced by exp(-age * 2.0) in an aspect-corrected ~0.2 radius, ~1.5s), so clicks wipe the fog. Modulate each pixel-cell's noiseVal by its own bin (`plasmaBuffer[(u32(cellHash * 8.0) % 8u) + 1u].x * 0.3`) so the digital static flickers across the spectrum. Fix the stale header ('Category: distortion' -> interactive-mouse, comment-only).
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the SIGMA_T_HAZE/SIGMA_T_CLEAR/STEP_SIZE constants, the Beer-Lambert transmittance/optical-depth math, the volumetric composition (inScattered + transmittedClear + transmittedHaze), the quantized-UV pixelation, the green tint, and the volumetric alpha VERBATIM - the fog physics are the identity. dataTextureA stays DISPLAY color (finalOut). All 4 slider ids/names/defaults EXACTLY (with mapping fields). extraBuffer in [133..255] ONLY.

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
  "id": "digital-haze",
  "url": "shaders/digital-haze.wgsl",
  "features": [
    "mouse-driven",
    "audio-reactive",
    "upgraded-rgba"
  ],
  "params": [
    {
      "id": "pixel_strength",
      "name": "Pixel Strength",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x",
      "description": "Controls grid size for pixelation"
    },
    {
      "id": "clear_radius",
      "name": "Clear Radius",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y",
      "description": "Radius around mouse where fog clears"
    },
    {
      "id": "noise_amount",
      "name": "Noise Amount",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z",
      "description": "Amount of digital noise in the haze"
    },
    {
      "id": "haze_density",
      "name": "Haze Density",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w",
      "description": "Density of the volumetric haze"
    }
  ],
  "tags": [
    "filter",
    "image-processing"
  ],
  "name": "Digital Haze",
  "updatedParams": [
    {
      "index": 0,
      "name": "Pixel Strength",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Clear Radius",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Noise Amount",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Haze Density",
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
//  Digital Haze
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-23
// ═══════════════════════════════════════════════════════════════════
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture:    texture_2d<f32>;
@group(0) @binding(2) var writeTexture:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture:   texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB:   texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config:      vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples:     array<vec4<f32>, 50>,
};

// Digital haze extinction coefficients
const SIGMA_T_HAZE: f32 = 1.2;          // Haze extinction (thick)
const SIGMA_T_CLEAR: f32 = 0.05;        // Clear area extinction (minimal)
const STEP_SIZE: f32 = 0.03;            // Ray step

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    var uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;
    let aspect = dims.x / dims.y;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;

    var mouse = u.zoom_config.yz;
    let dVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dVec);

    // Params; bass pulses the haze density, mids vary the noise texture
    let pixelStrength = u.zoom_params.x * 100.0 + 10.0;
    let clearRadius = u.zoom_params.y * 0.4 + 0.05;
    let noiseAmt = u.zoom_params.z * (1.0 + mids * 0.4);

    // ═══════════════════════════════════════════════════════════════
    //  Calculate Grid-based "Volumetric Cells"
    // ═══════════════════════════════════════════════════════════════
    
    // Mask: 0.0 near mouse (clear), 1.0 far away (haze)
    let mask = smoothstep(clearRadius, clearRadius + 0.2, dist);

    // Dynamic Pixelation
    let gridSize = vec2<f32>(pixelStrength * aspect, pixelStrength);
    let quantizedUV = floor(uv * gridSize) / gridSize;

    // Add digital noise to the quantized UV
    let seed = quantizedUV + vec2<f32>(time * 0.1, time * 0.05);
    let noiseVal = (hash(seed) - 0.5) * noiseAmt * 0.05;
    let hazeUV = quantizedUV + noiseVal;

    // Sample colors
    let colClear = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let colHaze = textureSampleLevel(readTexture, u_sampler, hazeUV, 0.0).rgb;

    // Apply a "digital" tint to the haze
    let greenTint = vec3<f32>(0.0, 0.1, 0.0) * noiseAmt;
    let finalHaze = colHaze + greenTint;

    // ═══════════════════════════════════════════════════════════════
    //  Volumetric Fog Calculation
    // ═══════════════════════════════════════════════════════════════
    
    // Calculate optical depth based on mask (haze density); bass pulses fog thickness
    let hazeDensity = (mask * SIGMA_T_HAZE + (1.0 - mask) * SIGMA_T_CLEAR) * (1.0 + bass * 0.5);
    
    // Optical depth through the haze layer
    let opticalDepth = hazeDensity * STEP_SIZE * (1.0 + noiseAmt * 0.5);
    
    // Transmittance (Beer-Lambert): T = exp(-τ)
    let transmittance = exp(-opticalDepth);
    
    // Volumetric alpha: α = 1 - T
    let alpha = 1.0 - transmittance;
    
    // In-scattered light (digital haze color)
    let hazeColor = vec3<f32>(0.1, 0.15, 0.1); // Digital green-grey haze
    let inScattered = hazeColor * mask * (1.0 - transmittance);
    
    // Volumetric composition
    // Final = in_scattered + transmitted_clear * T + transmitted_haze * (1-T)
    let transmittedClear = colClear * transmittance;
    let transmittedHaze = finalHaze * (1.0 - transmittance) * 0.3;
    
    let finalColor = inScattered + transmittedClear + transmittedHaze;

    // Output with volumetric alpha; A = Beer-Lambert optical opacity
    let finalOut = vec4<f32>(finalColor, alpha);
    let depthVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, gid.xy, finalOut);
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthVal, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(gid.xy), finalOut);
}
```
