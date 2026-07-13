# KIMI SWARM TASK — UPGRADE — mouse-ink-bleed

## Role Assignment
**Primary Agent:** Interactivist  
**Domain:** mouse/audio/video/depth reactivity, feedback loops, emergent behavior

## Shader Identity
- **ID:** `mouse-ink-bleed`
- **Name:** Mouse Ink Bleed
- **Category:** interactive-mouse
- **Current lines:** 96
- **Target lines:** 136 (max)
- **Current description:** Organic ink that bleeds and diffuses outward from the mouse position with turbulent, painterly motion. Audio adds life to the spread and color.

## Creative Brief
Upgrade `mouse-ink-bleed` while preserving its original visual soul. The interactivist should make the shader feel more sophisticated, reactive, and compositing-friendly without turning it into a different effect. Inject at least two modern techniques (FBM domain warp, curl noise, ACES tone mapping, semantic alpha, depth-aware compositing, audio envelope, IGN dither, etc.).

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
//  Mouse Ink Bleed
//  Category: interactive-mouse
//  Features: mouse-driven, ink-diffusion, organic, audio-reactive, semantic-alpha
//  Complexity: Medium
//  Created: 2026-05-30
//  Updated: 2026-06-28
//  By: Kimi Agent (integrated + upgraded)
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

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let mouse = u.zoom_config.yz;
    let isPress = u.zoom_config.w;

    let spread = mix(0.01, 0.5, clamp(u.zoom_params.x, 0.0, 1.0));
    let turbulence = clamp(u.zoom_params.y, 0.0, 1.0);
    let decay = clamp(u.zoom_params.z, 0.0, 1.0);
    let colorIntensity = clamp(u.zoom_params.w, 0.0, 1.0);

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    let dist = length(uv - mouse);
    let activeBrush = smoothstep(spread * 0.6, spread * 0.08, dist) * (0.6 + isPress * 1.2);

    let inkRadius = activeBrush * (0.7 + bass * 0.5);

    // Turbulent displacement for organic bleed
    let turb = turbulence * (1.0 + treble * 0.6);
    let gradX = noise(uv * turb * 6.0 + vec2<f32>(0.01, 0.0)) - noise(uv * turb * 6.0 - vec2<f32>(0.01, 0.0));
    let gradY = noise(uv * turb * 6.0 + vec2<f32>(0.0, 0.01)) - noise(uv * turb * 6.0 - vec2<f32>(0.0, 0.01));
    let displacement = vec2<f32>(gradX, gradY) * inkRadius * spread * 2.0;

    let displacedUV = clamp(uv + displacement, vec2<f32>(0.0), vec2<f32>(1.0));
    var color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

    let luminance = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let inkColor = mix(vec3<f32>(luminance), color * vec3<f32>(0.3, 0.25, 0.35), 0.3);
    color = mix(color, inkColor, inkRadius * colorIntensity);

    let edgeGlow = smoothstep(0.1, 0.6, inkRadius) * (1.0 - smoothstep(0.4, 0.9, inkRadius));
    color += vec3<f32>(0.05, 0.02, 0.08) * edgeGlow * colorIntensity * (0.8 + mids * 0.4);

    // Semantic alpha - preserve input alpha and strengthen where the ink is actively bleeding
    let effect = inkRadius * 0.7 + edgeGlow * 0.5;
    let semantic_alpha = clamp(baseColor.a * (0.5 + effect * 0.6), 0.0, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, semantic_alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

```

## CURRENT SOURCE JSON
```json
{
  "id": "mouse-ink-bleed",
  "name": "Mouse Ink Bleed",
  "url": "shaders/mouse-ink-bleed.wgsl",
  "category": "interactive-mouse",
  "description": "Organic ink that bleeds and diffuses outward from the mouse position with turbulent, painterly motion. Audio adds life to the spread and color.",
  "tags": [
    "ink",
    "bleed",
    "paint",
    "organic",
    "diffusion",
    "artistic",
    "mouse-driven",
    "audio-reactive"
  ],
  "features": [
    "mouse-driven",
    "audio-reactive",
    "semantic-alpha"
  ],
  "params": [
    {
      "id": "spread",
      "name": "Spread Radius",
      "default": 0.55,
      "min": 0.1,
      "max": 1.0,
      "step": 0.01,
      "param": "zoom_params.x"
    },
    {
      "id": "turbulence",
      "name": "Turbulence",
      "default": 0.6,
      "min": 0.0,
      "max": 1.4,
      "step": 0.01,
      "param": "zoom_params.y"
    },
    {
      "id": "decay",
      "name": "Edge Softness",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01,
      "param": "zoom_params.z"
    },
    {
      "id": "colorIntensity",
      "name": "Color Intensity",
      "default": 0.7,
      "min": 0.0,
      "max": 1.5,
      "step": 0.01,
      "param": "zoom_params.w"
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

## ROLE TOOLKIT — Interactivist
See `agents/prompt-templates/interactivist.md` for the full toolkit. Use the canonical snippets from `agents/WGSL_BUILTINS_GENERATIVE.md`.

## LINE BUDGET & FINAL REMINDER
Target: 136 lines max. Prefer dense math over comments. Stop the moment the WGSL fence closes. Nothing after it.
