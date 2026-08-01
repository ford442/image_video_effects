# Swarm Brief: prismatic-3d-compositor

**Role:** Algorithmist
**Name:** Prismatic 3D Compositor (Pass 2)
**Category:** interactive-mouse
**Description:** Adds parallax shifting, volumetric glow, chromatic aberration and final composite with depth-aware blending.
**Current lines:** 109
**Target lines:** 159–199 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. This compositor divides an ALREADY-normalized mouse by the resolution a second time - `mousePos = zoom_config.yz / dims` pins the parallax driver to the corner pixel, so the headline parallax feature has never worked. Then there's the 'cameraZ' that is secretly mouseDown. Fix the plumbing:
- FIX THE INVERTED MOUSE UNITS (priority 1): `vec2<f32>(u.zoom_config.y / dims.x, u.zoom_config.z / dims.y)` -> `u.zoom_config.yz` (already normalized [0,1]). Verify the parallax shift then actually tracks the cursor.
- HONEST LABELS + DEAD TREBLE: `cameraZ = u.zoom_config.w` is mouseDown - rename the local to mouseDown and use it as a parallax push (pressing deepens the shift: parallax *= (1.0 + mouseDown * 0.5)); update the mapping-notes comment. Wire the dead treble into the glow (glowIntensity * (1.0 + treble * 0.3)) so all three bands live.
- Click prism flares: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a decaying aberration spike at its click point (local chromatic offset boost exp(-age * 2.0), ~1.2s fade), so clicks flare the prism.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: this shader styles itself PASS 2 of 2 (reads pass-1 cloud color/depth from readTexture/readDepthTexture) - its JSON is standalone (no multipass key), so treat those reads as its GIVEN inputs and do NOT restructure them. Preserve the 5x5 glow gather, the depth-separated layered mix, the temporal feedback (A=feedback color, C=prev - consistent, keep symmetric), and the alpha luminance key VERBATIM. Sliders have non-0..1 ranges (Glow Radius 0-10, Intensity 0-4, Parallax 0-4, Aberration 0-0.2) - keep roles AND ranges EXACTLY. extraBuffer (if used) in [133..255] ONLY.

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
  "id": "prismatic-3d-compositor",
  "name": "Prismatic 3D Compositor (Pass 2)",
  "url": "shaders/prismatic-3d-compositor.wgsl",
  "description": "Adds parallax shifting, volumetric glow, chromatic aberration and final composite with depth-aware blending.",
  "params": [
    {
      "id": "glowRadius",
      "name": "Glow Radius",
      "default": 1,
      "min": 0,
      "max": 10
    },
    {
      "id": "glowIntensity",
      "name": "Glow Intensity",
      "default": 1,
      "min": 0,
      "max": 4
    },
    {
      "id": "parallaxAmount",
      "name": "Parallax",
      "default": 1,
      "min": 0,
      "max": 4
    },
    {
      "id": "aberration",
      "name": "Aberration",
      "default": 0.02,
      "min": 0,
      "max": 0.2
    }
  ],
  "features": [
    "multi-pass",
    "volumetric",
    "depth",
    "lighting",
    "mouse-driven",
    "audio-reactive",
    "upgraded-rgba"
  ],
  "tags": [
    "filter",
    "image-processing"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Glow Radius",
      "default": 1,
      "min": 0.0,
      "max": 10.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Glow Intensity",
      "default": 1,
      "min": 0.0,
      "max": 4.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Parallax",
      "default": 1,
      "min": 0.0,
      "max": 4.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Aberration",
      "default": 0.02,
      "min": 0.0,
      "max": 0.2,
      "step": 0.01
    }
  ],
  "updated": true
}
```

## Current WGSL Code

```wgsl
// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

// ═══════════════════════════════════════════════════════════════
//  Prismatic 3D Compositor - PASS 2 of 2
//  Adds parallax shifting, volumetric glow, chromatic aberration
//  and final composite with depth-aware blending.
//  
//  Inputs:
//    - readTexture: Pass 1 cloud color
//    - readDepthTexture: Pass 1 cloud depth
//  
//  Features: compositor, parallax, volumetric-glow, mouse-driven, audio-reactive, upgraded-rgba
//  Previous Pass: volumetric-rainbow-clouds.wgsl
// ═══════════════════════════════════════════════════════════════

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>
};

// Mapping notes:
// u.zoom_config.yz -> mouse X,Y
// u.zoom_config.w -> cameraZ
// u.zoom_params.x..w -> comp_params: glowRadius, glowIntensity, parallaxAmount, aberration
// u.ripples[0].x may be used for blend_params.x (videoBlend) if needed

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    var uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;
    var mousePos = vec2<f32>(u.zoom_config.y / dims.x, u.zoom_config.z / dims.y);
    let cameraZ = u.zoom_config.w;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;

    // Sample Pass 1 results (assume readTexture contains Pass1 color and readDepthTexture contains Pass1 depth)
    let cloudColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // 1) Parallax shift
    let parallax = u.zoom_params.z * depth * cameraZ * (1.0 + bass * 0.4);
    let parallaxUV = uv + (mousePos - vec2<f32>(0.5, 0.5)) * parallax;
    let parallaxColor = textureSampleLevel(readTexture, u_sampler, clamp(parallaxUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;

    // 2) Volumetric glow
    let glowRadius = u.zoom_params.x * 0.01;
    let glowIntensity = u.zoom_params.y;
    let glowThreshold = 0.2;

    var glow = vec3<f32>(0.0);
    var count = 0.0;
    for (var x: i32 = -2; x <= 2; x = x + 1) {
        for (var y: i32 = -2; y <= 2; y = y + 1) {
            let sampleUV = clamp(uv + vec2<f32>(f32(x), f32(y)) * glowRadius, vec2<f32>(0.0), vec2<f32>(1.0));
            let sampleColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
            let sampleDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
            let brightness = length(sampleColor);
            let weight = exp(-sampleDepth) * max(brightness - glowThreshold, 0.0);
            glow = glow + sampleColor * weight;
            count = count + weight;
        }
    }
    glow = glow / max(count, 1.0);

    // 3) Chromatic aberration along depth
    let aberration = u.zoom_params.w * depth * (1.0 + mids * 0.5);
    let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(aberration,0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(aberration,0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    let aberrantColor = vec3<f32>(r, g, b);

    // 4) Composite with video (video assumed bound to historyTex via renderer when desired) - here we just mix with original readTexture
    let videoColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    // blend params: videoBlend in extraBuffer[0], glowThreshold in extraBuffer[1], depthSharpness in extraBuffer[2]
    let videoBlend = 0.5;
    // Parallax layer rides on top: depth-separated ghost that bass pushes forward
    let layered = mix(aberrantColor, parallaxColor, clamp(depth * (0.4 + bass * 0.5), 0.0, 1.0));
    let lit = layered + glow * glowIntensity * (1.0 + bass * 0.6);
    let finalColor = mix(videoColor, lit, videoBlend);

    // 5) Temporal feedback — mids shorten the trail so busy passages stay crisp
    let prev = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).rgb;
    let feedback = mix(finalColor, prev, 0.85 - mids * 0.25);

    // Alpha carries composite luminance so downstream passes can key on it
    let alpha = clamp(length(finalColor) * 0.7 + depth * 0.3, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, alpha));
    textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(feedback, alpha));
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```
