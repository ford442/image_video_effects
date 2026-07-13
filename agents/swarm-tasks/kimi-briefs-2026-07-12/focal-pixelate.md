# KIMI SWARM TASK — UPGRADE — focal-pixelate

## Role Assignment
**Primary Agent:** Optimizer  
**Domain:** performance, elegance, pipeline integration, LOD, semantic alpha

## Shader Identity
- **ID:** `focal-pixelate`
- **Name:** Focal Pixelate
- **Category:** interactive-mouse
- **Current lines:** 98
- **Target lines:** 138 (max)
- **Current description:** Applies pixelation that varies based on distance from the mouse cursor, creating a focal point effect.

## Creative Brief
Upgrade `focal-pixelate` while preserving its original visual soul. The optimizer should make the shader feel more sophisticated, reactive, and compositing-friendly without turning it into a different effect. Inject at least two modern techniques (FBM domain warp, curl noise, ACES tone mapping, semantic alpha, depth-aware compositing, audio envelope, IGN dither, etc.).

## OUTPUT CONTRACT (non-negotiable)
1. Your entire response after the closing ``` of the WGSL block must be completely empty.
2. The shader must use the exact 13-binding header above (no `outputTex`, `videoSampler`, `iTime`, `mouse`).
3. Compute entry must be `@compute @workgroup_size(16, 16, 1)`.
4. Alpha must carry semantic meaning (density, energy, depth, or bloom weight). Never end with `vec4(..., 1.0)` unless opaque by design.
5. Use at least two techniques from the Kimi graphical tactics below.
6. Stay within the line budget.

## IMMUTABLE 13-BINDING CONTRACT (copy EXACTLY)
```wgsl
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
  config: vec4<f32>,       // .x = time, .y = delta_time, .zw = resolution
  zoom_config: vec4<f32>,  // .x = zoom, .yz = mouse_uv, .w = mouse_down
  zoom_params: vec4<f32>,  // .xyzw = user params p1..p4
  ripples: array<vec4<f32>, 50>,
};
```

## CURRENT SOURCE WGSL
```wgsl
// ═══════════════════════════════════════════════════════════════════
//  Focal Pixelate
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Low
//  Chunks From: focal-pixelate
//  Created: 2026-05-30
//  By: Copilot CLI
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
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    var uv = vec2<f32>(global_id.xy) / resolution;
    var mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let treble = audio.z;

    // Params
    // x: min grid size (0.0 = high res/no pixelation, 1.0 = big blocks)
    // y: max grid size
    // z: radius
    // w: softness

    let min_grid = mix(1000.0, 50.0, u.zoom_params.x); // High number = small pixels
    let max_grid = mix(1000.0, 10.0, u.zoom_params.y);
    let radius = u.zoom_params.z;
    let softness = u.zoom_params.w;

    var dVec = uv - mousePos;
    dVec.x *= aspect;
    let dist = length(dVec);

    let t = smoothstep(radius, radius + softness + 0.001, dist);
    let current_grid = mix(max_grid, min_grid, t); // Near mouse = max_grid (low res) or min_grid (high res)?

    // "Focal Pixelate" usually means clear in center, pixelated outside.
    // So let's invert logic:
    // Near mouse (dist < radius) => High Res (min_grid is actually just normal sampling if we handle it right)
    // Far from mouse => Low Res (max_grid)

    // Let's re-parameterize for clarity in usage:
    // Param X: Pixelation Amount (at edge)
    // Param Y: Focus Size (Radius)
    // Param Z: Focus Falloff (Softness)
    // Param W: Invert (0 = Clear Center, 1 = Pixelated Center)

    let pixel_strength = mix(500.0, 20.0, u.zoom_params.x) * (1.0 - bass * 0.3); // 500 = small blocks, 20 = huge blocks
    let focus_radius = u.zoom_params.y;
    let focus_falloff = u.zoom_params.z;
    let invert = u.zoom_params.w > 0.5;

    var mix_factor = smoothstep(focus_radius, focus_radius + focus_falloff + 0.001, dist);
    if (invert) {
        mix_factor = 1.0 - mix_factor;
    }

    // if mix_factor is 0 (center), we want high res. If 1 (edge), we want pixel_strength.
    // Ideally high res is direct sampling.
    // But for pixelation code:
    let blocks = max(mix(2000.0, pixel_strength, mix_factor), 1.0);

    let pixel_uv = clamp(floor(uv * blocks) / blocks + (0.5 / blocks), vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999)); // Center sample

    let color = textureSampleLevel(readTexture, non_filtering_sampler, pixel_uv, 0.0).rgb;
    let finalAlpha = clamp(0.18 + mix_factor * 0.35 + treble * 0.08, 0.08, 0.9);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4(color, finalAlpha));

    // Pass depth
    let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, pixel_uv, 0.0).r + mix_factor * 0.03, 0.0, 1.0);
    textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(mix_factor, 1.0 / blocks, bass, finalAlpha));
}

```

## CURRENT SOURCE JSON
```json
{
  "id": "focal-pixelate",
  "name": "Focal Pixelate",
  "url": "shaders/focal-pixelate.wgsl",
  "features": [
    "mouse-driven"
  ],
  "description": "Applies pixelation that varies based on distance from the mouse cursor, creating a focal point effect.",
  "params": [
    {
      "id": "pixel_strength",
      "name": "Pixel Size",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "focus_radius",
      "name": "Focus Radius",
      "default": 0.3,
      "min": 0,
      "max": 1
    },
    {
      "id": "focus_falloff",
      "name": "Focus Softness",
      "default": 0.2,
      "min": 0,
      "max": 1
    },
    {
      "id": "invert",
      "name": "Invert Focus",
      "default": 0,
      "min": 0,
      "max": 1
    }
  ],
  "tags": [
    "mouse-driven",
    "interactive"
  ]
}
```

### Kimi Graphical Tactics (apply where appropriate)
- **Hue-preserving HDR clamp**: `fn hue_preserve_clamp(c, max_lum)` before tone map.
- **ACES filmic tonemap**: `fn aces(x)` as final color transform.
- **IGN blue-noise dither**: `fn ign(p)` before `textureStore` to kill banding.
- **Anti-aliased SDF step**: `fn aa_step(edge, x)` using `fwidth`.
- **Smooth-min SDF union**: `fn smin(a, b, k)`.
- **Domain-warped FBM**: `fn warpedFBM(p, t)` for organic flow.
- **Polar kaleidoscope fold**: `fn kaleido(uv, segs)`.
- **Hex bokeh sampling**: `HEX_TAPS` array for blur/DOF.
- **Audio-reactive envelope**: `fn bass_env(prev, bass, attack, release)` with state in `dataTextureA`.
- **Depth-aware compositing**: sample `readDepthTexture`, use exponential fog/mix.
- **Anti-moiré LOD bias**: `lod = clamp(log2(fwidth(uv) * cell_freq), 0, 4)`.
- **Premultiplied-alpha writeback**: `textureStore(writeTexture, gid.xy, vec4(rgb*a, a))`.

## ROLE TOOLKIT — Optimizer
See `agents/prompt-templates/optimizer.md` for the full toolkit. Use the canonical snippets from `agents/WGSL_BUILTINS_GENERATIVE.md`.

## LINE BUDGET & FINAL REMINDER
Target: 138 lines max. Prefer dense math over comments. Stop the moment the WGSL fence closes. Nothing after it.
