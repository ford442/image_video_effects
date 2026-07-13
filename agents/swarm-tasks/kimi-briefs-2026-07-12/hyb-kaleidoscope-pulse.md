# KIMI SWARM TASK — UPGRADE — hyb-kaleidoscope-pulse

## Role Assignment
**Primary Agent:** Algorithmist  
**Domain:** advanced math, simulation depth, SDF/fractal/noise upgrades

## Shader Identity
- **ID:** `hyb-kaleidoscope-pulse`
- **Name:** Kaleidoscope Pulse
- **Category:** hybrid
- **Current lines:** 90
- **Target lines:** 130 (max)
- **Current description:** Mirrors the input image into kaleidoscope segments and adds a reaction-diffusion-style radial pulse at the center, preserving the original alpha.

## Creative Brief
Upgrade `hyb-kaleidoscope-pulse` while preserving its original visual soul. The algorithmist should make the shader feel more sophisticated, reactive, and compositing-friendly without turning it into a different effect. Inject at least two modern techniques (FBM domain warp, curl noise, ACES tone mapping, semantic alpha, depth-aware compositing, audio envelope, IGN dither, etc.).

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
//  hyb-kaleidoscope-pulse
//  Category: hybrid
//  Features: kaleidoscope, radial-pulse, image-remix, alpha-passthrough, depth-passthrough
//  Chunks: kaleidoscope + rdPulse (with glow)
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

// ── Chunk: glow (from anamorphic-flare.wgsl) ──
fn glow(dist: f32, radius: f32, intensity: f32) -> f32 {
    let safeRadius = max(radius, 0.001);
    return exp(-dist * dist / (safeRadius * safeRadius)) * intensity;
}

// ── Chunk: kaleidoscope (from kaleidoscope.wgsl) ──
fn kaleidoscope(uv: vec2<f32>, segments: f32) -> vec2<f32> {
    let safeSegments = max(segments, 1.0);
    let angle = atan2(uv.y, uv.x);
    let radius = length(uv);
    let segmentAngle = 6.28318 / safeSegments;
    let mirroredAngle = abs(fract(angle / segmentAngle + 0.5) - 0.5) * segmentAngle;
    return vec2<f32>(cos(mirroredAngle), sin(mirroredAngle)) * radius;
}

// ── Chunk: rdPulse (from gen-bioelectric-pulse.wgsl) ──
fn rdPulse(p: vec2<f32>, center: vec2<f32>, time: f32, speed: f32, width: f32) -> f32 {
    let d = length(p - center);
    let phase = d * 8.0 - time * speed * 4.0;
    let wave = sin(phase) * 0.5 + 0.5;
    let envelope = exp(-d * d * 2.0) * (1.0 - smoothstep(0.0, 1.5, d));
    return wave * envelope * glow(d, width, 1.0);
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
    let segments = mix(3.0, 16.0, clamp(u.zoom_params.x, 0.0, 1.0));
    let pulseSpeed = mix(0.2, 3.0, clamp(u.zoom_params.y, 0.0, 1.0));
    let pulseWidth = mix(0.05, 0.6, clamp(u.zoom_params.z, 0.0, 1.0));
    let effectMix = mix(0.0, 1.0, clamp(u.zoom_params.w, 0.0, 1.0));

    // Kaleidoscope in centered coordinates
    let centered = uv - 0.5;
    let kUV = kaleidoscope(centered, segments);
    let sampleUV = clamp(kUV + 0.5, vec2<f32>(0.0), vec2<f32>(1.0));
    let kaleido = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // Organic radial pulse overlaid at the kaleidoscope center
    let pulse = rdPulse(centered, vec2<f32>(0.0), time, pulseSpeed, pulseWidth);
    let pulseColor = pulse * vec3<f32>(0.5, 0.85, 1.0);

    let outRGB = mix(kaleido.rgb, kaleido.rgb + pulseColor, effectMix);

    textureStore(writeTexture, coord, vec4<f32>(outRGB, src.a));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

```

## CURRENT SOURCE JSON
```json
{
  "id": "hyb-kaleidoscope-pulse",
  "name": "Kaleidoscope Pulse",
  "category": "hybrid",
  "type": "compute",
  "url": "shaders/hyb-kaleidoscope-pulse.wgsl",
  "description": "Mirrors the input image into kaleidoscope segments and adds a reaction-diffusion-style radial pulse at the center, preserving the original alpha.",
  "features": [
    "hybrid",
    "kaleidoscope",
    "radial-pulse",
    "image-remix",
    "alpha-passthrough",
    "depth-aware",
    "randomization-safe"
  ],
  "tags": [
    "hybrid",
    "kaleidoscope",
    "pulse",
    "radial",
    "mirror"
  ],
  "workgroup_size": [
    16,
    16,
    1
  ],
  "params": [
    {
      "id": "segments",
      "name": "Mirror Segments",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x",
      "description": "Number of kaleidoscope mirror segments"
    },
    {
      "id": "pulse_speed",
      "name": "Pulse Speed",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y",
      "description": "Propagation speed of the radial pulse"
    },
    {
      "id": "pulse_width",
      "name": "Pulse Width",
      "default": 0.35,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z",
      "description": "Width/decay of the radial glow"
    },
    {
      "id": "effect_mix",
      "name": "Effect Mix",
      "default": 0.65,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w",
      "description": "Blend strength of the pulse overlay"
    }
  ],
  "supportsDepth": true,
  "supportsDof": false,
  "chunks_used": [
    "kaleidoscope (kaleidoscope.wgsl)",
    "rdPulse (gen-bioelectric-pulse.wgsl)",
    "glow (anamorphic-flare.wgsl)"
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

## ROLE TOOLKIT — Algorithmist
See `agents/prompt-templates/algorithmist.md` for the full toolkit. Use the canonical snippets from `agents/WGSL_BUILTINS_GENERATIVE.md`.

## LINE BUDGET & FINAL REMINDER
Target: 130 lines max. Prefer dense math over comments. Stop the moment the WGSL fence closes. Nothing after it.
