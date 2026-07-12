# KIMI SWARM TASK — UPGRADE — neon-edge-diffusion

## Role Assignment
**Primary Agent:** Optimizer  
**Domain:** performance, elegance, pipeline integration, LOD, semantic alpha

## Shader Identity
- **ID:** `neon-edge-diffusion`
- **Name:** Neon Edge Diffusion
- **Category:** artistic
- **Current lines:** 113
- **Target lines:** 153 (max)
- **Current description:** Sobel edge detection with neon-diffusion and color bleeding.

## Creative Brief
Upgrade `neon-edge-diffusion` while preserving its original visual soul. The optimizer should make the shader feel more sophisticated, reactive, and compositing-friendly without turning it into a different effect. Inject at least two modern techniques (FBM domain warp, curl noise, ACES tone mapping, semantic alpha, depth-aware compositing, audio envelope, IGN dither, etc.).

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
// ═══════════════════════════════════════════════════════════════
//  Neon Edge Diffusion - Diffused Glow with Alpha Emission
//  Category: lighting-effects
//  Physics: Diffused edge light with alpha occlusion
//  Alpha: Core diffusion = 0.3, Glow = 0.0 (additive)
// ═══════════════════════════════════════════════════════════════

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

// Alpha calculation for emissive materials
fn calculateEmissiveAlpha(glowIntensity: f32, occlusionBalance: f32) -> f32 {
    let coreAlpha = 0.3 * glowIntensity;
    let glowAlpha = 0.0;
    return mix(glowAlpha, coreAlpha, clamp(glowIntensity, 0.0, 1.0) * occlusionBalance);
}

fn edge_diffusion_fn(gid: vec3<u32>) {
  var coord = vec2<i32>(i32(gid.x), i32(gid.y));
  var dim = textureDimensions(readTexture);
  var uv = vec2<f32>(f32(gid.x), f32(gid.y)) / vec2<f32>(f32(dim.x), f32(dim.y));
  var time = u.config.x;
  
  var center = textureLoad(readTexture, coord, 0).rgb;
  var left = textureLoad(readTexture, coord + vec2<i32>(-1, 0), 0).rgb;
  var right = textureLoad(readTexture, coord + vec2<i32>(1, 0), 0).rgb;
  var top = textureLoad(readTexture, coord + vec2<i32>(0, -1), 0).rgb;
  var bottom = textureLoad(readTexture, coord + vec2<i32>(0, 1), 0).rgb;
  let gx = length(right - left);
  let gy = length(bottom - top);
  var edge = sqrt(gx*gx + gy*gy);
  
  // Mouse as local diffusion amplifier
  let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let dist_to_mouse = distance(uv, mouse_pos);
  if (dist_to_mouse < 0.2) {
    edge *= 1.0 + (1.0 - dist_to_mouse / 0.2) * 2.0;
  }
  
  let light = vec4<f32>(edge * 10.0);
  textureStore(dataTextureA, coord, light);
}

fn diffuse_light_impl(gid: vec3<u32>) {
  var coord = vec2<i32>(i32(gid.x), i32(gid.y));
  var dim = textureDimensions(dataTextureA);
  var uv = vec2<f32>(f32(gid.x), f32(gid.y)) / vec2<f32>(f32(dim.x), f32(dim.y));
  var time = u.config.x;
  
  // Get occlusion balance from params
  let occlusionBalance = u.zoom_params.w;
  
  var center = textureLoad(dataTextureC, coord, 0).r;
  var left = textureLoad(dataTextureC, coord + vec2<i32>(-1,0), 0).r;
  var right = textureLoad(dataTextureC, coord + vec2<i32>(1,0), 0).r;
  var top = textureLoad(dataTextureC, coord + vec2<i32>(0,-1), 0).r;
  var bottom = textureLoad(dataTextureC, coord + vec2<i32>(0,1), 0).r;
  var diffused = (center + left + right + top + bottom) * 0.2;
  
  // Ripples create neon pulses at click positions
  for (var i = 0; i < 50; i++) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let ripple_age = time - ripple.z;
      if (ripple_age > 0.0 && ripple_age < 2.0) {
        let dist_to_ripple = distance(uv, ripple.xy);
        if (dist_to_ripple < 0.1) {
          let pulse = sin(dist_to_ripple * 50.0 - ripple_age * 10.0) * exp(-ripple_age);
          diffused += pulse * 2.0;
        }
      }
    }
  }
  
  // Emission with color shift
  let shift = diffused * 0.1;
  let emission = vec3<f32>(diffused * (1.0 - shift), diffused * (1.0 - abs(shift - 0.5)), diffused * shift) * 3.0;
  
  // Calculate alpha based on emission intensity
  let glowIntensity = length(emission);
  let finalAlpha = calculateEmissiveAlpha(glowIntensity, occlusionBalance);
  
  textureStore(dataTextureB, coord, vec4<f32>(emission, finalAlpha));
  textureStore(writeTexture, vec2<i32>(i32(gid.x), i32(gid.y)), vec4<f32>(emission, finalAlpha));
}

// Main entrypoint for Neon Edge Diffusion
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  diffuse_light_impl(gid);
  let uv = vec2<f32>(gid.xy) / vec2<f32>(textureDimensions(readTexture));
  let depth_in = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth_in, 0.0, 0.0, 0.0));
}

```

## CURRENT SOURCE JSON
```json
{
  "id": "neon-edge-diffusion",
  "name": "Neon Edge Diffusion",
  "url": "shaders/neon-edge-diffusion.wgsl",
  "description": "Sobel edge detection with neon-diffusion and color bleeding.",
  "features": [
    "mouse-driven",
    "audio-reactive",
    "audio-driven"
  ],
  "tags": [
    "filter",
    "image-processing",
    "audio",
    "music"
  ],
  "params": [
    {
      "id": "viscosity",
      "name": "Viscosity",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x",
      "description": "Liquid thickness/resistance"
    },
    {
      "id": "turbulence",
      "name": "Turbulence",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y",
      "description": "Chaotic flow intensity"
    },
    {
      "id": "ripple_strength",
      "name": "Ripple Strength",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z",
      "description": "Wave distortion amount"
    },
    {
      "id": "color_shift",
      "name": "Color Shift",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w",
      "description": "Color manipulation amount"
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
Target: 153 lines max. Prefer dense math over comments. Stop the moment the WGSL fence closes. Nothing after it.
