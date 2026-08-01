# Swarm Brief: moire-interference

**Role:** Visualist
**Name:** Moiré Interference
**Category:** interactive-mouse
**Description:** Generates dynamic interference patterns between the center and the mouse position.
**Current lines:** 105
**Target lines:** 155–195 (expand by +50 to +90)

## Role Instructions

You are the Visualist. This interference field is honest but carries a dead variable, an odd depth write, and a snapping mouse point. Clean it up and give it touch:
- Remove the dead `dir` variable (normalize(uv - 0.5), never used) and normalize the depth write `vec4(depth, 0.0, 0.0, 1.0)` -> `vec4(depth, 0.0, 0.0, 0.0)`. Fix the stale header ('Category: image' -> interactive-mouse, comment-only) and config.y comment (ripple COUNT).
- Spring-damper the second emitter (priority 1): ease the mouse point with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the moire field morphs fluidly as the cursor moves; raw mouse stays the spring target. Keep the aspect correction on the SPRUNG position.
- Click interference bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple acts as a temporary THIRD wave emitter at its click point (same sin(d * freq - time * 2.0) form, weight exp(-age * 2.0), ~2s fade), so clicks drop stones into the interference pond. Also modulate each wave's amplitude by a per-emitter FFT bin (emitter 1 -> bin 1, mouse emitter -> bin 5) so the two sources listen to different bands.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the two-point sin() interference core, the complexity third-wave branch, the cos/sin displacement vector, and the r/g/b aberration tap structure VERBATIM. All 4 sliders honestly wired (note Complexity default 0 = third wave off) - keep roles EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.

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
  "id": "moire-interference",
  "label": "Moir\u00e9 Interference",
  "name": "Moir\u00e9 Interference",
  "url": "shaders/moire-interference.wgsl",
  "icon": "wifi",
  "description": "Generates dynamic interference patterns between the center and the mouse position.",
  "features": [
    "mouse-driven",
    "upgraded-rgba",
    "audio-reactive"
  ],
  "params": [
    {
      "name": "Frequency",
      "id": "x",
      "min": 0,
      "max": 1,
      "default": 0.5
    },
    {
      "name": "Distortion",
      "id": "y",
      "min": 0,
      "max": 1,
      "default": 0.5
    },
    {
      "name": "Aberration",
      "id": "z",
      "min": 0,
      "max": 1,
      "default": 0.2
    },
    {
      "name": "Complexity",
      "id": "w",
      "min": 0,
      "max": 1,
      "default": 0
    }
  ],
  "tags": [
    "filter",
    "image-processing"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Frequency",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Distortion",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Aberration",
      "default": 0.2,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Complexity",
      "default": 0,
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
//  Moiré Interference
//  Category: image
//  Features: [mouse-driven, audio-reactive, upgraded-rgba]
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
  zoom_params: vec4<f32>,  // x=Frequency, y=Distortion, z=Aberration, w=Complexity
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  var uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Params
  let freq = mix(20.0, 200.0, u.zoom_params.x) * (1.0 + bass * 0.1 + mids * 0.05);
  let strength = u.zoom_params.y * 0.05 * (1.0 + treble * 0.1);
  let abb = u.zoom_params.z * 0.02;
  let complexity = u.zoom_params.w;

  // Points
  var center = vec2<f32>(0.5 * aspect, 0.5);
  var mouse = vec2<f32>(u.zoom_config.y * aspect, u.zoom_config.z);
  let current_uv = vec2<f32>(uv.x * aspect, uv.y);

  // Distances
  let d1 = distance(current_uv, center);
  let d2 = distance(current_uv, mouse);

  // Wave functions
  let w1 = sin(d1 * freq - time * 2.0);
  let w2 = sin(d2 * freq - time * 2.0);

  // Basic Interference
  var interference = w1 + w2;

  // Complexity adds a third point or modulates freq
  if (complexity > 0.0) {
      let d3 = distance(current_uv, mix(center, mouse, 0.5));
      let w3 = sin(d3 * freq * 1.5 + time);
      interference += w3 * complexity;
  }

  // Normalize roughly
  interference = interference * 0.5;

  // Distortion Vector
  var dir = normalize(uv - vec2<f32>(0.5));
  let displacement = vec2<f32>(cos(interference * 3.14), sin(interference * 3.14)) * strength;

  // Sample with Aberration
  let r_uv = uv + displacement * (1.0 + abb * 10.0);
  let g_uv = uv + displacement;
  let b_uv = uv + displacement * (1.0 - abb * 10.0);

  let r = textureSampleLevel(readTexture, u_sampler, r_uv, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, g_uv, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, b_uv, 0.0).b;

  var color = vec3<f32>(r, g, b);

  // Depth pass-through
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Alpha: preserve input transparency, blend to opaque based on effect intensity
  let dispMag = length(displacement);
  let effectIntensity = clamp(dispMag * 10.0 + abs(interference) * 0.2, 0.0, 1.0);
  let finalAlpha = mix(baseColor.a, 1.0, effectIntensity);

  textureStore(writeTexture, coord, vec4<f32>(color, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(color, finalAlpha));
}
```
