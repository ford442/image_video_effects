# KIMI SWARM TASK — UPGRADE — complex-exponent-warp

## Role Assignment
**Primary Agent:** Algorithmist  
**Domain:** advanced math, simulation depth, SDF/fractal/noise upgrades

## Shader Identity
- **ID:** `complex-exponent-warp`
- **Name:** Complex Exponent Warp
- **Category:** distortion
- **Current lines:** 112
- **Target lines:** 152 (max)
- **Current description:** Applies a complex domain distortion z -> z^p where p is controlled by mouse position. Creates spirals, fractals, and inversions.

## Creative Brief
Upgrade `complex-exponent-warp` while preserving its original visual soul. The algorithmist should make the shader feel more sophisticated, reactive, and compositing-friendly without turning it into a different effect. Inject at least two modern techniques (FBM domain warp, curl noise, ACES tone mapping, semantic alpha, depth-aware compositing, audio envelope, IGN dither, etc.).

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
//  Complex Exponent Warp
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-05-17
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount/FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn complex_mul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

// z^w = exp(w * ln(z))
// Branchless: guard r=0 via max, never output garbage
fn complex_pow(z: vec2<f32>, w: vec2<f32>) -> vec2<f32> {
    let r     = max(length(z), 0.0001);
    let angle = atan2(z.y, z.x);

    // ln(z) = ln(r) + i*angle
    let ln_z     = vec2<f32>(log(r), angle);
    let exponent = complex_mul(w, ln_z);

    // exp(x + iy) = exp(x) * (cos(y) + i*sin(y))
    let mag = exp(exponent.x);
    return vec2<f32>(mag * cos(exponent.y), mag * sin(exponent.y));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
        return;
    }

    let coord = vec2<i32>(gid.xy);
    let uv    = vec2<f32>(gid.xy) / resolution;
    let time  = u.config.x;

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let aspect = resolution.x / max(resolution.y, 0.001);

    // Center UV on complex plane
    var z = (uv - 0.5) * 2.0;
    z.x *= aspect;

    let scale = mix(1.0, 5.0, u.zoom_params.x);
    z *= scale;

    let mouse = u.zoom_config.yz;

    let w_real = (mouse.x - 0.5) * mix(1.0, 10.0, u.zoom_params.z) + 1.0;
    // Mids add a time-varying imaginary exponent component
    let w_imag = (mouse.y - 0.5) * 6.0 + mids * sin(time) * 0.5;
    let w      = vec2<f32>(w_real, w_imag);

    var result_z = complex_pow(z, w);

    // Bass modulates spiral angle
    let spiral   = u.zoom_params.y * 3.14159265 + bass * 0.3;
    let rotation = vec2<f32>(cos(spiral), sin(spiral));
    result_z     = complex_mul(result_z, rotation);

    // Convert back to UV [0,1]
    result_z.x /= aspect;
    var final_uv = result_z * mix(0.1, 1.0, u.zoom_params.w) + 0.5;
    final_uv     = fract(final_uv);

    // Clamp before sampling (fract already keeps [0,1) but be explicit)
    let final_uv_clamped = clamp(final_uv, vec2<f32>(0.0), vec2<f32>(1.0));

    let sampled = textureSampleLevel(readTexture, u_sampler, final_uv_clamped, 0.0);

    // Alpha: encodes UV distance from center and bass (far-mapped = lower alpha)
    let uvDist    = length(result_z);
    let distAlpha = clamp(1.0 - uvDist * 0.15, 0.0, 1.0);
    let alpha     = clamp(distAlpha * (0.7 + bass * 0.3), 0.0, 1.0);

    let finalColor = vec4<f32>(sampled.rgb, alpha);

    textureStore(writeTexture, coord, finalColor);

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, finalColor);
}

```

## CURRENT SOURCE JSON
```json
{
  "id": "complex-exponent-warp",
  "name": "Complex Exponent Warp",
  "url": "shaders/complex-exponent-warp.wgsl",
  "description": "Applies a complex domain distortion z -> z^p where p is controlled by mouse position. Creates spirals, fractals, and inversions.",
  "features": [
    "mouse-driven",
    "complex-math"
  ],
  "params": [
    {
      "id": "scale",
      "name": "Scale",
      "default": 0.2,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x",
      "description": "Zoom scale into the complex plane"
    },
    {
      "id": "spiral",
      "name": "Spiral Rotation",
      "default": 0,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y",
      "description": "Additional spiral rotation amount"
    },
    {
      "id": "exponent_spread",
      "name": "Exponent Spread",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z",
      "description": "Spread of the complex exponent from mouse position"
    },
    {
      "id": "uv_warp",
      "name": "UV Warp Scale",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w",
      "description": "Scale of the UV warp output"
    }
  ],
  "tags": [
    "warp",
    "distort",
    "transform"
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

## ROLE TOOLKIT — Algorithmist
See `agents/prompt-templates/algorithmist.md` for the full toolkit. Use the canonical snippets from `agents/WGSL_BUILTINS_GENERATIVE.md`.

## LINE BUDGET & FINAL REMINDER
Target: 152 lines max. Prefer dense math over comments. Stop the moment the WGSL fence closes. Nothing after it.
