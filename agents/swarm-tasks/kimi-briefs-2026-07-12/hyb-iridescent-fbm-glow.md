# KIMI SWARM TASK — UPGRADE — hyb-iridescent-fbm-glow

## Role Assignment
**Primary Agent:** Visualist  
**Domain:** color science, lighting, atmospheric/emotional impact

## Shader Identity
- **ID:** `hyb-iridescent-fbm-glow`
- **Name:** Iridescent FBM Glow
- **Category:** hybrid
- **Current lines:** 106
- **Target lines:** 146 (max)
- **Current description:** Domain-warped FBM drives a thin-film iridescent glow layer that is blended over the input image while preserving alpha.

## Creative Brief
Upgrade `hyb-iridescent-fbm-glow` while preserving its original visual soul. The visualist should make the shader feel more sophisticated, reactive, and compositing-friendly without turning it into a different effect. Inject at least two modern techniques (FBM domain warp, curl noise, ACES tone mapping, semantic alpha, depth-aware compositing, audio envelope, IGN dither, etc.).

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
//  hyb-iridescent-fbm-glow
//  Category: hybrid
//  Features: fbm-noise, iridescence, image-glow, alpha-passthrough, depth-passthrough
//  Chunks: fbm2 + iridescence
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

// ── Chunk: hash12 (from gen_grid.wgsl) ──
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ── Chunk: valueNoise (from gen_grid.wgsl) ──
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let a = hash12(i + vec2<f32>(0.0, 0.0));
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// ── Chunk: fbm2 (from gen_grid.wgsl) ──
fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value = value + amplitude * valueNoise(p * frequency);
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.0;
    }
    return value;
}

// ── Chunk: iridescence (from gen-holographic-fracture.wgsl) ──
fn iridescence(theta: f32, shift: f32) -> vec3<f32> {
    let t = theta * 4.0 + shift;
    return 0.5 + 0.5 * cos(vec3<f32>(t, t + 2.094, t + 4.189));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let coord = vec2<i32>(gid.xy);
    let dimsI = vec2<i32>(dims);

    if (any(coord >= dimsI)) {
        return;
    }

    let uv = (vec2<f32>(coord) + 0.5) / vec2<f32>(dims);
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Normalize zoom_params
    let time = u.config.x;
    let fbmScale = mix(1.5, 18.0, clamp(u.zoom_params.x, 0.0, 1.0));
    let octaves = i32(mix(2.0, 7.0, clamp(u.zoom_params.y, 0.0, 1.0)));
    let shiftSpeed = mix(0.0, 3.0, clamp(u.zoom_params.z, 0.0, 1.0));
    let glowMix = mix(0.0, 1.0, clamp(u.zoom_params.w, 0.0, 1.0));

    // Animated FBM layer
    let q = vec2<f32>(
        fbm2(uv * fbmScale + vec2<f32>(time * 0.07, 0.0), octaves),
        fbm2(uv * fbmScale + vec2<f32>(5.2, 1.3 + time * 0.07), octaves)
    );
    let warped = uv * fbmScale + 4.0 * q + vec2<f32>(time * 0.05);
    let noise = fbm2(warped, octaves);

    // Iridescent glow layer
    let ird = iridescence(noise, time * shiftSpeed);
    let glowLayer = ird * noise * noise;

    // Blend glow over input, preserving luminance relationship
    let outRGB = mix(src.rgb, src.rgb + glowLayer, glowMix);

    textureStore(writeTexture, coord, vec4<f32>(outRGB, src.a));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

```

## CURRENT SOURCE JSON
```json
{
  "id": "hyb-iridescent-fbm-glow",
  "name": "Iridescent FBM Glow",
  "category": "hybrid",
  "type": "compute",
  "url": "shaders/hyb-iridescent-fbm-glow.wgsl",
  "description": "Domain-warped FBM drives a thin-film iridescent glow layer that is blended over the input image while preserving alpha.",
  "features": [
    "hybrid",
    "fbm-noise",
    "iridescence",
    "image-glow",
    "alpha-passthrough",
    "depth-aware",
    "randomization-safe"
  ],
  "tags": [
    "hybrid",
    "fbm",
    "iridescence",
    "glow",
    "noise"
  ],
  "workgroup_size": [
    16,
    16,
    1
  ],
  "params": [
    {
      "id": "fbm_scale",
      "name": "FBM Scale",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x",
      "description": "Scale of the FBM noise domain"
    },
    {
      "id": "fbm_octaves",
      "name": "FBM Octaves",
      "default": 0.6,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y",
      "description": "Number of FBM noise octaves"
    },
    {
      "id": "color_shift_speed",
      "name": "Color Shift Speed",
      "default": 0.35,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z",
      "description": "Speed of the iridescent color cycling"
    },
    {
      "id": "glow_mix",
      "name": "Glow Mix",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w",
      "description": "Blend strength of the iridescent glow over the input"
    }
  ],
  "supportsDepth": true,
  "supportsDof": false,
  "chunks_used": [
    "fbm2 (gen_grid.wgsl)",
    "iridescence (gen-holographic-fracture.wgsl)"
  ],
  "updated": true
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

## ROLE TOOLKIT — Visualist
See `agents/prompt-templates/visualist.md` for the full toolkit. Use the canonical snippets from `agents/WGSL_BUILTINS_GENERATIVE.md`.

## LINE BUDGET & FINAL REMINDER
Target: 146 lines max. Prefer dense math over comments. Stop the moment the WGSL fence closes. Nothing after it.
