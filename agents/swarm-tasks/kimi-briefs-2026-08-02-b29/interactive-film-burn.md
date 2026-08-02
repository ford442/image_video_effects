# Swarm Brief: interactive-film-burn

**Role:** Visualist
**Name:** Film Burn
**Category:** interactive-mouse
**Description:** Simulates burning film reel with organic edges and grain, centered on the cursor.
**Current lines:** 119
**Target lines:** 169–209 (expand by +50 to +90)

## Role Instructions

You are the Visualist. This film burn's fire edge and ember noise are genuinely pyrotechnic - but the burn snaps to the cursor and clicks never scorch the film. Give it arson:
- Spring-damper the burn center (priority 1): ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the burn hole drags behind the cursor like a real ember; raw mouse stays the spring target. Keep the aspect correction.
- Click cigarette burns: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple sears a small secondary burn at its click point (same hole/fire/smoke mask evaluation against a radius that grows to ~0.08 then chars over ~2s, composed via max() with the main burn masks), so clicks brand the film - the classic cigarette-burn cue mark.
- Per-sector ember FFT: divide the burn edge into 8 angular sectors; each sector's emberGlow rides its own bin (`plasmaBuffer[(sector % 8u) + 1u].x * 0.4`), so the fire line crackles unevenly around the hole instead of only global audio.x.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: dataTextureA stores MASK data (holeMask, fireMask, smokeMask, finalAlpha) - NOT display color - keep that packing VERBATIM. Preserve the hash12/noise/fbm helpers (5-octave rot matrix), the distortedDist construction, the hole/fire/smoke mask smoothsteps, the fireColor ramp + charColor, the sepia/grain intact color, the alpha composition, and the depthOut math VERBATIM - the burn identity is hand-tuned. All 4 slider ids/names/defaults EXACTLY. extraBuffer in [133..255] ONLY.

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
  "id": "interactive-film-burn",
  "name": "Film Burn",
  "category": "interactive-mouse",
  "url": "shaders/interactive-film-burn.wgsl",
  "description": "Simulates burning film reel with organic edges and grain, centered on the cursor.",
  "params": [
    {
      "id": "radius",
      "name": "Burn Radius",
      "default": 0.3,
      "min": 0,
      "max": 1
    },
    {
      "id": "speed",
      "name": "Burn Speed",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "grain",
      "name": "Grain Strength",
      "default": 0.3,
      "min": 0,
      "max": 1
    },
    {
      "id": "glow",
      "name": "Edge Glow",
      "default": 0.4,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
    "mouse-driven",
    "noise",
    "texture",
    "audio-reactive",
    "upgraded-rgba"
  ],
  "tags": [
    "film",
    "burn",
    "embers",
    "analog"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Burn Radius",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Burn Speed",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Grain Strength",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Edge Glow",
      "default": 0.4,
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
// ================================================================
//  Interactive Film Burn
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: interactive-film-burn
//  Created: 2026-05-30
//  By: Copilot
// ================================================================

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
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=BurnRadius, y=BurnSpeed, z=GrainStrength, w=EdgeGlow
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u2.x),
    mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u2.x),
    u2.y
  );
}

fn fbm(p: vec2<f32>) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var pos = p;
  let rot = mat2x2<f32>(0.8, 0.6, -0.6, 0.8);
  for (var i: i32 = 0; i < 5; i = i + 1) {
    value = value + amplitude * noise(pos);
    pos = rot * pos * 2.0;
    amplitude = amplitude * 0.5;
  }
  return value;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let audio = plasmaBuffer[0].xyz;

  let burnRadius = u.zoom_params.x * 0.80;
  let burnSpeed = u.zoom_params.y * 2.0;
  let grainStrength = u.zoom_params.z;
  let glowWidth = u.zoom_params.w * 0.20 + 0.01;

  let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(distVec);
  let noiseScale = 10.0 + audio.z * 6.0;
  let noiseVal = fbm(uv * noiseScale + vec2<f32>(time * burnSpeed * 0.15, -time * burnSpeed * 0.11));
  let distortedDist = dist - noiseVal * (0.10 + audio.x * 0.30);

  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let filmGrain = (hash12(uv * 120.0 + vec2<f32>(time * 7.3, time * 13.1)) - 0.5) * grainStrength * 0.35;
  let gray = dot(sourceColor, vec3<f32>(0.299, 0.587, 0.114));
  let sepia = vec3<f32>(gray * 1.18, gray * 1.0, gray * 0.78);
  let intactColor = mix(sourceColor, sepia, 0.55) + vec3<f32>(filmGrain);

  let d = distortedDist - burnRadius;
  let holeMask = 1.0 - smoothstep(-0.015, 0.015, d);
  let fireMask = smoothstep(-glowWidth, 0.0, d) * (1.0 - smoothstep(0.0, glowWidth, d));
  let smokeMask = 1.0 - smoothstep(glowWidth * 0.5, glowWidth * 3.0, d);

  let emberNoise = noise(uv * 50.0 + vec2<f32>(time * 10.0, -time * 7.0));
  let emberGlow = smoothstep(-0.08, 0.0, d) * (0.4 + 0.6 * emberNoise);
  let fireT = clamp(d / glowWidth, 0.0, 1.0);
  var fireColor = mix(vec3<f32>(1.0, 0.98, 0.80), vec3<f32>(1.0, 0.30, 0.0), fireT);
  fireColor = mix(fireColor, vec3<f32>(0.08, 0.0, 0.0), fireT * fireT);
  fireColor = fireColor + vec3<f32>(1.0, 0.45, 0.10) * emberGlow * (0.4 + 0.6 * audio.x);
  let charColor = vec3<f32>(0.0) + vec3<f32>(1.0, 0.18, 0.02) * emberGlow * 0.45;

  var finalColor = intactColor * mix(0.55, 1.0, smokeMask);
  finalColor = mix(finalColor, fireColor, fireMask);
  finalColor = mix(finalColor, charColor, holeMask);

  var finalAlpha = (1.0 - holeMask) * (0.82 + 0.12 * smokeMask);
  finalAlpha = max(finalAlpha, fireMask * (0.35 + 0.45 * u.zoom_params.w));
  finalAlpha = clamp(finalAlpha, 0.0, 0.98);

  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthOut = clamp(mix(baseDepth, baseDepth * 0.25, holeMask) + fireMask * 0.08, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(holeMask, fireMask, smokeMask, finalAlpha));
}
```
