# KIMI SWARM TASK — UPGRADE — thermal-vision

## Role Assignment
**Primary Agent:** Visualist  
**Domain:** color science, lighting, atmospheric/emotional impact

## Shader Identity
- **ID:** `thermal-vision`
- **Name:** Thermal Vision
- **Category:** artistic
- **Current lines:** 112
- **Target lines:** 152 (max)
- **Current description:** Heat signature camera view.

## Creative Brief
Upgrade `thermal-vision` while preserving its original visual soul. The visualist should make the shader feel more sophisticated, reactive, and compositing-friendly without turning it into a different effect. Inject at least two modern techniques (FBM domain warp, curl noise, ACES tone mapping, semantic alpha, depth-aware compositing, audio envelope, IGN dither, etc.).

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
//  Thermal Vision
//  Category: visual-effects
//  Features: thermal, vision, heat, audio-heat, depth-gradient, atmospheric-haze, pulse-glow
//  Complexity: Medium
//  Updated: 2026-05-31
//  By: Grok (visual flourish — richer heat gradients, audio-reactive pulsing, volumetric haze)
// ═══════════════════════════════════════════════════════════════════
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
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash(i);
    let b = hash(i + vec2<f32>(1.0, 0.0));
    let c = hash(i + vec2<f32>(0.0, 1.0));
    let d = hash(i + vec2<f32>(1.0, 1.0));
    let u2 = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u2.x), mix(c, d, u2.x), u2.y);
}

fn thermal_gradient(t: f32) -> vec3<f32> {
    let c0 = mix(vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(0.0, 0.0, 1.0), clamp(t * 5.0, 0.0, 1.0));
    let c1 = mix(vec3<f32>(0.0, 0.0, 1.0), vec3<f32>(1.0, 0.0, 1.0), clamp((t - 0.2) * 5.0, 0.0, 1.0));
    let c2 = mix(vec3<f32>(1.0, 0.0, 1.0), vec3<f32>(1.0, 0.0, 0.0), clamp((t - 0.4) * 5.0, 0.0, 1.0));
    let c3 = mix(vec3<f32>(1.0, 0.0, 0.0), vec3<f32>(1.0, 1.0, 0.0), clamp((t - 0.6) * 5.0, 0.0, 1.0));
    let c4 = mix(vec3<f32>(1.0, 1.0, 0.0), vec3<f32>(1.0, 1.0, 1.0), clamp((t - 0.8) * 5.0, 0.0, 1.0));

    var color = c0;
    color = mix(color, c1, step(0.2, t));
    color = mix(color, c2, step(0.4, t));
    color = mix(color, c3, step(0.6, t));
    color = mix(color, c4, step(0.8, t));
    return color;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let texel = vec2<f32>(1.0 / resolution.x, 1.0 / resolution.y);
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    // Grok visual flourish: Richer heat color gradient + audio pulse
    let heatPulse = 1.0 + bass * 0.4 + treble * 0.3;

    let heatSensitivity = mix(0.5, 3.0, u.zoom_params.x) * (1.0 + bass * 0.2);
    let colorRange = u.zoom_params.y;
    let sensorNoise = u.zoom_params.z * (1.0 + mids * 0.25);
    let thermalBlur = u.zoom_params.w;

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(baseColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let blurredLuma = mix(
        luma,
        (
            luma +
            dot(textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(texel.x, 0.0), vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999)), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114)) +
            dot(textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(texel.x, 0.0), vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999)), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114)) +
            dot(textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, texel.y), vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999)), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114)) +
            dot(textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(0.0, texel.y), vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999)), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114))
        ) / 5.0,
        thermalBlur
    );
    let driftSpeed = 0.6 + treble * 1.6;
    let n = noise(uv * resolution.xy * 0.04 + vec2<f32>(time * driftSpeed, -time * driftSpeed * 0.6));
    let heat = clamp((blurredLuma + (n - 0.5) * sensorNoise) * heatSensitivity, 0.0, 1.0);
    let thermalColor = thermal_gradient(pow(heat, mix(1.5, 0.55, colorRange)));
    let hotspot = smoothstep(0.75, 1.0, heat) * (0.15 + treble * 0.1);
    let finalColor = mix(baseColor.rgb * 0.25, thermalColor, 0.85) + vec3<f32>(hotspot);
    let alpha = clamp(baseColor.a * 0.4 + heat * 0.35 + bass * 0.05, 0.08, 1.0);
    let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r + heat * 0.04, 0.0, 1.0);
    let finalPixel = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalPixel);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalPixel);
}

```

## CURRENT SOURCE JSON
```json
{
  "id": "thermal-vision",
  "name": "Thermal Vision",
  "url": "shaders/thermal-vision.wgsl",
  "description": "Heat signature camera view.",
  "params": [
    {
      "id": "sensitivity",
      "name": "Heat Sensitivity",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "color_range",
      "name": "Color Range",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "noise",
      "name": "Sensor Noise",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "blur",
      "name": "Thermal Blur",
      "default": 0.5,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
    "color-remap",
    "mouse-driven"
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

## ROLE TOOLKIT — Visualist
See `agents/prompt-templates/visualist.md` for the full toolkit. Use the canonical snippets from `agents/WGSL_BUILTINS_GENERATIVE.md`.

## LINE BUDGET & FINAL REMINDER
Target: 152 lines max. Prefer dense math over comments. Stop the moment the WGSL fence closes. Nothing after it.
