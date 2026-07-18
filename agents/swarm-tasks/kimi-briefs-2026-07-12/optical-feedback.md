# KIMI SWARM TASK — UPGRADE — optical-feedback

## Role Assignment
**Primary Agent:** Interactivist  
**Domain:** mouse/audio/video/depth reactivity, feedback loops, emergent behavior

## Shader Identity
- **ID:** `optical-feedback`
- **Name:** Optical Feedback Loop
- **Category:** interactive-mouse
- **Current lines:** 110
- **Target lines:** 150 (max)
- **Current description:** Infinite video feedback loop centered on the mouse cursor.

## Creative Brief
Upgrade `optical-feedback` while preserving its original visual soul. The interactivist should make the shader feel more sophisticated, reactive, and compositing-friendly without turning it into a different effect. Inject at least two modern techniques (FBM domain warp, curl noise, ACES tone mapping, semantic alpha, depth-aware compositing, audio envelope, IGN dither, etc.).

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
//  Optical Feedback
//  Category: image
//  Features: mouse-driven, temporal-persistence, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-05-23
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=AccumulationRate, y=Zoom, z=Rotation, w=Brightness
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

// ═══ ADVANCED ALPHA FUNCTIONS ═══

// Mode 3: Accumulative Alpha
fn accumulativeAlpha(
    newColor: vec3<f32>,
    newAlpha: f32,
    prevColor: vec3<f32>,
    prevAlpha: f32,
    accumulationRate: f32
) -> vec4<f32> {
    let accumulatedAlpha = prevAlpha * (1.0 - accumulationRate * 0.08) + newAlpha * accumulationRate;
    let totalAlpha = min(accumulatedAlpha, 1.0);
    let blendFactor = select(newAlpha * accumulationRate / totalAlpha, 0.0, totalAlpha < 0.001);
    let color = mix(prevColor, newColor, blendFactor);
    return vec4<f32>(color, totalAlpha);
}

// Mode 4: Volumetric Alpha
fn volumetricAlpha(density: f32, thickness: f32) -> f32 {
    return 1.0 - exp(-density * thickness);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(i32(global_id.x), i32(global_id.y));
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;

    // Mouse-driven feedback center for tactile zoom/rotate
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    let accumulationRate = u.zoom_params.x;
    let zoom = u.zoom_params.y * 0.02 * (1.0 + bass * 0.5);    // bass pumps the zoom
    let rotation = u.zoom_params.z * 0.1 + mouseDown * 0.02 * sin(time * 4.0);
    let brightness = u.zoom_params.w * 2.0;
    
    let current = textureLoad(readTexture, coord, 0);
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    
    // Optical feedback transformation — center on mouse for camera-feedback feel
    let center = mix(vec2<f32>(0.5), mouse, 0.5);
    let centered = uv - center;
    let c = cos(rotation);
    let s = sin(rotation);
    let rotated = vec2<f32>(
        centered.x * c - centered.y * s,
        centered.x * s + centered.y * c
    );
    let scaled = rotated * (1.0 - zoom) + center;
    
    let feedbackSample = textureSampleLevel(dataTextureC, u_sampler, clamp(scaled, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    
    let feedbackColor = feedbackSample.rgb * brightness;
    let newAlpha = volumetricAlpha(length(feedbackColor), 1.0);
    
    let accumulated = accumulativeAlpha(
        feedbackColor,
        newAlpha,
        prev.rgb,
        prev.a,
        accumulationRate
    );
    
    let rgbResult = mix(accumulated.rgb, current.rgb, 0.1);
    let finalAlpha = mix(current.a, 1.0, accumulationRate * 0.7);
    let finalResult = vec4<f32>(rgbResult, finalAlpha);
    
    textureStore(dataTextureA, coord, finalResult);
    textureStore(writeTexture, global_id.xy, finalResult);
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0, 0, 0.0));
}

```

## CURRENT SOURCE JSON
```json
{
  "id": "optical-feedback",
  "name": "Optical Feedback Loop",
  "url": "shaders/optical-feedback.wgsl",
  "description": "Infinite video feedback loop centered on the mouse cursor.",
  "params": [
    {
      "id": "zoom",
      "name": "Feedback Zoom",
      "default": 0.6,
      "min": 0,
      "max": 1
    },
    {
      "id": "rotation",
      "name": "Rotation",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "decay",
      "name": "Decay",
      "default": 0.95,
      "min": 0,
      "max": 1
    },
    {
      "id": "shift",
      "name": "Hue Shift",
      "default": 0.1,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
    "mouse-driven",
    "temporal-persistence"
  ],
  "tags": [
    "filter",
    "image-processing"
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
Target: 150 lines max. Prefer dense math over comments. Stop the moment the WGSL fence closes. Nothing after it.
