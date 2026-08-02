# Swarm Brief: spec-histogram-equalize

**Role:** Algorithmist
**Name:** Histogram Equalize
**Category:** image
**Description:** Real-time CLAHE histogram equalization using workgroup cooperative histogram building. Computes local histogram per 8x8 tile and remaps intensities via CDF for dramatic adaptive contrast enhancement.
**Current lines:** 106
**Target lines:** 156–196 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. This CLAHE shader is a double agent: 'Clip Limit' computes a clippedCount that is NEVER USED (no actual clipping happens), 'Tile Blend' is read and NEVER REFERENCED, and dataTextureA gets masks instead of display color. Two dead sliders and a poisoned slot - make it the real CLAHE it claims to be:
- REAL CLAHE CLIP (priority 1): implement the actual clip-and-redistribute - after the histogram barrier, each thread computes the clipped CDF for its bin: cdfClip = sum over i<=bin of min(count[i], u32(clipLimit)) PLUS uniform redistribution of the total clipped excess (excess = sum over all i of count[i] - min(count[i], clip); add excess * (bin + 1) / 256). Use cdfClip / totalPixels for equalizedLuma. A 256-iteration loop per thread is fine. Note: the slider was DEAD, so any wiring changes the look - that is the fix, not a regression; document the chosen mapping.
- WIRE TILE BLEND + FIX THE A SLOT: tileBlend (z) should soften tile seams - blend the final color toward a 4-tap neighbor average remapped with the same scaleFactor (`mix(outColor, neighborAvg * scaleMix, tileBlend * 0.5)`), so 0 = crisp per-tile, 1 = spatially smoothed. Then write the DISPLAY color (outColor, color.a) to dataTextureA and move the debug quad (equalizedLuma, luma, scaleFactor, cdfNorm) to dataTextureB. Remove the dead PI/TAU consts and the dead clippedCount line. Fix the stale '8x8' doc comment (workgroup is 16x16).
- Mouse contrast lens (optional flavor, not tagged mouse-driven): near the cursor, locally raise `strength` (+0.3 smoothstep falloff ~0.3 radius) so the pointer peels open local contrast. Loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple pulses a temporary clip-limit loosening at its click point (~1.5s fade), so clicks pop the tonal range locally.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: the workgroup choreography is SACRED - all workgroupBarrier() calls must stay OUTSIDE conditionals (divergence = UB), keep the cooperative clear/vote structure, the atomic ops, the luma binning, and the inBounds write guard VERBATIM in structure. totalPixels stays 256u. @workgroup_size(16, 16, 1) is load-bearing here. dataTextureB is write-only storage - fine for the debug quad. extraBuffer (if used) in [133..255] ONLY.

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
  "id": "spec-histogram-equalize",
  "name": "Histogram Equalize",
  "url": "shaders/spec-histogram-equalize.wgsl",
  "description": "Real-time CLAHE histogram equalization using workgroup cooperative histogram building. Computes local histogram per 8x8 tile and remaps intensities via CDF for dramatic adaptive contrast enhancement.",
  "tags": [
    "histogram",
    "equalization",
    "CLAHE",
    "contrast",
    "cooperative",
    "workgroup"
  ],
  "features": [
    "cooperative-workgroup",
    "histogram",
    "CLAHE",
    "contrast-enhancement"
  ],
  "params": [
    {
      "id": "clip_limit",
      "name": "Clip Limit",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "strength",
      "name": "Effect Strength",
      "default": 0.6,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "tile_blend",
      "name": "Tile Blend",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "color_preserve",
      "name": "Color Preserve",
      "default": 0.7,
      "min": 0,
      "max": 1,
      "step": 0.01
    }
  ],
  "target_rating": 4.6,
  "updatedParams": [
    {
      "index": 0,
      "name": "Clip Limit",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Effect Strength",
      "default": 0.6,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Tile Blend",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Color Preserve",
      "default": 0.7,
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
//  spec-histogram-equalize
//  Category: image
//  Features: cooperative-workgroup, histogram, CLAHE
//  Complexity: High
//  Upgraded: 2026-05-23
//  upgraded-rgba
// ═══════════════════════════════════════════════════════════════════
//  Real-Time Histogram Equalization via Workgroup Reduction
//  Computes a local histogram within each 8x8 workgroup tile, then
//  uses the CDF to remap pixel intensities (CLAHE-style contrast).
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
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=ClipLimit, y=Strength, z=TileBlend, w=ColorPreserve
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

var<workgroup> localHistogram: array<atomic<u32>, 256>;

@compute @workgroup_size(16, 16, 1)
fn main(
    @builtin(global_invocation_id) gid: vec3<u32>,
    @builtin(local_invocation_id) lid: vec3<u32>,
    @builtin(local_invocation_index) lidx: u32
) {
    let res = u.config.zw;
    let inBounds = gid.x < u32(res.x) && gid.y < u32(res.y);
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let bass = plasmaBuffer[0].x;

    // Bass loosens contrast clip — beat opens up tonal range
    let clipLimit = mix(1.0, 8.0, u.zoom_params.x) * (1.0 + bass * 0.3);
    let strength = mix(0.0, 1.0, u.zoom_params.y);
    let tileBlend = mix(0.0, 1.0, u.zoom_params.z);
    let colorPreserve = mix(0.0, 1.0, u.zoom_params.w);

    // Phase 1: Clear histogram (cooperative clear)
    for (var i = lidx; i < 256u; i = i + 256u) {
        atomicStore(&localHistogram[i], 0u);
    }
    workgroupBarrier();

    // Read color and compute luma
    let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = clamp(dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114)), 0.0, 1.0);
    let bin = u32(luma * 255.0);

    // Phase 2: Vote into histogram
    atomicAdd(&localHistogram[bin], 1u);
    workgroupBarrier();

    // Phase 3: Read our bin count and compute prefix sum (CDF) for our bin
    var cdf = 0u;
    for (var i = 0u; i <= bin; i = i + 1u) {
        cdf = cdf + atomicLoad(&localHistogram[i]);
    }

    // CLAHE: clip histogram and redistribute
    let totalPixels = 256u; // 16x16 workgroup
    let clippedCount = min(atomicLoad(&localHistogram[bin]), u32(clipLimit));

    // Phase 4: Remap using CDF
    let equalizedLuma = f32(cdf) / f32(totalPixels);
    let originalLuma = max(luma, 0.001);
    let scaleFactor = equalizedLuma / originalLuma;

    // Blend between equalized and original
    var outColor: vec3<f32>;
    if (colorPreserve > 0.5) {
        // Preserve hue, adjust luminance
        outColor = color.rgb * mix(1.0, scaleFactor, strength);
    } else {
        outColor = mix(color.rgb, color.rgb * scaleFactor, strength);
    }

    // Tone map and clamp
    outColor = clamp(outColor, vec3<f32>(0.0), vec3<f32>(3.0));

    // Preserve input alpha
    if (inBounds) {
        textureStore(writeTexture, gid.xy, vec4<f32>(outColor, color.a));
        textureStore(dataTextureA, gid.xy, vec4<f32>(equalizedLuma, luma, scaleFactor, f32(cdf) / f32(totalPixels)));
        let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
        textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0, 0, 0.0));
    }
}
```
