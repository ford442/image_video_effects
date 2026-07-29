# Swarm Brief: velvet-vortex

**Role:** Visualist
**Name:** Velvet Vortex
**Category:** interactive-mouse
**Description:** A spiraling, velvety distortion that swirls video content around the mouse cursor.
**Current lines:** 88
**Target lines:** 138–178 (expand by +50 to +90)

## Role Instructions

You are the Visualist. This vortex is already honest under the hood - give it touch, glide, and a per-voice spectrum:
- Click swirl shockwaves (priority 1): the ripples[] uniform is unused. Loop it (guard `min(u32(u.config.y), 50u)`); each live ripple spawns an expanding ring from its click point that adds a decaying extra twist to `angle` inside the ring band (age = time - ripple.z, fade over ~2s), so clicks visibly whip the velvet.
- Spring-damper the vortex center: ease the mouse target with a critically-damped spring stored in extraBuffer[133..136] ([0..4] reserved, [5..132] = engine FFT) so the vortex glides after the cursor instead of snapping; integrate with the existing depth parallax offset.
- Per-arm spectrum: replace the single global `armCount = 3 + floor(mids*6)` with per-sample angular FFT - rotate `plasmaBuffer[(bin % 8) + 1].x` into the swirl phase by angle sector so different arms shimmer on different bins; keep treble driving the velvet tint as now.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the 2x2 rotation-matrix swirl math, the smoothstep falloff structure, and the depth-parallax (depth-0.5)*0.04 VERBATIM - the swirl identity is hand-tuned. Fix the stale header comment claiming 'Category: distortion' (JSON lives in interactive-mouse) - comment-only. dataTextureA stays DISPLAY color (not sim state). extraBuffer in [133..255] ONLY.

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
  "id": "velvet-vortex",
  "name": "Velvet Vortex",
  "url": "shaders/velvet-vortex.wgsl",
  "description": "A spiraling, velvety distortion that swirls video content around the mouse cursor.",
  "params": [
    {
      "id": "radius",
      "name": "Vortex Radius",
      "default": 0.4,
      "min": 0,
      "max": 1
    },
    {
      "id": "strength",
      "name": "Swirl Force",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "softness",
      "name": "Edge Softness",
      "default": 0.6,
      "min": 0,
      "max": 1
    },
    {
      "id": "pulse",
      "name": "Pulse Speed",
      "default": 0.2,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
    "mouse-driven",
    "audio-reactive",
    "audio-driven"
  ],
  "tags": [
    "filter",
    "image-processing",
    "audio",
    "music",
    "reactive"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Vortex Radius",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Swirl Force",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Edge Softness",
      "default": 0.6,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Pulse Speed",
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
//  Velvet Vortex
//  Category: distortion
//  Features: mouse-driven, vortex, velvet, audio-swirl, depth-pile, light-absorb, tactile-motion
//  Complexity: Medium
//  Updated: 2026-05-31
//  By: Grok (visual flourish — richer material feel, audio texture, atmospheric absorption)
// ═══════════════════════════════════════════════════════════════════
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
  return 1.0 + bass * 0.5 + mids * 0.2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;
    let center = u.zoom_config.yz;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let parallax = (depth - 0.5) * 0.04;

    let radiusParam = max(u.zoom_params.x, 0.001);
    let strength = u.zoom_params.y * bass_env(bass, mids);
    let softness = u.zoom_params.z;
    let pulseSpeed = u.zoom_params.w;

    let uvCorrected = uv * vec2<f32>(aspect, 1.0);
    let centerCorrected = center * vec2<f32>(aspect, 1.0) + vec2<f32>(parallax, parallax);
    let dist = distance(uvCorrected, centerCorrected);
    let pulse = sin(time * pulseSpeed * bass_env(bass, mids) * 5.0) * 0.2 + 1.0;
    let effectiveRadius = max(radiusParam * pulse, 0.001);
    let swirlFactor = 1.0 - smoothstep(0.0, effectiveRadius, dist);
    let softFactor = pow(swirlFactor, 1.0 / (softness + 0.1));

    // Audio modulates arm count
    let armCount = 3.0 + floor(mids * 6.0);
    let angle = strength * (8.0 + armCount) * softFactor;

    let s = sin(angle);
    let c = cos(angle);
    let dir = uvCorrected - centerCorrected;
    let rotatedDir = vec2<f32>(
        dir.x * c - dir.y * s,
        dir.x * s + dir.y * c
    );
    let finalUV = clamp((rotatedDir + centerCorrected) / vec2<f32>(aspect, 1.0), vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));

    let baseColor = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);
    let velvetTint = vec3<f32>(0.12 + bass * 0.05, 0.02 + treble * 0.04, 0.16 + bass * 0.05) * softFactor;
    let finalColor = mix(baseColor.rgb, baseColor.rgb * vec3<f32>(0.85, 0.78 + treble * 0.08, 1.08), softFactor * 0.25) + velvetTint;
    let alpha = clamp(baseColor.a * 0.45 + softFactor * 0.35 + bass * 0.06, 0.08, 1.0);
    let depthOut = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r + softFactor * 0.05, 0.0, 1.0);
    let finalPixel = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalPixel);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalPixel);
}
```
