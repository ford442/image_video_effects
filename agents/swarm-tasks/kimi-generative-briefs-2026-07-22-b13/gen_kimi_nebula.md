# Swarm Brief: gen_kimi_nebula

**Role:** Visualist
**Name:** Kimi Nebula
**Category:** generative
**Description:** Cosmic nebula cloud swirls with ethereal gas formations, twinkling stars, and mouse-driven stellar winds.
**Current lines:** 172
**Target lines:** 222–262 (expand by +50 to +90)

## Role Instructions

You are the Visualist. This nebula's 4 sliders are placeholder param1-4 wired to the generic applyGenerativePrimaryControls boilerplate - none of them touch the actual nebula algorithm. Make them real:
- KILL THE BOILERPLATE (priority 1): replace applyGenerativePrimaryControls with real nebula constants - Intensity -> gas density gain, Speed -> animation time multiplier (currently hard-coded time*0.1), Scale -> noise spatial scale, Detail -> star density threshold (currently hard-coded 0.995). Keep JSON ids/names/defaults EXACTLY as they are (saved-preset contract) - only the WGSL mapping changes.
- Audio layer separation: mids and treble drive drift speeds of different fbm density layers so the cloud strata visibly disaggregate with the music (bass already drives chromatic offset - keep that).
- Extra domain warp: warp noisePos by one additional fbm3 lookup for more turbulent billowing; keep the ACES tonemap and the 0.85 input blend intact.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.

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
  "id": "gen-kimi-nebula",
  "name": "Kimi Nebula",
  "url": "shaders/gen_kimi_nebula.wgsl",
  "description": "Cosmic nebula cloud swirls with ethereal gas formations, twinkling stars, and mouse-driven stellar winds.",
  "features": [
    "aces-tone-map",
    "audio-reactive",
    "chromatic-aberration",
    "cosmic",
    "depth-aware",
    "generative",
    "mouse-driven",
    "procedural",
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
//  Kimi Nebula
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
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


// Kimi Nebula - Cosmic Cloud Swirls
// Ethereal gas clouds with twinkling stars and mouse-driven stellar winds

fn hash3(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise3(p: vec3<f32>) -> f32 {
    var i = floor(p);
    var f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    let n = i.x + i.y * 57.0 + i.z * 113.0;
    var res = mix(mix(mix(hash3(vec3<f32>(n)), hash3(vec3<f32>(n + 1.0)), f.x),
                      mix(hash3(vec3<f32>(n + 57.0)), hash3(vec3<f32>(n + 58.0)), f.x), f.y),
                 mix(mix(hash3(vec3<f32>(n + 113.0)), hash3(vec3<f32>(n + 114.0)), f.x),
                     mix(hash3(vec3<f32>(n + 170.0)), hash3(vec3<f32>(n + 171.0)), f.x), f.y), f.z);
    return res;
}

fn fbm3(p: vec3<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var freq = 1.0;
    for (var i = 0; i < octaves; i++) {
        value += amplitude * noise3(p * freq);
        amplitude *= 0.5;
        freq *= 2.0;
    }
    return value;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x * 0.1;
    let px = vec2<i32>(global_id.xy);
    let bass = plasmaBuffer[0].x;
    
    // Mouse interaction
    var mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    
    // Create swirling nebula effect
    var p = uv * 2.0 - 1.0;
    p.x *= resolution.x / resolution.y;
    
    // Mouse creates stellar wind
    var mousePos = mouse * 2.0 - 1.0;
    mousePos.x *= resolution.x / resolution.y;
    let dist = length(p - mousePos);
    let windStrength = smoothstep(0.8, 0.0, dist) * (0.5 + mouseDown * 0.5);
    
    // Animated 3D noise for gas clouds
    var noisePos = vec3<f32>(p * 1.5, time * 0.2);
    
    // Add swirling motion from mouse
    let angle = windStrength * 2.0;
    let rot = vec2<f32>(
        noisePos.x * cos(angle) - noisePos.y * sin(angle),
        noisePos.x * sin(angle) + noisePos.y * cos(angle)
    );
    noisePos.x = mix(noisePos.x, rot.x, windStrength);
    noisePos.y = mix(noisePos.y, rot.y, windStrength);
    
    // Multi-octave nebula density
    let density1 = fbm3(noisePos, 4);
    let density2 = fbm3(noisePos * 2.0 + vec3<f32>(100.0), 3);
    let density3 = fbm3(noisePos * 4.0 + vec3<f32>(200.0), 2);
    
    let nebulaDensity = density1 * 0.5 + density2 * 0.3 + density3 * 0.2;
    
    // Color palette - deep purples, blues, and pink accents
    let color1 = vec3<f32>(0.1, 0.05, 0.2);  // Deep purple
    let color2 = vec3<f32>(0.2, 0.1, 0.4);   // Purple
    let color3 = vec3<f32>(0.4, 0.2, 0.6);   // Magenta
    let color4 = vec3<f32>(0.8, 0.6, 0.9);   // Pink highlight
    let color5 = vec3<f32>(0.1, 0.3, 0.5);   // Blue
    
    var color = color1;
    color = mix(color, color2, smoothstep(0.2, 0.4, nebulaDensity));
    color = mix(color, color3, smoothstep(0.4, 0.6, nebulaDensity));
    color = mix(color, color4, smoothstep(0.7, 0.9, nebulaDensity + windStrength * 0.3));
    color = mix(color, color5, smoothstep(0.5, 0.8, density3));
    
    // Add stars
    let starNoise = hash3(vec3<f32>(floor(p * 100.0), time * 0.01));
    let star = select(0.0, 1.0, starNoise > 0.995 && nebulaDensity < 0.6);
    
    // Twinkling stars near mouse
    let starTwinkle = sin(time * 5.0 + starNoise * 10.0) * 0.5 + 0.5;
    color += vec3<f32>(star) * (0.5 + starTwinkle * 0.5) * (1.0 + windStrength);
    
    // Bright core near mouse
    color += vec3<f32>(0.6, 0.8, 1.0) * windStrength * 0.5;
    
    // Gamma correction and intensity
    color = pow(color, vec3<f32>(0.8)) * 1.2;
    
    // ═══ SAMPLE INPUT FROM PREVIOUS LAYER ═══
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // Opacity control
    let opacity = 0.85;
    
    // ═══ BLEND WITH INPUT ═══
    let finalColor = mix(inputColor.rgb, color, opacity);
    let finalAlpha = max(inputColor.a, opacity);
    
    // Store for feedback
    let caStr = 0.003 * (1.0 + bass) + inputDepth * 0.001;
    let chromaticColor = vec3<f32>(finalColor.r + caStr, finalColor.g, finalColor.b - caStr * 0.5);
    let acesColor = acesToneMap(chromaticColor * 1.1);

    textureStore(writeTexture, px, applyGenerativePrimaryControls(vec4<f32>(acesColor, finalAlpha)));
    textureStore(dataTextureA, px, vec4<f32>(acesColor, nebulaDensity));
    textureStore(writeDepthTexture, px, vec4<f32>(inputDepth, 0.0, 0.0, 0.0));
}
```
