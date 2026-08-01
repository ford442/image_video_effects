# Swarm Brief: sonar-pulse

**Role:** Interactivist
**Name:** Sonar Pulse
**Category:** interactive-mouse
**Description:** Radial sonar waves emitting from the cursor that distort and scan the image. Now with audio reactivity.
**Current lines:** 103
**Target lines:** 153–193 (expand by +50 to +90)

## Role Instructions

You are the Interactivist. This is a SONAR shader that ignores the ripples uniform - clicks should fire pings! The origin also snaps to the cursor. Give the sonar its voice:
- CLICK PINGS (priority 1): loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple is a sonar emitter at its click point: an expanding ring at radius age * 0.6 with the shader's own pulse smoothstep profile (reuse waveWidth), intensity exp(-age * 2.0), ~2s life, adding to pulseStrength AND the chromatic echo + distortion, so every click fires a visible ping that sweeps the image.
- Spring-damper the sonar origin: ease the mouse position with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the main emitter glides; raw mouse stays the spring target. Keep aspect correction on the SPRUNG position.
- Per-ring spectral shimmer: modulate the pulse color by FFT bins - ring phase proximity picks bins 1-8 (`plasmaBuffer[(ringIdx % 8u) + 1u].x` where ringIdx derives from floor(phase / 6.28318)) tinting pulseColor between the green sonar and the violet beat colors, so the rings shimmer across the spectrum. Fix stale comments (comment-only): config.y = ripple COUNT, zoom_config.w = mouseDown.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the bass_env helper, the phase/pulse/falloff core, the interference beat construction (phase2/beat/beatMask), the safeDist normalize guard, and the r/g/b chromatic echo taps VERBATIM. All 4 sliders honestly wired - keep roles EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.

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
  "id": "sonar-pulse",
  "name": "Sonar Pulse",
  "url": "shaders/sonar-pulse.wgsl",
  "description": "Radial sonar waves emitting from the cursor that distort and scan the image. Now with audio reactivity.",
  "params": [
    {
      "id": "speed",
      "name": "Wave Speed",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "freq",
      "name": "Frequency",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "intensity",
      "name": "Intensity",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "width",
      "name": "Wave Width",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.01
    }
  ],
  "features": [
    "mouse-driven",
    "audio-reactive",
    "upgraded-rgba"
  ],
  "tags": [
    "filter",
    "image-processing",
    "sonar",
    "pulse",
    "audio-reactive"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Wave Speed",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Frequency",
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
      "name": "Wave Width",
      "default": 0.3,
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
//  Sonar Pulse
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, chromatic-echo, depth-attenuation, interference, upgraded-rgba
//  Complexity: High
//  Chunks From: sonar-pulse, bass_env, depth-aware-fog
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / max(resolution, vec2<f32>(0.001, 0.001));
  let time = u.config.x;

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let waveSpeed = mix(1.0, 10.0, u.zoom_params.x) * bass_env(bass, mids);
  let waveFreq = mix(10.0, 100.0, u.zoom_params.y) + mids * 10.0;
  let intensity = clamp(u.zoom_params.z + treble * 0.1, 0.0, 1.0);
  let waveWidth = max(mix(0.1, 0.5, u.zoom_params.w), 0.001);

  let aspect = resolution.x / max(resolution.y, 0.001);
  let mousePos = u.zoom_config.yz;

  let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouse_corrected = vec2<f32>(mousePos.x * aspect, mousePos.y);

  let dist = distance(uv_corrected, mouse_corrected);

  // Multi-ring sonar with chromatic separation
  let phase = dist * waveFreq - time * waveSpeed;
  let wave = sin(phase);
  let pulse = smoothstep(1.0 - waveWidth, 1.0, wave);
  let falloff = 1.0 / (1.0 + dist * 2.0);

  // Interference beats from secondary wave
  let phase2 = dist * waveFreq * 1.03 - time * waveSpeed * 0.97;
  let beat = sin(phase) * sin(phase2);
  let beatMask = smoothstep(0.5, 1.0, abs(beat)) * 0.3;

  let audioBoost = bass_env(bass, mids);
  let pulseStrength = pulse * intensity * falloff * audioBoost;

  let safeDist = max(dist, 0.001);
  let offsetDir = (uv_corrected - mouse_corrected) / safeDist;
  let distortAmt = 0.02 * pulse * intensity;
  let distortedUV = clamp(uv - offsetDir * distortAmt, vec2<f32>(0.0), vec2<f32>(1.0));

  // Chromatic echo: R/G/B sample at different distances
  let chromaOffset = pulseStrength * 0.015;
  let rUV = clamp(distortedUV + offsetDir * chromaOffset, vec2<f32>(0.0), vec2<f32>(1.0));
  let gUV = distortedUV;
  let bUV = clamp(distortedUV - offsetDir * chromaOffset, vec2<f32>(0.0), vec2<f32>(1.0));

  let rCol = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
  let gCol = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
  let bCol = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

  let pulseColor = vec3<f32>(0.0, 1.0, 0.5);
  var finalColor = vec3<f32>(rCol, gCol, bCol) + pulseColor * pulseStrength;
  finalColor = finalColor + vec3<f32>(0.5, 0.2, 0.8) * beatMask * intensity;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthAtten = mix(1.0, 0.5, depth);
  finalColor = finalColor * depthAtten;

  let luminance = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(luminance + pulseStrength * 0.3 + beatMask * 0.2, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```
