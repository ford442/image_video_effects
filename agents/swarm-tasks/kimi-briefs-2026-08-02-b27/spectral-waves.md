# Swarm Brief: spectral-waves

**Role:** Visualist
**Name:** Luma Ripple
**Category:** interactive-mouse
**Description:** Luminance-reactive waves ripple out from the mouse cursor, displacing the image with chromatic aberration. Audio bass boosts wave amplitude.
**Current lines:** 116
**Target lines:** 166–206 (expand by +50 to +90)

## Role Instructions

You are the Visualist. This luma ripple's palette/ACES/dither stack is exemplary - but the wave origin snaps to the cursor and clicks never launch a wave. Make the water respond:
- Spring-damper the wave origin (priority 1): ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the ripple epicenter glides; raw mouse stays the spring target. Keep the existing aspect correction (uv_c/mouse_c).
- Click wave trains: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple emits an expanding wave train from its click point (an extra displacement term: sin(distR * frequency * 0.8 - rippleAge * 8.0) * exp(-rippleAge * 1.5) * maxAmplitude * 0.8 in an aspect-corrected falloff, ~2s), composed with the main wave before the chromatic taps, so clicks splash rings.
- Per-ring FFT voices: quantize the radial distance into 8 rings; each ring's crest glow rides its own bin (`plasmaBuffer[(ring % 8u) + 1u].x * 0.35` added into the caustic term), so the spectrum ripples outward spatially. Fix the stale comments (comment-only): config.y = ripple COUNT, zoom_config.w = mouseDown.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the getLuminance/palette/aces/ign helpers, the dual-wave construction (wave + echoWave), the crest smoothsteps, the displacement luma weighting, the 3-tap chromatic aberration with safeDir, the spectral/caustic/bass-glow HDR assembly, the radial vignette, the dither, the alpha formula, and the PREMULTIPLIED finalRGBA output VERBATIM - the tonal stack is hand-tuned. All 4 sliders honestly wired - keep roles EXACTLY. dataTextureA stays display color (premultiplied, same as writeTexture). extraBuffer in [133..255] ONLY.

## Required Output Format

- Return exactly one fenced WGSL block (` ```wgsl ` ... ` ``` `).
- No prose before or after the fence.
- Preserve the canonical 13-binding compute layout:
  - @binding(0) sampler, (1) readTexture, (2) writeTexture, (3) Uniforms, (4) readDepthTexture, (5) non_filtering_sampler, (6) writeDepthTexture, (7) dataTextureA, (8) dataTextureB, (9) dataTextureC, (10) extraBuffer (read_write), (11) comparison_sampler, (12) plasmaBuffer (read).
- Workgroup size must be `@workgroup_size(16, 16, 1)`.
- Write to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Use `textureSampleLevel(..., 0.0)` for sampler reads and `textureLoad` for storage reads.
- Do not use WGSL reserved keywords as identifiers (e.g. `target`). Do not add or renumber bindings. Binding 13 (historyTexture) is optional - only declare it if the shader already uses it.
- extraBuffer (if ever used): [0..4] reserved, [5..132] = engine FFT bins — persistent shader state goes in [133..255] ONLY.
- Engine uniform truth (verified src/renderer/UniformBuffer.ts): config = [time, rippleCount, resW, resH]; zoom_config = [time, mouseX, mouseY, mouseDown]. Guard ripple loops with `min(u32(u.config.y), 50u)`.

## JSON Parameters / Controls

```json
{
  "id": "spectral-waves",
  "name": "Luma Ripple",
  "url": "shaders/spectral-waves.wgsl",
  "description": "Luminance-reactive waves ripple out from the mouse cursor, displacing the image with chromatic aberration. Audio bass boosts wave amplitude.",
  "params": [
    {
      "id": "frequency",
      "name": "Ripple Freq",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "speed",
      "name": "Wave Speed",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "amplitude",
      "name": "Intensity",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "aberration",
      "name": "Chromatic Split",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    }
  ],
  "features": [
    "mouse-driven",
    "audio-reactive",
    "image",
    "upgraded-rgba"
  ],
  "tags": [
    "filter",
    "image-processing",
    "ripple",
    "chromatic",
    "audio-reactive"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Ripple Freq",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Wave Speed",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Intensity",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Chromatic Split",
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
//  Spectral Waves
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, image, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn getLuminance(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

fn palette(t: f32) -> vec3<f32> {
    return vec3<f32>(0.50, 0.49, 0.52) +
           vec3<f32>(0.48, 0.44, 0.42) *
           cos(6.28318 * (vec3<f32>(1.0, 0.82, 0.58) * t + vec3<f32>(0.06, 0.30, 0.54)));
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
    let coords = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(global_id.xy) / u.config.zw;
    let aspect = u.config.z / u.config.w;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let frequency = 10.0 + u.zoom_params.x * 90.0;
    let speed = u.zoom_params.y * 5.0;
    let maxAmplitude = u.zoom_params.z * 0.1 * (1.0 + bass * 0.3 + treble * 0.15);
    let aberration = u.zoom_params.w * 0.05;

    var mousePos = u.zoom_config.yz;

    let uv_c = vec2<f32>(uv.x * aspect, uv.y);
    let mouse_c = vec2<f32>(mousePos.x * aspect, mousePos.y);
    let dist = distance(uv_c, mouse_c);

    let centerColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let luma = getLuminance(centerColor);

    let wave = sin(dist * frequency - time * speed);
    let echoWave = sin(dist * frequency * 0.47 + time * speed * 0.72 + bass * 3.0);
    let crest = smoothstep(0.58, 1.0, wave) + smoothstep(0.74, 1.0, echoWave) * 0.55;
    let displacement = (wave * 0.78 + echoWave * 0.22) * maxAmplitude * (0.35 + luma * 0.95);

    let safeDir = select(vec2<f32>(0.0), normalize(uv_c - mouse_c), dist > 0.001);

    let uv_r = clamp(uv - safeDir * displacement * (1.0 + aberration), vec2<f32>(0.0), vec2<f32>(1.0));
    let uv_g = clamp(uv - safeDir * displacement, vec2<f32>(0.0), vec2<f32>(1.0));
    let uv_b = clamp(uv - safeDir * displacement * (1.0 - aberration), vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, uv_r, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv_g, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv_b, 0.0).b;

    var hdr = vec3<f32>(r, g, b);
    let spectral = palette(wave * 0.18 + dist * 0.7 - time * 0.04 + mids * 0.2);
    let caustic = pow(crest, 2.6) * (0.35 + luma) * (1.0 + treble * 0.8);
    hdr = hdr * (0.94 + crest * 0.2) + spectral * caustic * 1.55;
    hdr = hdr + vec3<f32>(0.16, 0.28, 0.8) * pow(max(0.0, 1.0 - dist * 1.8), 3.0) * bass * 0.55;

    let radial = length(uv - vec2<f32>(0.5)) * 1.414;
    hdr = hdr * mix(1.06, 0.72, smoothstep(0.45, 1.0, radial));
    let dither = (ign(vec2<f32>(global_id.xy) + time * 19.0) - 0.5) / 255.0;
    let finalColor = clamp(aces(hdr * 1.18) + vec3<f32>(dither), vec3<f32>(0.0), vec3<f32>(1.0));

    let wave_pos = clamp(wave * 0.5 + 0.5, 0.0, 1.0);
    let hdr_luma = getLuminance(hdr);
    let alpha = clamp(0.16 + wave_pos * 0.18 + pow(max(0.0, hdr_luma - 0.55), 2.0) * 2.8, 0.0, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let finalRGBA = vec4<f32>(finalColor * alpha, alpha);

    textureStore(writeTexture, coords, finalRGBA);
    textureStore(dataTextureA, coords, finalRGBA);
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```
