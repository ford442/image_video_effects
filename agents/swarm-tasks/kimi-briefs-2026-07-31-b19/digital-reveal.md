# Swarm Brief: digital-reveal

**Role:** Algorithmist
**Name:** Digital Rain Reveal
**Category:** interactive-mouse
**Description:** Hides the image behind chromatic digital rain; move the mouse to reveal content. Audio shifts rain colors (bass green, treble white). Depth makes near objects reveal faster.
**Current lines:** 102
**Target lines:** 152–192 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. This rain-reveal has a real feedback trail (A=mask, C=prev mask - consistent, keep it) and honest sliders, but the brush snaps to the cursor, clicks do nothing, and the uniform comments lie. Tighten it up:
- Spring-damper the reveal brush (priority 1): ease the mouse target with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the brush paints with inertia; raw mouse stays the spring target. The feedback trail then naturally records swooping strokes.
- Click splash reveals: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple stamps a decaying reveal blob at its click point into the mask (`newVal = max(newVal, rippleBlob)` before the A write, radius ~0.15, ~2s fade), so single clicks splash-reveal content that then fades with trailFade.
- Honest depth-gated rain: `depthReveal` currently scales the mask only - also let depth subtly scale the rain glyph brightness in unrevealed regions (`rainColor *= mix(1.0, mix(0.6, 1.2, depth), 0.4)`) so near content glows through the rain, earning the 'depth-aware' feature tag. Fix the stale comments (comment-only): config.y = ripple COUNT (not 'MouseClickCount'), zoom_config.w = mouseDown (not 'Generic2').
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the hash22/bass_env helpers, the mask feedback contract (dataTextureA stores (newVal,0,0,1); dataTextureC.r read as prev mask - it is NOT display color, never tonemap it), the rain column/charID/dropVal math, and the chromatic white-drop branch VERBATIM. All 4 sliders are honestly wired - keep their roles EXACTLY. extraBuffer in [133..255] ONLY.

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
  "id": "digital-reveal",
  "name": "Digital Rain Reveal",
  "category": "interactive-mouse",
  "url": "shaders/digital-reveal.wgsl",
  "description": "Hides the image behind chromatic digital rain; move the mouse to reveal content. Audio shifts rain colors (bass green, treble white). Depth makes near objects reveal faster.",
  "params": [
    {
      "id": "density",
      "name": "Rain Density",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "size",
      "name": "Reveal Size",
      "default": 0.3,
      "min": 0,
      "max": 1
    },
    {
      "id": "fade",
      "name": "Trail Fade",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "speed",
      "name": "Rain Speed",
      "default": 0.5,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
    "mouse-driven",
    "audio-reactive",
    "depth-aware",
    "upgraded-rgba",
    "temporal-digital-rain",
    "chromatic-drops"
  ],
  "tags": [
    "filter",
    "image-processing",
    "digital-rain",
    "reveal",
    "audio-reactive",
    "depth-aware",
    "chromatic",
    "temporal"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Rain Density",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Reveal Size",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Trail Fade",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Rain Speed",
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
//  Digital Reveal
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, temporal-digital-rain, depth-reveal, chromatic-drops, upgraded-rgba
//  Complexity: High
//  Chunks From: digital-reveal, bass_env, hash22
//  Created: 2024-01-01
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx+p3.yz)*p3.zy);
}

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthReveal = mix(0.3, 1.0, depth);

    let density = u.zoom_params.x * bass_env(bass, mids);
    let revealSize = u.zoom_params.y;
    let trailFade = u.zoom_params.z;
    let rainSpeed = u.zoom_params.w * (1.0 + treble * 0.5);

    let prevVal = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;

    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
    let mouseCorrected = vec2<f32>(mouse.x * aspect, mouse.y);
    let dist = distance(uvCorrected, mouseCorrected);

    let brushRadius = revealSize * 0.3 + 0.05;
    let brush = smoothstep(brushRadius, brushRadius * 0.5, dist);

    let fadeFactor = 0.8 + trailFade * 0.19;
    let newVal = max(prevVal * fadeFactor, brush) * depthReveal;

    textureStore(dataTextureA, global_id.xy, vec4<f32>(newVal, 0.0, 0.0, 1.0));

    let gridSize = vec2<f32>(20.0, 20.0 * aspect) * (1.0 + density * 2.0);
    let cellUV = fract(uv * gridSize);
    let cellID = floor(uv * gridSize);

    let colSpeed = hash22(vec2<f32>(cellID.x, 0.0)).y * (rainSpeed * 5.0 + 1.0);
    let verticalPos = cellID.y + time * colSpeed;
    let charID = floor(verticalPos);
    let dropVal = fract(verticalPos);
    let charBright = smoothstep(0.0, 0.2, dropVal) * smoothstep(1.0, 0.8, dropVal);
    let flicker = step(0.1, hash22(vec2<f32>(cellID.x, charID)).x);

    // Chromatic drops: bass shifts green, treble shifts cyan/white highlights
    var rainColor = vec3<f32>(0.0, 1.0, 0.2) * charBright * flicker;
    rainColor.g = rainColor.g + bass * 0.3 * charBright;
    if (hash22(vec2<f32>(cellID.x, charID)).y > 0.98 - density * 0.1) {
        rainColor = vec3<f32>(0.8 + treble * 0.2, 1.0, 0.8 + treble * 0.2);
    }

    let imageColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let finalColor = mix(rainColor, imageColor, clamp(newVal, 0.0, 1.0));
    let alpha = clamp(newVal + charBright * 0.2 + bass * 0.05, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```
