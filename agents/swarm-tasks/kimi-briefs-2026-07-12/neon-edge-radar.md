# KIMI SWARM TASK — UPGRADE — neon-edge-radar

## Role Assignment
**Primary Agent:** Visualist  
**Domain:** color science, lighting, atmospheric/emotional impact

## Shader Identity
- **ID:** `neon-edge-radar`
- **Name:** Neon Edge Radar
- **Category:** interactive-mouse
- **Current lines:** 98
- **Target lines:** 138 (max)
- **Current description:** A rotating radar scanner that highlights edges in neon colors as it passes, centered on the mouse.

## Creative Brief
Upgrade `neon-edge-radar` while preserving its original visual soul. The visualist should make the shader feel more sophisticated, reactive, and compositing-friendly without turning it into a different effect. Inject at least two modern techniques (FBM domain warp, curl noise, ACES tone mapping, semantic alpha, depth-aware compositing, audio envelope, IGN dither, etc.).

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
//  Neon Edge Radar
//  Category: interactive-mouse
//  Features: advanced-alpha, radar-sweep, edge-detection, mouse-driven, audio-reactive
//  Complexity: Medium
//  Upgraded: 2026-05-23
//  upgraded-rgba
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
  zoom_params: vec4<f32>,  // x=EdgeThreshold, y=RadarSpeed, z=SweepWidth, w=Intensity
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

// ═══ ADVANCED ALPHA FUNCTIONS ═══

// Mode 2: Edge-Preserve Alpha
fn edgePreserveAlpha(uv: vec2<f32>, pixelSize: vec2<f32>, edgeThreshold: f32) -> f32 {
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let dR = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(pixelSize.x, 0.0), 0.0).r;
    let dL = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(pixelSize.x, 0.0), 0.0).r;
    let dU = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, pixelSize.y), 0.0).r;
    let dD = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, pixelSize.y), 0.0).r;
    let depthEdge = length(vec2<f32>(dR - dL, dU - dD));
    let edgeMask = smoothstep(edgeThreshold * 0.5, edgeThreshold, depthEdge);
    return mix(0.2, 1.0, edgeMask);
}

// Mode 5: Effect Intensity Alpha
fn effectIntensityAlpha(intensity: f32, falloff: f32) -> f32 {
    return mix(0.3, 1.0, intensity * falloff);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let pixelSize = 1.0 / resolution;
    let time = u.config.x;
    let audioBass = plasmaBuffer[0].x;
    let audioReactivity = 1.0 + audioBass * 0.5;

    let edgeThreshold = u.zoom_params.x * 0.1 + 0.02;
    let radarSpeed = u.zoom_params.y * 2.0 * audioReactivity;
    let sweepWidth = u.zoom_params.z * 0.3;
    let intensity = u.zoom_params.w * 2.0;

    // Radar centered on mouse — drag the radar around
    let mouse = u.zoom_config.yz;
    let centered = uv - mix(vec2<f32>(0.5), mouse, 0.6);
    let angle = atan2(centered.y, centered.x);
    let sweepAngle = fract(time * radarSpeed) * TAU - PI;
    let angleDiff = abs(angle - sweepAngle);
    let sweep = exp(-angleDiff * angleDiff / (sweepWidth * sweepWidth));
    
    let baseAlpha = textureSampleLevel(readTexture, u_sampler, uv, 0.0).a;
    
    // Edge detection
    let l = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(pixelSize.x, 0.0), 0.0).rgb;
    let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(pixelSize.x, 0.0), 0.0).rgb;
    let edge = length(r - l);
    
    // Neon color
    let neonColor = vec3<f32>(0.0, 1.0, 0.5);
    let emission = neonColor * edge * sweep * intensity;
    
    let edgeAlpha = edgePreserveAlpha(uv, pixelSize, edgeThreshold);
    let effectAlpha = effectIntensityAlpha(sweep * edge, intensity);
    let alpha = clamp(edgeAlpha * effectAlpha, 0.0, 1.0);
    let finalAlpha = mix(baseAlpha, 1.0, sweep * edge * intensity * 0.7);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(emission, finalAlpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(emission, finalAlpha));
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}

```

## CURRENT SOURCE JSON
```json
{
  "id": "neon-edge-radar",
  "name": "Neon Edge Radar",
  "url": "shaders/neon-edge-radar.wgsl",
  "description": "A rotating radar scanner that highlights edges in neon colors as it passes, centered on the mouse.",
  "params": [
    {
      "id": "speed",
      "name": "Beam Speed",
      "default": 1,
      "min": 0.1,
      "max": 5
    },
    {
      "id": "width",
      "name": "Beam Width",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "threshold",
      "name": "Edge Sensitivity",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "intensity",
      "name": "Neon Intensity",
      "default": 2,
      "min": 0,
      "max": 5
    }
  ],
  "features": [
    "mouse-driven",
    "audio-reactive",
    "audio-driven"
  ],
  "tags": [
    "mouse-driven",
    "interactive",
    "audio",
    "music",
    "reactive"
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

## ROLE TOOLKIT — Visualist
See `agents/prompt-templates/visualist.md` for the full toolkit. Use the canonical snippets from `agents/WGSL_BUILTINS_GENERATIVE.md`.

## LINE BUDGET & FINAL REMINDER
Target: 138 lines max. Prefer dense math over comments. Stop the moment the WGSL fence closes. Nothing after it.
