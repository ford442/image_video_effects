# Swarm Brief: sonic-boom

**Role:** Visualist
**Name:** Sonic Boom
**Category:** distortion
**Description:** (no description field)
**Current lines:** 118
**Target lines:** 168–208 (expand by +50 to +90)

## Role Instructions

You are the Visualist. This mach-cone shock's physics stack is genuinely aerodynamic - but the shock center snaps to the cursor and clicks never break the sound barrier. Give it flybys:
- Spring-damper the shock center (priority 1): ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the cone trails the cursor like a jet that can't turn instantly; raw mouse stays the spring target. Keep the aspect correction.
- Click mach bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple fires a secondary expanding shock ring from its click point (same ring0 gaussian form with radius growing at mach speed ~0.5/s, strength exp(-age * 1.5), ~2s) composed into ringSum before the distortion taps, so clicks launch sonic booms.
- Per-ring FFT voices: the three PHI rings each ride their own bin (ring0 <- plasmaBuffer[2].x, ring1 <- plasmaBuffer[4].x, ring2 <- plasmaBuffer[6].x, +-20% amplitude), so the shock diamonds shimmer across the spectrum instead of only global bass/treble.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the aces_tonemap, the mach number/angle math, the PHI ring hierarchy (d0/d1/d2, ring0/1/2 gaussians), the shock diamond phase, the condensation/fog scatter, the doppler chromatic taps (uv_r/uv_g/uv_b), the temporal tail (prevTail * 0.82 via C read), and the alpha formula VERBATIM - the aero identity is hand-tuned. dataTextureA stays DISPLAY color. All 4 slider ids/names/defaults/ranges EXACTLY (Ring Width range 0.01-0.2, Chrom. Split 0-0.1). extraBuffer in [133..255] ONLY.

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
  "id": "sonic-boom",
  "name": "Sonic Boom",
  "url": "shaders/sonic-boom.wgsl",
  "features": [
    "mouse-driven",
    "audio-reactive",
    "depth-aware",
    "upgraded-rgba"
  ],
  "params": [
    {
      "id": "radius",
      "name": "Ring Radius",
      "default": 0.2,
      "min": 0,
      "max": 1
    },
    {
      "id": "width",
      "name": "Ring Width",
      "default": 0.05,
      "min": 0.01,
      "max": 0.2
    },
    {
      "id": "strength",
      "name": "Distortion",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "split",
      "name": "Chrom. Split",
      "default": 0.02,
      "min": 0,
      "max": 0.1
    }
  ],
  "tags": [
    "warp",
    "distort",
    "shock-wave",
    "mach-cone",
    "supersonic"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Ring Radius",
      "default": 0.2,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Ring Width",
      "default": 0.05,
      "min": 0.01,
      "max": 0.2,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Distortion",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Chrom. Split",
      "default": 0.02,
      "min": 0.0,
      "max": 0.1,
      "step": 0.01
    }
  ],
  "updated": true
}
```

## Current WGSL Code

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  Sonic Boom v2
//  Category: distortion
//  Features: mouse-driven, audio-reactive, mach-cone, prandtl-glauert,
//            shock-diamonds, condensation-fog, aces-tone-map
//  Complexity: High
//  Upgraded: 2026-05-30
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

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51);
  let b = vec3<f32>(0.03);
  let c = vec3<f32>(2.43);
  let d = vec3<f32>(0.59);
  let e = vec3<f32>(0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

const PHI: f32 = 1.61803398874989484820;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
  let dim = vec2<i32>(i32(u.config.z), i32(u.config.w));
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(coord) / vec2<f32>(f32(dim.x), f32(dim.y));
  let aspect = vec2<f32>(f32(dim.x) / f32(dim.y), 1.0);

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let radius   = u.zoom_params.x;
  let width    = u.zoom_params.y;
  let strength = u.zoom_params.z * (1.0 + bass * 0.6);
  let split    = u.zoom_params.w;

  let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let to_pixel = (uv - mouse_pos) * aspect;
  let dist = length(to_pixel);
  let dir = to_pixel / max(dist, 1e-4);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let atmDensity = 0.5 + depth * 0.5;

  let machNum = 0.8 + strength * 1.4 + bass * 0.4;
  let machAngle = asin(clamp(1.0 / max(machNum, 1.001), 0.0, 1.0));
  let coneDist = abs(dist - radius) / max(machAngle, 0.01);

  let widthHalf = max(width * 0.5, 1e-4);
  let invWH = 1.0 / widthHalf;
  let d0 = (dist - radius) * invWH;
  let d1 = (dist - radius / PHI) * invWH;
  let d2 = (dist - radius / (PHI * PHI)) * invWH;
  let ring0 = exp(-d0 * d0 * 4.0);
  let ring1 = exp(-d1 * d1 * 6.0) * 0.55;
  let ring2 = exp(-d2 * d2 * 8.0) * 0.30;
  let ringSum = ring0 + ring1 + ring2;

  let diamondPhase = sin(coneDist * 12.0 * PHI) * 0.5 + 0.5;
  let shockDiamond = diamondPhase * ring0 * 0.4 * select(0.0, 1.0, machNum > 1.0);

  let condensation = exp(-coneDist * coneDist * 2.0) * atmDensity * (0.3 + bass * 0.4) * select(0.0, 1.0, machNum > 0.95);
  let fogScatter = condensation * 0.5 * (1.0 + mids * 0.5);

  let prevTail = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;
  let ringFinal = max(ringSum, prevTail * 0.82);

  let distortion = dir * ringFinal * strength * 0.12 * (1.0 + mids * 0.3);
  let velocity = ringFinal * strength * (1.0 + bass * 0.5);
  let caStrength = split * (1.0 + velocity * 3.0);
  let doppler = (ring0 - ring2) * split * 10.0;

  let uv_r = clamp(uv - distortion * (1.0 + caStrength * 1.5 + doppler), vec2<f32>(0.0), vec2<f32>(1.0));
  let uv_g = clamp(uv - distortion, vec2<f32>(0.0), vec2<f32>(1.0));
  let uv_b = clamp(uv - distortion * (1.0 - caStrength * 1.5 - doppler), vec2<f32>(0.0), vec2<f32>(1.0));

  let c = textureSampleLevel(readTexture, u_sampler, uv_g, 0.0);
  let r = textureSampleLevel(readTexture, u_sampler, uv_r, 0.0).r;
  let b = textureSampleLevel(readTexture, u_sampler, uv_b, 0.0).b;

  let shockFront = ring0 * (0.6 + treble * 0.4);
  let bloom = vec3<f32>(0.9, 0.95, 1.0) * shockFront * 0.35;
  let diamondColor = vec3<f32>(0.6, 0.8, 1.0) * shockDiamond * (1.0 + treble * 0.5);
  let fogColor = vec3<f32>(0.85, 0.88, 0.92) * fogScatter;

  var finalColor = vec3<f32>(r, c.g, b);
  finalColor = finalColor + bloom + diamondColor + fogColor;
  finalColor = aces_tonemap(finalColor * (1.0 + shockFront * 0.3));

  let shockIntensity = clamp(ringSum + shockDiamond + shockFront * 0.5, 0.0, 1.0);
  let alpha = clamp(shockIntensity * condensation * depth * 1.2 + abs(doppler) * 0.4 + treble * 0.06, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```
