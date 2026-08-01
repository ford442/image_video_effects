# Swarm Brief: signal-modulation

**Role:** Visualist
**Name:** Signal Modulation
**Category:** visual-effects
**Description:** Simulates AM/FM signal distortion with mouse-controlled frequency and amplitude.
**Current lines:** 102
**Target lines:** 152–192 (expand by +50 to +90)

## Role Instructions

You are the Visualist. This signal shader's 8-band 'spectral' visualizer is a LIE - bandAmp is driven by fract(sin()) hash noise, not the FFT. The bins are sitting right there in plasmaBuffer. Make the bands honest, then give it touch:
- REAL FFT BANDS (priority 1): replace `bandNoise = fract(sin(band * 12.9898 + time) * 43758.5453)` with the actual bin amplitude (`plasmaBuffer[u32(band) + 1u].x`, bands 0-7 map to bins 1-8; band is f32 from floor() - cast it). Keep bandAmp's (1.0 + bass * 0.5) boost on top. The fake hash term can survive ONLY as a tiny +-10% jitter so the bars don't look digitized - the FFT must be the signal.
- Spring-damper the wave origin: ease the mouse target with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the proximity-warped carrier trails the cursor; raw mouse stays the spring target.
- Click carrier bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple injects a decaying signal spike at its click point (local boost to `signal` + extra chromatic offset in a radial band, ~1.2s fade), so clicks spike the waveform.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the bass_env and huePreserveClamp helpers (keep the 1.8 cap call), the carrier wave construction (wave/distanceToWave/signal smoothstep), the displacement + r/g/b chromatic tap structure, and the noise floor VERBATIM. All 4 sliders are honestly wired - keep roles EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.

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
  "id": "signal-modulation",
  "name": "Signal Modulation",
  "url": "shaders/signal-modulation.wgsl",
  "description": "Simulates AM/FM signal distortion with mouse-controlled frequency and amplitude.",
  "features": [
    "mouse-driven",
    "visual-effect"
  ],
  "params": [
    {
      "id": "freq",
      "name": "Base Frequency",
      "type": "float",
      "default": 0.2,
      "min": 0,
      "max": 1
    },
    {
      "id": "amp",
      "name": "Distortion Amt",
      "type": "float",
      "default": 0.1,
      "min": 0,
      "max": 1
    },
    {
      "id": "speed",
      "name": "Scroll Speed",
      "type": "float",
      "default": 0.3,
      "min": 0,
      "max": 1
    },
    {
      "id": "shift",
      "name": "Color Split",
      "type": "float",
      "default": 0.2,
      "min": 0,
      "max": 1
    }
  ],
  "tags": [
    "filter",
    "image-processing"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Base Frequency",
      "default": 0.2,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Distortion Amt",
      "default": 0.1,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Scroll Speed",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Color Split",
      "default": 0.2,
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
//  Signal Modulation
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, chromatic-aberration, spectral-bands, upgraded-rgba
//  Complexity: High
//  Chunks From: signal-modulation, bass_env, hue_preserve_clamp
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

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

fn huePreserveClamp(col: vec3<f32>, maxRGB: f32) -> vec3<f32> {
  let mx = max(max(col.r, col.g), col.b);
  if (mx > maxRGB) {
    let lum = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    return mix(col * (maxRGB / mx), vec3<f32>(lum), 0.15);
  }
  return col;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mousePos = u.zoom_config.yz;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthAtten = mix(1.0, 0.6, depth);

    let freq = mix(1.0, 50.0, u.zoom_params.x) * bass_env(bass, mids);
    let amp = mix(0.0, 0.5, u.zoom_params.y) * (1.0 + mids * 0.3);
    let speed = mix(0.0, 10.0, u.zoom_params.z) * (1.0 + treble * 0.25);
    let colorSplit = u.zoom_params.w * 0.02 * (1.0 + bass * 0.1);
    let lineWidth = 0.006 + amp * 0.03;

    let proximity = distance(uv, mousePos);
    let wave = 0.5 + amp * sin((uv.x + proximity * 2.0) * freq + time * speed);
    let distanceToWave = abs(uv.y - wave);
    let signal = 1.0 - smoothstep(lineWidth, lineWidth + 0.005, distanceToWave);
    let displacement = signal * amp * 0.1;

    // Spectral band visualization: divide screen into 8 frequency bands
    let band = floor(uv.y * 8.0);
    let bandNoise = fract(sin(band * 12.9898 + time) * 43758.5453);
    let bandAmp = mix(0.1, 1.0, bandNoise) * (1.0 + bass * 0.5);
    let bandMask = smoothstep(0.0, 0.02, abs(fract(uv.y * 8.0) - 0.5)) * signal * bandAmp;

    let baseUV = clamp(uv + vec2<f32>(0.0, displacement), vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
    let offset = vec2<f32>(colorSplit * signal * (0.5 + treble * 0.5), 0.0);
    let uvR = clamp(baseUV + offset, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
    let uvG = baseUV;
    let uvB = clamp(baseUV - offset, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));

    let baseColor = textureSampleLevel(readTexture, u_sampler, baseUV, 0.0);
    let glow = vec3<f32>(0.15 + bandMask * 0.5, 0.35 + treble * 0.08 + bandMask * 0.3, 0.55 + bandMask * 0.2) * signal;
    var finalColor = vec3<f32>(
        textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r,
        baseColor.g,
        textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b
    ) + glow;

    // Noise floor
    let noiseFloor = (fract(sin(dot(uv + time, vec2<f32>(12.9898, 78.233))) * 43758.5453) - 0.5) * 0.02 * signal;
    finalColor = finalColor + vec3<f32>(noiseFloor);

    finalColor = huePreserveClamp(finalColor, 1.8) * depthAtten;
    let alpha = clamp(baseColor.a * 0.45 + signal * 0.35 + bass * 0.05 + bandMask * 0.2, 0.08, 1.0);
    let depthOut = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, baseUV, 0.0).r + signal * 0.04, 0.0, 1.0);
    let finalPixel = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalPixel);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalPixel);
}
```
