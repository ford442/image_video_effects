# Swarm Brief: scanline-drift

**Role:** Optimizer
**Name:** Scanline Drift
**Category:** retro-glitch
**Description:** Horizontal segments of the image drift left and right, simulating a bad video signal or tracking error.
**Current lines:** 103
**Target lines:** 153–193 (expand by +50 to +90)

## Role Instructions

You are the Optimizer. This tracking-error drift is clean and honest - but it only reads mouse.y, ignores clicks entirely, and ships an odd depth-write alpha. Give it full touch without breaking the VHS feel:
- Spring-damper the tracking band (priority 1): ease mouse.y with a critically-damped 1D spring (extraBuffer[133..134], [0..4] reserved, [5..132] = engine FFT) so the jitter band glides vertically instead of snapping; raw mouse.y stays the spring target. Add a mouse.x term: horizontal proximity to each strip's displaced edge subtly boosts that strip's drift (keeps 'mouse-driven' honest in both axes).
- Click tracking tears: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple forces a hard horizontal tear on the strips near its click row (a one-shot offset spike decaying over ~0.8s, plus a brief colorShift doubling), so clicks slam the tracking.
- Normalize the depth write: `vec4(depth, 0.0, 0.0, 1.0)` -> `vec4(depth, 0.0, 0.0, 0.0)` (depth value passthrough; r32float only stores .r anyway). Fix the stale header comment ('Category: image' -> retro-glitch, comment-only).
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the hash11 helper, the strip construction (stripId/stripRand), the sin-drift + mouse-jitter offset math, the fract-wrapped r/g/b taps, and the lineDark boundary smoothsteps VERBATIM - the VHS identity is hand-tuned. All 4 sliders honestly wired - keep roles EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.

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
  "id": "scanline-drift",
  "name": "Scanline Drift",
  "url": "shaders/scanline-drift.wgsl",
  "description": "Horizontal segments of the image drift left and right, simulating a bad video signal or tracking error.",
  "params": [
    {
      "name": "Drift Speed",
      "id": "zoomParam1",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "name": "Line Height",
      "id": "zoomParam2",
      "default": 0.1,
      "min": 0,
      "max": 1
    },
    {
      "name": "Jitter Amount",
      "id": "zoomParam3",
      "default": 0.3,
      "min": 0,
      "max": 1
    },
    {
      "name": "Color Shift",
      "id": "zoomParam4",
      "default": 0.2,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
    "mouse-driven",
    "audio-reactive",
    "upgraded-rgba"
  ],
  "tags": [
    "glitch",
    "retro",
    "vintage"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Drift Speed",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Line Height",
      "default": 0.1,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Jitter Amount",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Color Shift",
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
//  Scanline Drift
//  Category: image
//  Features: audio-reactive, mouse-driven
//  Complexity: Low
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
  zoom_params: vec4<f32>,  // x=DriftSpeed, y=LineHeight, z=Jitter, w=ColorShift
  ripples: array<vec4<f32>, 50>,
};

fn hash11(p: f32) -> f32 {
    var p2 = fract(p * .1031);
    p2 *= p2 + 33.33;
    p2 *= p2 + p2;
    return fract(p2);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    var mouse = u.zoom_config.yz;

    // Params
    let driftSpeed = u.zoom_params.x * 2.0 * (1.0 + bass * 0.2);
    let lineHeight = mix(0.001, 0.1, u.zoom_params.y);
    let jitter = u.zoom_params.z * 0.1 * (1.0 + mids * 0.3);
    let colorShift = u.zoom_params.w * 0.05;

    // Determine which horizontal strip we are in
    let stripId = floor(uv.y / lineHeight);
    let stripRand = hash11(stripId);

    // Mouse proximity increases jitter
    let distY = abs(uv.y - mouse.y);
    let mouseEffect = smoothstep(0.2, 0.0, distY);

    // Calculate horizontal offset
    var offset = sin(time * driftSpeed + stripRand * 6.28) * jitter;
    offset += (hash11(stripId + time) - 0.5) * mouseEffect * jitter * 2.0;

    // Color separation
    let rOffset = offset + colorShift;
    let gOffset = offset;
    let bOffset = offset - colorShift;

    let rUV = vec2<f32>(fract(uv.x + rOffset), uv.y);
    let gUV = vec2<f32>(fract(uv.x + gOffset), uv.y);
    let bUV = vec2<f32>(fract(uv.x + bOffset), uv.y);

    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

    // Scanline darkness at strip boundaries
    let stripUVy = fract(uv.y / lineHeight);
    let lineDark = smoothstep(0.0, 0.1, stripUVy) * smoothstep(1.0, 0.9, stripUVy);

    var color = vec3<f32>(r, g, b);
    color *= mix(0.8, 1.0, lineDark);

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let driftMag = abs(rOffset - bOffset);
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let effectIntensity = clamp(driftMag * 10.0 + mouseEffect * 0.3 + luma * 0.2, 0.0, 1.0);
    let finalAlpha = mix(baseColor.a, 1.0, effectIntensity * 0.7);

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, coord, vec4<f32>(color, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
    textureStore(dataTextureA, coord, vec4<f32>(color, finalAlpha));
}
```
