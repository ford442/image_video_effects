# Swarm Brief: spectral-distortion

**Role:** Visualist
**Name:** Spectral Distortion
**Category:** interactive-mouse
**Description:** RGB channels split and warp based on noise, mouse proximity, and bass-driven audio reactivity.
**Current lines:** 99
**Target lines:** 149–189 (expand by +50 to +90)

## Role Instructions

You are the Visualist. This warp field is honest and branchless - give the mouse weight, clicks a punch, and each channel its own frequency:
- Spring-damper the influence center (priority 1): ease the mouse target with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the warp blob trails the cursor with weight; keep the branchless mouseActive gate (step(0.0, mousePos.x)) applied to the RAW mouse before springing.
- Click warp bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a decaying radial warp impulse centered on its click point (an expanding ring that locally boosts warpStr, ~1.2s fade), branchless (smoothstep bands, no if).
- Per-channel bin separation: drive the R offset from `plasmaBuffer[3].x` and the B offset from `plasmaBuffer[7].x` (different spectrum regions) instead of one global separation term, so the chromatic tear shimmers across the spectrum; the slider stays the base separation amount.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the value_noise helper, the three nR/nG/nB field taps with their (t, t+10, -t) offsets, and the branchless select()/step() style VERBATIM (docs/BRANCHLESS_PATTERNS.md). Fix the stale uniform comments (config.y = ripple COUNT, zoom_config.w = mouseDown, not 'Generic2') - comment-only. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.

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
  "id": "spectral-distortion",
  "name": "Spectral Distortion",
  "url": "shaders/spectral-distortion.wgsl",
  "description": "RGB channels split and warp based on noise, mouse proximity, and bass-driven audio reactivity.",
  "params": [
    {
      "id": "separation",
      "name": "RGB Separation",
      "default": 0.3,
      "min": 0,
      "max": 1
    },
    {
      "id": "warpScale",
      "name": "Warp Scale",
      "default": 0.2,
      "min": 0,
      "max": 1
    },
    {
      "id": "mouseInfluence",
      "name": "Mouse Influence",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "speed",
      "name": "Speed",
      "default": 0.3,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
    "mouse-driven",
    "temporal-persistence",
    "glitch",
    "audio-reactive",
    "upgraded-rgba"
  ],
  "tags": [
    "filter",
    "image-processing",
    "chromatic",
    "warp",
    "noise"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "RGB Separation",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Warp Scale",
      "default": 0.2,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Mouse Influence",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Speed",
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
//  Spectral Distortion
//  Category: interactive-mouse
//  Features: mouse-driven, temporal-persistence, glitch, audio-reactive, upgraded-rgba
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

fn noise(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn value_noise(st: vec2<f32>) -> f32 {
    let i = floor(st);
    let f = fract(st);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(noise(i + vec2<f32>(0.0, 0.0)),
                   noise(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(noise(i + vec2<f32>(0.0, 1.0)),
                   noise(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / resolution;
  var mousePos = u.zoom_config.yz;
  let time = u.config.x;

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let separation = clamp(u.zoom_params.x * 0.1 * (1.0 + bass * 0.3), 0.0, 0.2);
  let warpScale = u.zoom_params.y * 20.0 + 1.0 + mids * 5.0;
  let mouseInf = u.zoom_params.z;
  let speed = u.zoom_params.w * 2.0;

  var warpStr = 0.02 + treble * 0.01;

  // Branchless mouse influence
  let mouseActive = step(0.0, mousePos.x);
  let aspect = resolution.x / max(resolution.y, 0.001);
  let dVec = uv - mousePos;
  let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));
  let influenceRadius = 0.3;
  let influence = 1.0 - smoothstep(0.0, influenceRadius, dist);
  warpStr += influence * mouseInf * 0.1 * mouseActive;

  // Generate warp fields for R, G, B
  let t = time * speed;
  let nR = value_noise(uv * warpScale + vec2<f32>(t, t));
  let nG = value_noise(uv * warpScale + vec2<f32>(t + 10.0, -t));
  let nB = value_noise(uv * warpScale + vec2<f32>(-t, t + 5.0));

  let offR = vec2<f32>(nR - 0.5, value_noise(uv * warpScale + 100.0) - 0.5) * warpStr + vec2<f32>(separation, 0.0);
  let offG = vec2<f32>(nG - 0.5, value_noise(uv * warpScale + 200.0) - 0.5) * warpStr;
  let offB = vec2<f32>(nB - 0.5, value_noise(uv * warpScale + 300.0) - 0.5) * warpStr - vec2<f32>(separation, 0.0);

  let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + offR, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, clamp(uv + offG, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(uv + offB, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

  // Alpha: warp magnitude + chromatic separation drive spectral effect weight
  let warpMag = length(offR - offB);
  let luma = dot(vec3<f32>(r, g, b), vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(warpMag * 8.0 + separation * 6.0 + luma * 0.2, 0.0, 1.0);
  let finalColor = vec4<f32>(r, g, b, alpha);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
  textureStore(dataTextureA, global_id.xy, finalColor);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```
