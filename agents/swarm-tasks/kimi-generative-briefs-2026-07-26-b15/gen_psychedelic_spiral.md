# Swarm Brief: gen_psychedelic_spiral

**Role:** Visualist
**Name:** Superformula Spirograph Spiral
**Category:** generative
**Description:** Superformula-driven spirograph spiral with nested epicycles, audio-reactive petal modulation, mouse-centered orbit drift, and temporal feedback warping.
**Current lines:** 142
**Target lines:** 192–232 (expand by +50 to +90)

## Role Instructions

You are the Visualist. This superformula spirograph is already solid - give it individual spectral voices and a sense of touch:
- Per-bin superformula modulation: drive the superformula exponents (n2/n3) from individual FFT bins `plasmaBuffer[1..k]` (e.g. n2 from a low bin, n3 from a high bin) instead of only the band averages, so the petal morphology visibly follows the spectrum.
- Click petal bursts: loop the ripples[] uniform (guard with `min(u32(u.config.y), 50u)`) and add each live ripple as a decaying radial impulse to shapeRadius - clicks detonate a temporary petal-burst ring.
- IQ cosine palette: replace the hsv2rgb call with an IQ cosine palette for cheaper, smoother chroma, and add a hue-preserving clamp at ~1.2 on the color before the feedback write to future-proof the history loop (value can reach ~2.6 today).
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the dataTextureC feedback historyUV transform chain (rotate -> scale by `0.985 - feedback*0.08` -> aspect un-correct -> `+0.5+mouseOffset*0.15`) VERBATIM - it is the warp signature. dataTextureC is engine-owned: sampled, never written by this shader. dataTextureA carries display color here (not sim state).

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
  "id": "gen-psychedelic-spiral",
  "name": "Superformula Spirograph Spiral",
  "url": "shaders/gen_psychedelic_spiral.wgsl",
  "description": "Superformula-driven spirograph spiral with nested epicycles, audio-reactive petal modulation, mouse-centered orbit drift, and temporal feedback warping.",
  "features": [
    "mouse-driven",
    "audio-reactive",
    "audio-driven",
    "temporal",
    "chromatic",
    "depth-aware",
    "spirograph",
    "superformula"
  ],
  "tags": [
    "procedural",
    "generative",
    "audio",
    "music",
    "reactive",
    "spirograph",
    "spiral",
    "fractal-floral"
  ],
  "params": [
    {
      "id": "intensity",
      "name": "Orbit Intensity",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x"
    },
    {
      "id": "spin",
      "name": "Spin Speed",
      "default": 0.45,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y"
    },
    {
      "id": "petals",
      "name": "Petal Count",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z"
    },
    {
      "id": "feedback",
      "name": "Feedback Warp",
      "default": 0.45,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w"
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Orbit Intensity",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Spin Speed",
      "default": 0.45,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Petal Count",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Feedback Warp",
      "default": 0.45,
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
//  Superformula Spirograph Spiral
//  Category: generative
//  Features: mouse-driven, audio-reactive, temporal, chromatic, depth-aware, spirograph,
//            superformula, feedback-warp
//  Complexity: High
//  Upgraded: 2026-05-31
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

const TAU: f32 = 6.283185307179586;

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
  return c.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

fn superformula(phi: f32, m: f32, n1: f32, n2: f32, n3: f32) -> f32 {
    let t1 = pow(abs(cos(m * phi * 0.25)), n2);
    let t2 = pow(abs(sin(m * phi * 0.25)), n3);
    return pow(max(t1 + t2, 0.0001), -1.0 / max(n1, 0.0001));
}

fn spiroCenter(phi: f32, time: f32, speed: f32, intensity: f32, bass: f32) -> vec2<f32> {
    var center = vec2<f32>(0.0);
    var radius = mix(0.22, 0.36, intensity);
    for (var i: i32 = 0; i < 4; i = i + 1) {
        let harmonic = f32(i + 1);
        let a = phi * harmonic + time * speed * (0.9 + harmonic * 0.35) * (1.0 + bass * 0.25);
        center = center + vec2<f32>(cos(a), sin(a)) * radius;
        radius = radius * 0.52;
    }
    return center;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let intensity = mix(0.2, 1.35, u.zoom_params.x);
    let spinSpeed = mix(0.2, 2.8, u.zoom_params.y);
    let petalCount = mix(3.0, 12.0, u.zoom_params.z);
    let feedback = u.zoom_params.w;

    let aspect = resolution.x / max(resolution.y, 1.0);
    var p = uv - 0.5;
    p.x = p.x * aspect;

    let mouseOffset = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0);
    p = p - mouseOffset * 0.55;

    let orbit = spiroCenter(atan2(p.y, p.x) + length(p) * 6.0, time, spinSpeed, intensity, bass);
    let q = p - orbit * mix(0.08, 0.22, intensity);
    let dist = length(q);
    let angle = atan2(q.y, q.x);

    let n1 = mix(0.25, 1.4, 0.5 + 0.5 * sin(time * 0.2 + mids * 2.0));
    let n2 = 1.2 + intensity * 4.5;
    let n3 = 1.0 + treble * 7.0;
    let superR = superformula(angle + time * spinSpeed * 0.18, petalCount + bass * 4.0, n1, n2, n3);
    let shapeRadius = superR * mix(0.12, 0.42, intensity);

    let band = smoothstep(0.08, 0.0, abs(dist - shapeRadius));
    let spokes = 0.5 + 0.5 * cos(angle * (petalCount * 2.0) - dist * 28.0 + time * spinSpeed * 4.0);
    let swirl = 0.5 + 0.5 * sin(length(p) * 24.0 - angle * (petalCount * 1.5) - time * spinSpeed * 3.0);
    let halo = smoothstep(0.35, 0.0, abs(dist - shapeRadius * 1.18));
    let pattern = band * (0.6 + 0.4 * spokes) + pow(swirl, 3.0) * 0.25 + halo * 0.18;

    let hue = fract(angle / TAU + time * 0.12 * spinSpeed + spokes * 0.18 + length(p) * 0.2 + mids * 0.1);
    let saturation = clamp(0.72 + treble * 0.18, 0.0, 1.0);
    let value = pattern * mix(0.85, 2.6, intensity);
    var color = hsv2rgb(vec3<f32>(hue, saturation, value));

    let rot = 0.015 + spinSpeed * 0.01;
    let c = cos(rot);
    let s = sin(rot);
    var historyP = vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);
    historyP = historyP * (0.985 - feedback * 0.08);
    var historyUV = historyP;
    historyUV.x = historyUV.x / aspect;
    historyUV = historyUV + 0.5 + mouseOffset * 0.15;

    // Chromatic temporal feedback: per-channel offset sampling
    let prevR = textureSampleLevel(dataTextureC, u_sampler, historyUV + vec2<f32>(bass * 0.008, 0.0), 0.0).r;
    let prevG = textureSampleLevel(dataTextureC, u_sampler, historyUV + vec2<f32>(0.0, mids * 0.006), 0.0).g;
    let prevB = textureSampleLevel(dataTextureC, u_sampler, historyUV - vec2<f32>(treble * 0.005, 0.0), 0.0).b;
    let chromaticPrev = vec3<f32>(prevR, prevG, prevB);
    let feedbackMix = mix(0.12, 0.78, feedback);
    color = mix(color, chromaticPrev, feedbackMix * (0.42 + band * 0.28));

    // Standard temporal feedback blend
    let prevStandard = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    color = mix(color, prevStandard.rgb * 0.9, 0.03 + bass * 0.01);

    // Chromatic dispersion: per-channel audio boosts
    color.r *= 1.0 + bass * 0.1;
    color.g *= 1.0 + mids * 0.08;
    color.b *= 1.0 + treble * 0.1;

    let edgeFade = 1.0 - smoothstep(0.35, 0.82, length(p));
    let presence = clamp(pattern * edgeFade, 0.0, 1.0);
    let finalColor = mix(inputColor.rgb, color, presence * 0.9);
    let finalAlpha = max(inputColor.a, presence * 0.9);
    let finalDepth = mix(inputDepth, clamp(shapeRadius + halo * 0.25, 0.0, 1.0), presence * 0.85);

    textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(color, presence));
}
```
