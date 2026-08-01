# Swarm Brief: codebreaker-reveal

**Role:** Interactivist
**Name:** Codebreaker Reveal
**Category:** interactive-mouse
**Description:** (no description field)
**Current lines:** 102
**Target lines:** 152–192 (expand by +50 to +90)

## Role Instructions

You are the Interactivist. This Matrix-rain reveal is honest - all four sliders are real - but the reveal circle snaps to the cursor and clicks are deaf. Make the reveal feel alive:
- Spring-damper the reveal center (priority 1): ease the mouse target with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the reveal circle sweeps after the cursor with momentum; the raw mouse stays the spring target. Keep the bass radius boost applied AFTER the spring so the punch stays instant.
- Click reveal bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple opens a temporary second reveal disc at its click point (same mask math as the cursor disc, radius growing then collapsing over ~1.5s, combined with the cursor mask via max()), so clicks punch holes in the code wall.
- Per-column treble shimmer: modulate each rain column's blink rate by a per-column FFT bin (`plasmaBuffer[(colIndex % 8u) + 1u].x` - note colIndex is f32, cast via u32(colIndex)) so the code wall glitters across the spectrum instead of blinking uniformly.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the hash12 helper, the matrix rain column/row math (fallSpeed, yFlow, charRandom, pixelCode), the luminance-driven matrixColor mix, and the edge ring glow VERBATIM - the code-wall identity is hand-tuned. Fix the stale comment config.y ('MouseClickCount' -> ripple count) comment-only. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.

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
  "id": "codebreaker-reveal",
  "url": "shaders/codebreaker-reveal.wgsl",
  "features": [
    "mouse-driven",
    "audio-reactive",
    "upgraded-rgba"
  ],
  "params": [
    {
      "id": "param1",
      "name": "Reveal Radius",
      "default": 0.3,
      "min": 0,
      "max": 1
    },
    {
      "id": "param2",
      "name": "Rain Speed",
      "default": 0.2,
      "min": 0,
      "max": 1
    },
    {
      "id": "param3",
      "name": "Code Density",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "param4",
      "name": "Glow Intensity",
      "default": 0.5,
      "min": 0,
      "max": 1
    }
  ],
  "tags": [
    "mouse-driven",
    "interactive"
  ],
  "name": "Codebreaker Reveal",
  "updatedParams": [
    {
      "index": 0,
      "name": "Reveal Radius",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Rain Speed",
      "default": 0.2,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Code Density",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Glow Intensity",
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
//  Codebreaker Reveal
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-17
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Radius, y=Speed, z=Density, w=Glow
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mousePos = u.zoom_config.yz;
    let time = u.config.x;

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Parameters — bass widens reveal radius
    let radius  = max(0.01, u.zoom_params.x * 0.4) * (1.0 + bass * 0.2);
    let speed   = u.zoom_params.y * 2.0 * (1.0 + mids * 0.3);
    let density = max(10.0, u.zoom_params.z * 150.0);
    let glow    = u.zoom_params.w * 2.0;

    let videoSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let videoColor  = videoSample.rgb;
    let luminance   = dot(videoColor, vec3<f32>(0.299, 0.587, 0.114));

    let aspect  = resolution.x / max(resolution.y, 0.001);
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist    = length(distVec);

    let mask = 1.0 - smoothstep(max(0.0, radius - 0.05), radius, dist);

    // Matrix rain
    let colIndex  = floor(uv.x * density);
    let colRandom = hash12(vec2<f32>(colIndex, 0.0));
    let fallSpeed = (0.5 + 0.5 * colRandom) * speed;
    let yFlow     = uv.y + time * fallSpeed;

    let rowDensity = density * aspect;
    let rowIndex   = floor(yFlow * rowDensity);
    let charRandom = hash12(vec2<f32>(colIndex, rowIndex));
    let cellUV     = fract(vec2<f32>(uv.x * density, yFlow * rowDensity));
    let pixelCode  = step(0.5, hash12(vec2<f32>(colIndex, rowIndex) + floor(cellUV * 3.0)));
    let blink      = step(0.95, fract(time * 5.0 + charRandom * 10.0));

    // Treble brightens the top of matrix characters
    var matrixColor = vec3<f32>(0.0, 1.0 + treble * 0.2, 0.4);
    matrixColor = mix(matrixColor, vec3<f32>(1.0), luminance * luminance);

    let codeBrightness = pixelCode * luminance;
    let finalMatrix    = matrixColor * codeBrightness * (1.0 + blink * glow);

    var finalColor = mix(finalMatrix, videoColor, mask);

    // Edge ring glow
    let ring = 1.0 - smoothstep(0.0, 0.02, abs(dist - radius));
    finalColor += vec3<f32>(0.5, 1.0, 0.8) * ring * glow;
    finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.0));

    // Depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Meaningful alpha: reveal mask blend + ring glow + bass
    let alpha = clamp((1.0 - mask) * 0.5 + ring * 0.4 + bass * 0.1 + videoSample.a * 0.1, 0.0, 1.0);
    let fc = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), fc);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), fc);
}
```
