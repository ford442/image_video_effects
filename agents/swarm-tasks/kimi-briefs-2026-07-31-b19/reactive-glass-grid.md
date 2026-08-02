# Swarm Brief: reactive-glass-grid

**Role:** Visualist
**Name:** Reactive Glass Grid
**Category:** interactive-mouse
**Description:** A grid of refractive glass tiles that light up and distort based on mouse proximity.
**Current lines:** 100
**Target lines:** 150–190 (expand by +50 to +90)

## Role Instructions

You are the Visualist. This glass tile field is honest - every slider is real - but the cursor snaps, clicks do nothing, and every tile dances to the same global bass/treble. Give it weight, touch, and per-tile voices:
- Spring-damper the influence center (priority 1): ease the mouse target with a critically-damped spring (extraBuffer[133..136], [0..4] engine-reserved, [5..132] = engine FFT bins) so the glass bulge trails the cursor with weight; the raw clamped mouse stays the spring target.
- Click glass shockwaves: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a decaying radial influence ring at its click point (expanding smoothstep band boosting `influence` + caustic sparkle, ~1.5s fade), so clicks send ripples through the tiles.
- Per-tile FFT voices: derive a bin index from the tile id (`u32(hash21(floor(gridUV)) * 8.0) % 8u + 1u`) and let that bin's `plasmaBuffer[bin].x` modulate that tile's caustic sparkle amplitude, so different tiles listen to different frequencies instead of all following global treble.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the bass_env/hash21 helpers, the refraction + chromatic dispersion tap structure (rUV/gUV/bUV), the fresnel rim, and the ior depth mapping VERBATIM - the glass look is hand-tuned. dataTextureA stays DISPLAY color (raw, never tonemapped). extraBuffer in [133..255] ONLY.

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
  "id": "reactive-glass-grid",
  "name": "Reactive Glass Grid",
  "url": "shaders/reactive-glass-grid.wgsl",
  "description": "A grid of refractive glass tiles that light up and distort based on mouse proximity.",
  "params": [
    {
      "id": "tile_size",
      "name": "Tile Density",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "refraction",
      "name": "Refraction",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "glow",
      "name": "Glow Intensity",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "edge_smooth",
      "name": "Edge Smoothness",
      "default": 0.2,
      "min": 0,
      "max": 1
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
      "name": "Tile Density",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Refraction",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Glow Intensity",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Edge Smoothness",
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
//  Reactive Glass Grid
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, caustics, chromatic-dispersion, fresnel, upgraded-rgba
//  Complexity: High
//  Chunks From: reactive-glass-grid, bass_env, fresnel
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.4 + mids * 0.15;
}

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let cellDensity = mix(4.0, 40.0, u.zoom_params.x) * bass_env(bass, mids);
    let refractionAmount = u.zoom_params.y * (1.0 + mids * 0.3);
    let glowIntensity = u.zoom_params.z * bass_env(bass, mids);
    let edgeSmooth = mix(0.12, 0.48, u.zoom_params.w);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let ior = mix(1.1, 1.5, depth);

    let gridUV = uv * cellDensity;
    let localUV = fract(gridUV) - 0.5;
    let mouseDist = length((mousePos - uv) * vec2<f32>(aspect, 1.0));
    let influence = smoothstep(0.45, 0.0, mouseDist) * (0.5 + glowIntensity * 0.5);
    let wave = sin(time * (2.0 + bass * 2.0) * (1.0 + mids * 0.35) - mouseDist * 24.0) * 0.5 + 0.5;
    let bump = localUV * influence * (0.5 + wave * 0.5);
    let normal = normalize(vec3<f32>(-bump.x * 8.0, -bump.y * 8.0, 1.0));

    let refract = normal.xy * 0.06 * refractionAmount * (1.0 + treble * 0.25) / ior;
    let finalUV = clamp(uv + refract, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));

    // Caustic sparkle
    let caustic = hash21(floor(gridUV) + time * 0.5) * influence * treble * 2.0;

    // Chromatic dispersion scaled by depth
    let aberration = refractionAmount * 0.012 * (1.0 + treble * 0.3) * (ior - 1.0);
    let rUV = clamp(finalUV + vec2<f32>(aberration, 0.0), vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
    let gUV = finalUV;
    let bUV = clamp(finalUV - vec2<f32>(aberration, 0.0), vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));

    let gColor = textureSampleLevel(readTexture, u_sampler, gUV, 0.0);
    let edge = 1.0 - smoothstep(edgeSmooth, 0.5, length(localUV));
    let gridGlow = vec3<f32>(0.1 + caustic, 0.25 + treble * 0.08 + caustic * 0.5, 0.35 + caustic * 0.3) * edge * influence * glowIntensity * 1.5;
    var finalColor = vec3<f32>(
        textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r,
        gColor.g,
        textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b
    ) + gridGlow;

    // Fresnel rim on tile edges
    let fresnel = pow(1.0 - abs(dot(normal, vec3<f32>(0.0, 0.0, 1.0))), 2.0);
    finalColor = finalColor + vec3<f32>(0.3, 0.5, 0.7) * fresnel * edge * influence;

    let alpha = clamp(gColor.a * 0.45 + edge * 0.18 + influence * 0.25 + bass * 0.05 + fresnel * 0.1, 0.08, 1.0);
    let depthOut = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, finalUV, 0.0).r + influence * 0.05, 0.0, 1.0);
    let finalPixel = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalPixel);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalPixel);
}
```
