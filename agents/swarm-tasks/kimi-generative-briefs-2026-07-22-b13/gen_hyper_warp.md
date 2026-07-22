# Swarm Brief: gen_hyper_warp

**Role:** Optimizer
**Name:** Hyper Warp
**Category:** generative
**Description:** Advanced domain warping with fractal noise and reaction-diffusion feedback.
**Current lines:** 173
**Target lines:** 223–263 (expand by +50 to +90)

## Role Instructions

You are the Optimizer. Same placeholder param1-4 / applyGenerativePrimaryControls boilerplate as kimi_nebula, PLUS a borderline feedback loop. Stabilize first, then wire real controls:
- STABILIZE THE FEEDBACK (priority 1): the dataTextureC loop mixes sharpened history (history*1.1 - 0.05) at 0.95 weight - a slow amplifier held in check only by ACES+clamp. Add an explicit ~1.2 pre-tint clamp on the sharpened history (luma-echo-warp lesson) so it can never blow out.
- KILL THE BOILERPLATE: rewire the 4 sliders to real constants - Intensity -> warp amplitude (q weight), Speed -> time multiplier (currently fixed 0.2), Scale -> palette frequency/hue offset, Detail -> feedback mix (range ~0.85-0.98). Keep JSON ids/names/defaults EXACTLY (saved-preset contract).
- Flow-advected history: offset the dataTextureC sample position slightly by the r warp vector so feedback smears along the liquid flow instead of sharpening a static frame.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the triple domain-warp reaction-diffusion character and the radial burst; do not reduce octave counts. This shader's charm is the specific warp weights.

## Required Output Format

- Return exactly one fenced WGSL block (` ```wgsl ` ... ` ``` `).
- No prose before or after the fence.
- Preserve the canonical 13-binding compute layout:
  - @binding(0) sampler, (1) readTexture, (2) writeTexture, (3) Uniforms, (4) readDepthTexture, (5) non_filtering_sampler, (6) writeDepthTexture, (7) dataTextureA, (8) dataTextureB, (9) dataTextureC, (10) extraBuffer (read_write), (11) comparison_sampler, (12) plasmaBuffer (read).
- Workgroup size must be `@workgroup_size(16, 16, 1)`.
- Write to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Use `textureSampleLevel(..., 0.0)` for sampler reads and `textureLoad` for storage reads.
- Do not use WGSL reserved keywords as identifiers (e.g. `target`). Do not add or renumber bindings. Binding 13 (historyTexture) is optional - only declare it if the shader already uses it.
- extraBuffer (if ever used): [0..4] reserved, [5..132] = engine FFT bins - persistent shader state goes in [133..255] ONLY.

## JSON Parameters / Controls

```json
{
  "id": "gen-hyper-warp",
  "name": "Hyper Warp",
  "url": "shaders/gen_hyper_warp.wgsl",
  "description": "Advanced domain warping with fractal noise and reaction-diffusion feedback.",
  "features": [
    "aces-tone-map",
    "audio-reactive",
    "chromatic-aberration",
    "depth-aware",
    "generative",
    "mouse-driven",
    "temporal",
    "upgraded-rgba"
  ],
  "tags": [
    "procedural",
    "generative"
  ],
  "params": [
    {
      "id": "param1",
      "name": "Intensity",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x",
      "description": "Controls the overall strength of the generated effect."
    },
    {
      "id": "param2",
      "name": "Speed",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y",
      "description": "Controls animation and temporal evolution speed."
    },
    {
      "id": "param3",
      "name": "Scale",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z",
      "description": "Controls spatial scale, frequency, or detail contrast."
    },
    {
      "id": "param4",
      "name": "Detail",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w",
      "description": "Controls mouse-driven or secondary variation influence."
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Intensity",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Speed",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Scale",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Detail",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    }
  ],
  "updated": true
}
```

## Current WGSL Code

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  Hyper Warp
//  Category: generative
//  Features: generative, audio-reactive, mouse-driven, temporal, depth-aware,
//            upgraded-rgba, aces-tone-map, chromatic-aberration
//  Complexity: High
//  Created: 2026-05-30
//  Upgraded: 2026-06-06
// ═══════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(7) var dataTextureA : texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC : texture_2d<f32>;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,              // time, rippleCount, resolutionX, resolutionY
  zoom_config: vec4<f32>,         // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn applyGenerativePrimaryControls(color: vec4<f32>) -> vec4<f32> {
  let primaryIntensity = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
  let speedPulse = 0.92 + 0.16 * (0.5 + 0.5 * sin(u.config.x * mix(0.25, 5.0, clamp(u.zoom_params.y, 0.0, 1.0))));
  let detailContrast = mix(0.75, 1.6, clamp(u.zoom_params.z, 0.0, 1.0));
  let mouseDistance = length(u.zoom_config.yz - vec2<f32>(0.5));
  let mouseInfluence = mix(0.95, 1.15, clamp(u.zoom_params.w * mouseDistance * 2.0, 0.0, 1.0));
  let controlled = pow(max(color.rgb * primaryIntensity * speedPulse * mouseInfluence, vec3<f32>(0.0)), vec3<f32>(1.0 / detailContrast));
  return vec4<f32>(controlled, color.a);
}


// Psychedelic Hyper-Warp
// Advanced WGSL shader with domain warping, fractal noise, and reaction-diffusion feedback.

// 2D random function for noise generation
fn rand(co: vec2<f32>) -> f32 {
    return fract(sin(dot(co, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// 2D noise function
fn noise(p: vec2<f32>) -> f32 {
    var i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    let a = rand(i);
    let b = rand(i + vec2<f32>(1.0, 0.0));
    let c = rand(i + vec2<f32>(0.0, 1.0));
    let d = rand(i + vec2<f32>(1.0, 1.0));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Fractal Brownian Motion (fBm) for detailed patterns
fn fbm(p: vec2<f32>, octaves: i32, persistence: f32) -> f32 {
    var total = 0.0;
    var frequency = 1.0;
    var amplitude = 1.0;
    var maxValue = 0.0;
    for (var i = 0; i < octaves; i++) {
        total += noise(p * frequency) * amplitude;
        maxValue += amplitude;
        amplitude *= persistence;
        frequency *= 2.0;
    }
    return total / maxValue;
}

// Function to create a vibrant color palette
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x * 0.2;
    let px = vec2<i32>(global_id.xy);
    let bass = plasmaBuffer[0].x;

    // --- Feedback and Coordinates ---
    // Sample current pixel for feedback effect
    let history = textureLoad(dataTextureC, px, 0).rgb;

    let aspect = resolution.x / resolution.y;
    var p = uv - 0.5;
    p.x *= aspect;

    // --- Mouse Interaction ---
    var mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z) - 0.5;
    mouse.x *= aspect;
    let mouse_dist = length(p - mouse);
    // Inverted smoothstep logic
    let mouse_warp = pow(1.0 - smoothstep(0.2, 0.0, mouse_dist), 2.0) * u.zoom_config.w;

    // --- Domain Warping ---
    // Warp the coordinate space using multiple layers of fBm for a liquid-like distortion
    var q = vec2<f32>(
        fbm(p + vec2<f32>(0.0, time * 0.4), 3, 0.5),
        fbm(p + vec2<f32>(5.2, time * 0.3), 3, 0.5)
    );
    // Add mouse influence to the domain warp
    let warp_dir = normalize(p - mouse);
    // Only apply if mouse_warp has value
    if (length(warp_dir) > 0.001) {
         q += mouse_warp * warp_dir * 0.5;
    }

    var r = vec2<f32>(
        fbm(p + q * 2.0 + vec2<f32>(1.7, 9.2) + 0.1 * time, 4, 0.6),
        fbm(p + q * 2.0 + vec2<f32>(8.3, 2.8) + 0.1 * time, 4, 0.6)
    );

    // --- Final Pattern Generation ---
    // The final value is a mix of warped coordinates and a radial component
    let val = fbm((p + r) * 2.0, 5, 0.5);
    // Inverted smoothstep logic
    let radial_burst = pow(1.0 - smoothstep(0.5, 0.0, length(p)), 2.0);
    let final_val = val + radial_burst * 0.2;

    // --- Advanced Color Mapping ---
    // Blend between two psychedelic palettes based on the pattern value
    let color1 = palette(final_val + time, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(0.0, 0.1, 0.2));
    let color2 = palette(final_val + time, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0, 1.0, 0.5), vec3<f32>(0.8, 0.9, 0.3));
    var color = mix(color1, color2, smoothstep(0.4, 0.6, final_val));

    // Boost brightness and contrast for intensity
    color = pow(color, vec3<f32>(0.8)) * 1.5;

    // ═══ SAMPLE INPUT FROM PREVIOUS LAYER ═══
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // Opacity control
    let opacity = 0.85;

    // --- Feedback and Output ---
    // Reaction-diffusion style feedback: sharpen and blend
    let sharpened_history = clamp(history * 1.1 - 0.05, vec3<f32>(0.0), vec3<f32>(1.0));
    let generatedColor = mix(color, sharpened_history, 0.95);

    // ═══ BLEND WITH INPUT ═══
    let finalColor = mix(inputColor.rgb, generatedColor, opacity);
    let finalAlpha = max(inputColor.a, opacity);

    let caStr = 0.003 * (1.0 + bass) + inputDepth * 0.001;
    let chromaticColor = vec3<f32>(finalColor.r + caStr, finalColor.g, finalColor.b - caStr * 0.5);
    let acesColor = acesToneMap(chromaticColor * 1.1);

    textureStore(writeTexture, vec2<i32>(global_id.xy), applyGenerativePrimaryControls(vec4<f32>(acesColor, finalAlpha)));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(acesColor, finalAlpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(inputDepth, 0.0, 0.0, 0.0));
}
```
