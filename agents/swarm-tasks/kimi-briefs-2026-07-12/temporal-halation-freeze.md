# KIMI SWARM TASK — UPGRADE — temporal-halation-freeze

## Role Assignment
**Primary Agent:** Optimizer  
**Domain:** performance, elegance, pipeline integration, LOD, semantic alpha

## Shader Identity
- **ID:** `temporal-halation-freeze`
- **Name:** Temporal Halation Freeze
- **Category:** post-processing
- **Current lines:** 106
- **Target lines:** 146 (max)
- **Current description:** Long-exposure style halation and light bloom that slowly accumulates and 'freezes' bright moments with beautiful decaying ghost echoes. Transforms video into dreamy, time-blurred poetry. Bass lengthens the exposure tail.

## Creative Brief
Upgrade `temporal-halation-freeze` while preserving its original visual soul. The optimizer should make the shader feel more sophisticated, reactive, and compositing-friendly without turning it into a different effect. Inject at least two modern techniques (FBM domain warp, curl noise, ACES tone mapping, semantic alpha, depth-aware compositing, audio envelope, IGN dither, etc.).

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
//  Temporal Halation Freeze
//  Category: post-processing
//  Features: halation, bloom, temporal, long-exposure, ghost, audio-tail, semantic-alpha
//  Complexity: Medium-High
//  Chunks From: _hash_library.wgsl (hash21)
//  Created: 2026-06-01
//  By: Grok (new image/video effect — long-exposure halation and light bloom that accumulates and slowly freezes bright moments with decaying ghosts)
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
  zoom_params: vec4<f32>,  // x=Exposure, y=Decay, z=Color, w=Ghost
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / res;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let exposure = u.zoom_params.x * (0.6 + bass * 0.7);
    let decay = u.zoom_params.y * 0.92 + 0.06;
    let colorTemp = u.zoom_params.z;
    let ghostAmt = u.zoom_params.w;

    let input = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(input.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Previous accumulated halation (temporal)
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

    // Halation bloom — strong on bright areas, bleeds outward
    let bloomRadius = 0.004 + exposure * 0.009;
    let texel = 1.0 / res;

    var halo = vec3<f32>(0.0);
    for (var i = -2; i <= 2; i = i + 1) {
        for (var j = -2; j <= 2; j = j + 1) {
            if (i == 0 && j == 0) { continue; }
            let off = vec2<f32>(f32(i), f32(j)) * texel * bloomRadius * 18.0;
            let s = textureSampleLevel(readTexture, u_sampler, uv + off, 0.0).rgb;
            let w = exp(-length(vec2<f32>(f32(i), f32(j))) * 0.45);
            halo += s * w;
        }
    }
    halo /= 24.0;

    // Accumulate with decay (long exposure freeze)
    let brightMask = smoothstep(0.45, 0.92, luma);
    let newHalo = halo * brightMask * exposure * 0.85;
    let accumulated = prev.rgb * decay + newHalo * (0.6 + bass * 0.3);

    // Ghost echo (older, more decayed)
    let ghost = prev.rgb * (ghostAmt * 0.45) * (0.7 + treble * 0.4);

    // Color temperature on the bloom
    let warm = mix(vec3<f32>(1.0, 0.75, 0.45), vec3<f32>(0.6, 0.85, 1.0), colorTemp);
    let bloomCol = accumulated * warm;

    // Final composite
    var col = input.rgb * (1.0 - brightMask * 0.15) + bloomCol * 1.1 + ghost * 0.6;

    // Gentle filmic rolloff
    col = 1.0 - exp(-col * 1.05);

    // Semantic alpha — very high on strong halation areas (ethereal quality)
    let energy = length(accumulated) * 0.8 + length(ghost) * 0.5;
    let semantic_alpha = clamp(0.58 + energy * 0.55, 0.45, 1.0);

    textureStore(writeTexture, global_id.xy, vec4<f32>(col, semantic_alpha));

    // Write new accumulation state
    textureStore(dataTextureA, global_id.xy, vec4<f32>(accumulated.r, accumulated.g, accumulated.b, semantic_alpha));

    let d = clamp(0.18 + energy * 0.45, 0.0, 0.93);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}

```

## CURRENT SOURCE JSON
```json
{
  "id": "temporal-halation-freeze",
  "name": "Temporal Halation Freeze",
  "url": "shaders/temporal-halation-freeze.wgsl",
  "description": "Long-exposure style halation and light bloom that slowly accumulates and 'freezes' bright moments with beautiful decaying ghost echoes. Transforms video into dreamy, time-blurred poetry. Bass lengthens the exposure tail.",
  "tags": [
    "halation",
    "bloom",
    "long-exposure",
    "temporal",
    "ghost",
    "cinematic",
    "audio-reactive"
  ],
  "features": [
    "audio-reactive",
    "audio-driven",
    "temporal",
    "semantic-alpha",
    "depth-aware"
  ],
  "params": [
    {
      "id": "exposure",
      "name": "Exposure Length",
      "default": 0.7,
      "min": 0.0,
      "max": 1.5,
      "step": 0.01
    },
    {
      "id": "decay",
      "name": "Decay Rate",
      "default": 0.86,
      "min": 0.6,
      "max": 0.97,
      "step": 0.01
    },
    {
      "id": "color",
      "name": "Bloom Color Temp",
      "default": 0.35,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "id": "ghost",
      "name": "Ghost Echo",
      "default": 0.55,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    }
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
Target: 146 lines max. Prefer dense math over comments. Stop the moment the WGSL fence closes. Nothing after it.
