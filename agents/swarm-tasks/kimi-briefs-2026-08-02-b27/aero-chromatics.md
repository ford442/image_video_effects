# Swarm Brief: aero-chromatics

**Role:** Interactivist
**Name:** Aero Chromatics
**Category:** simulation
**Description:** Wind tunnel simulation where image brightness determines aerodynamic drag, creating chromatic smoke trails.
**Current lines:** 117
**Target lines:** 167–207 (expand by +50 to +90)

## Role Instructions

You are the Interactivist. This smoke-advection shader declares plasmaBuffer 'Or generic object data' and never samples it - the smoke ignores the music - and clicks never gust. Give the wind a beat:
- WIRE THE DEAD AUDIO (priority 1): bass gusts - the windStrength rides bass (windStrength *= 1.0 + bass * 0.6) so drops push the smoke; per-band flutter - 8 horizontal bands each wobble their velocity perpendicular component by `plasmaBuffer[(band % 8u) + 1u].x * 0.003`, so the trail flickers across the spectrum.
- Spring-damper the wind source: ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the repulsion source drifts like a slow fan; raw mouse stays the spring target. Keep the aspect-corrected distance and the smoothstep(0.5, 0.0) influence.
- Click gust bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a decaying radial gust from its click point (velocity += aspect-corrected dir * 0.02 * exp(-rippleAge * 2.0) * smoothstep(0.35, 0.0, distR), ~1.5s), so clicks blow puffs of smoke. Fix the stale comment (comment-only): config.y = ripple COUNT.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: the feedback contract is SACRED - dataTextureC is read as advected history (3 chromatic taps + alpha carry), dataTextureA is written with the display color - keep this exactly, never tonemap the A write. Preserve ALL the dev commentary comments VERBATIM (file personality), the luma-drag model, the baseWind/mouseWind construction, the chromatic offsetR/G/B advection taps, the decay/injectAmount mix, and the depth-weighted alpha VERBATIM. All 4 slider ids/names/defaults EXACTLY. extraBuffer in [133..255] ONLY.

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
  "id": "aero-chromatics",
  "name": "Aero Chromatics",
  "url": "shaders/aero-chromatics.wgsl",
  "features": [
    "mouse-driven"
  ],
  "description": "Wind tunnel simulation where image brightness determines aerodynamic drag, creating chromatic smoke trails.",
  "params": [
    {
      "id": "wind-strength",
      "name": "Wind Force",
      "type": "float",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "decay",
      "name": "Smoke Decay",
      "type": "float",
      "default": 0.8,
      "min": 0,
      "max": 1
    },
    {
      "id": "chroma",
      "name": "Chromatic Split",
      "type": "float",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "source-mix",
      "name": "Source Intensity",
      "type": "float",
      "default": 0.5,
      "min": 0,
      "max": 1
    }
  ],
  "tags": [
    "simulation",
    "physics"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Wind Force",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Smoke Decay",
      "default": 0.8,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Chromatic Split",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Source Intensity",
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
//  Aero Chromatics
//  Category: simulation
//  Features: mouse-driven, depth-aware
//  Complexity: Medium
//  Chunks From: aero-chromatics
//  Created: 2026-05-31
//  By: Copilot CLI (tactical swarm)
// ═══════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// Aero Chromatics
// P1: Wind Speed / Force
// P2: Decay Rate (Tail length)
// P3: Chromatic Split (Aberration amount)
// P4: Source Mix (How much new video is injected vs history)

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    var mouse = u.zoom_config.yz;

    // Params
    let windStrength = mix(0.5, 5.0, u.zoom_params.x);
    let decay = mix(0.8, 0.995, u.zoom_params.y);
    let chromaSplit = u.zoom_params.z * 0.02; // Small offset
    let sourceMix = mix(0.01, 0.2, u.zoom_params.w);

    // Calculate drag based on current image luma
    // Lighter pixels = lighter weight = move faster (or vice versa?)
    // Let's say Light = Smoke = Fast. Dark = Heavy = Slow.
    let currentFrame = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(currentFrame.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let drag = 1.0 - (luma * 0.8); // 0.2 to 1.0

    // Wind Vector
    // Base wind flows diagonally or follows mouse?
    // Let's make wind blow AWAY from mouse.
    let dVec = uv - mouse;
    let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

    // Mouse influence falls off
    let mouseInfluence = smoothstep(0.5, 0.0, dist);

    // Combine base drift with mouse wind
    // Base drift (upwards slightly like smoke)
    let baseWind = vec2<f32>(0.0, -0.001);
    let mouseWind = normalize(dVec) * 0.01 * mouseInfluence * windStrength;

    // Final velocity for this pixel
    // If luma is high, it moves more.
    let velocity = (baseWind + mouseWind) * (luma * 2.0);

    // To simulate advection, we sample FROM (uv - velocity)
    // Because the smoke at (uv) came from (uv - velocity).

    // Chromatic Advection: Sample R, G, B from slightly different locations
    let offsetR = velocity * (1.0 + chromaSplit);
    let offsetG = velocity;
    let offsetB = velocity * (1.0 - chromaSplit);

    let prevR = textureSampleLevel(dataTextureC, u_sampler, uv - offsetR, 0.0).r;
    let prevG = textureSampleLevel(dataTextureC, u_sampler, uv - offsetG, 0.0).g;
    let prevB = textureSampleLevel(dataTextureC, u_sampler, uv - offsetB, 0.0).b;
    let prevAlpha = textureSampleLevel(dataTextureC, u_sampler, uv - velocity, 0.0).a; // Carry alpha

    let historyColor = vec3<f32>(prevR, prevG, prevB);

    // Mix new source
    // If it's bright, we inject more source (smoke generation).
    // If dark, we inject less (transparent).
    let injectAmount = sourceMix * luma;

    var finalColor = mix(historyColor * decay, currentFrame.rgb, injectAmount);

    // Clamp
    finalColor = max(vec3<f32>(0.0), finalColor);

    // Sample depth for alpha calculation
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // Calculate luminance-based alpha
    let lumaFinal = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = mix(0.7, 1.0, lumaFinal);
    let finalAlpha = mix(alpha * 0.8, alpha, depth);

    // Store to history (A) and Display (Write)
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));

    // Pass depth
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4(depth, 0.0, 0.0, 0.0));
}
```
