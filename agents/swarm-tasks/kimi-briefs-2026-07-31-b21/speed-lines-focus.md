# Swarm Brief: speed-lines-focus

**Role:** Visualist
**Name:** Speed Lines Focus
**Category:** artistic
**Description:** Applies a radial zoom blur and manga-style speed lines focused on the mouse.
**Current lines:** 106
**Target lines:** 156–196 (expand by +50 to +90)

## Role Instructions

You are the Visualist. This manga speed-line focus is honest - but the focus point snaps, clicks do nothing, and the depth write ships a stray alpha. Sharpen it:
- Spring-damper the focus point (priority 1): ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the zoom-blur vortex trails the cursor with momentum; raw mouse stays the spring target. The 16-tap zoom blur then naturally smears during fast moves.
- Click action bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple flashes a radial speed-line burst at its click point (temporary lineEffect boost with lines emanating from the click angle, ~1.0s fade), so clicks punctuate the action like a manga impact frame.
- Angular FFT voices: divide the angle around the focus into 8 sectors; each sector's line intensity rides its own bin (`plasmaBuffer[(sector % 8u) + 1u].x` where sector = u32((angle / 6.28318 + 0.5) * 8.0)) so the speed lines pulse around the spectrum. Normalize the depth write `vec4(depth, 0.0, 0.0, 1.0)` -> `vec4(depth, 0.0, 0.0, 0.0)`; fix the stale header ('Category: image' -> artistic, comment-only).
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the hash11/noise1 helpers, the 16-tap zoom blur loop, the noise1(angle * lineDensity + time * lineSpeed) line construction, the centerMask, and the vignette VERBATIM. All 4 sliders honestly wired - keep roles EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.

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
  "id": "speed-lines-focus",
  "name": "Speed Lines Focus",
  "url": "shaders/speed-lines-focus.wgsl",
  "description": "Applies a radial zoom blur and manga-style speed lines focused on the mouse.",
  "params": [
    {
      "name": "Blur Strength",
      "type": "float",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "id": "blur_strength"
    },
    {
      "name": "Line Density",
      "type": "float",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "id": "line_density"
    },
    {
      "name": "Line Speed",
      "type": "float",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "id": "line_speed"
    },
    {
      "name": "Contrast",
      "type": "float",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "id": "contrast"
    }
  ],
  "features": [
    "mouse-driven",
    "audio-reactive",
    "upgraded-rgba"
  ],
  "tags": [
    "filter",
    "image-processing"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Blur Strength",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Line Density",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Line Speed",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Contrast",
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
//  Speed Lines Focus
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
  zoom_params: vec4<f32>,  // x=BlurStrength, y=LineDensity, z=LineSpeed, w=Contrast
  ripples: array<vec4<f32>, 50>,
};

fn hash11(p: f32) -> f32 {
    var p2 = fract(p * .1031);
    p2 *= p2 + 33.33;
    p2 *= p2 + p2;
    return fract(p2);
}

fn noise1(p: f32) -> f32 {
    var i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(hash11(i), hash11(i + 1.0), u);
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

    let aspect = resolution.x / resolution.y;
    var mouse = u.zoom_config.yz;

    // Params
    let blurStrength = u.zoom_params.x * 0.1 * (1.0 + bass * 0.2);
    let lineDensity = u.zoom_params.y * 50.0 + 10.0;
    let lineSpeed = u.zoom_params.z * 10.0 + 2.0;
    let contrast = (u.zoom_params.w + 0.5) * (1.0 + treble * 0.2);

    // Center on mouse
    let uvCenter = uv - mouse;
    let uvCenterAspect = vec2<f32>(uvCenter.x * aspect, uvCenter.y);
    let dist = length(uvCenterAspect);
    let angle = atan2(uvCenterAspect.y, uvCenterAspect.x);

    // 1. Zoom Blur
    var blurColor = vec3<f32>(0.0);
    let samples = 16;
    for (var i = 0; i < samples; i++) {
        let t = f32(i) / f32(samples - 1);
        let scale = 1.0 - t * blurStrength * dist;
        let sampleUV = mouse + uvCenter * scale;
        blurColor += textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
    }
    blurColor = blurColor / f32(samples);

    // 2. Speed Lines
    let n = noise1(angle * lineDensity + time * lineSpeed);
    let lines = smoothstep(0.6, 0.8, n);
    let centerMask = smoothstep(0.2, 0.5, dist);
    let lineEffect = lines * centerMask * contrast;

    // Composite
    var finalColor = blurColor + vec3<f32>(lineEffect);

    // Optional: Darken edges (Vignette)
    finalColor *= (1.0 - dist * 0.5);

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Alpha: preserve input transparency, blend to opaque based on effect intensity
    let effectIntensity = clamp(blurStrength * dist * 2.0 + lineEffect, 0.0, 1.0);
    let finalAlpha = mix(baseColor.a, 1.0, effectIntensity);

    textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
    textureStore(dataTextureA, coord, vec4<f32>(finalColor, finalAlpha));
}
```
