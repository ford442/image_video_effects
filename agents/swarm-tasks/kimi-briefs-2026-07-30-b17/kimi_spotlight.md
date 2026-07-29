# Swarm Brief: kimi_spotlight

**Role:** Interactivist
**Name:** Kimi Spotlight
**Category:** interactive-mouse
**Description:** Flashlight effect that reveals full color under the beam while surroundings are desaturated and darkened. Audio-reactive spotlight size pulses with bass.
**Current lines:** 94
**Target lines:** 144–184 (expand by +50 to +90)

## Role Instructions

You are the Interactivist. This spotlight is honest but static-feeling - give it glide, click rings, and honest depth:
- Spring-damper the spotlight (priority 1): ease the mouse target with a critically-damped spring (extraBuffer[133..134], [0..4] reserved, [5..132] = engine FFT) so the beam sweeps with weight instead of snapping 1:1 to the cursor; keep the existing mouseDown clickPulse applied AFTER the spring.
- Click light rings: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple emits an expanding luminous ring from its click point (radius ~ age * 0.4, intensity decays over ~2s) that locally lifts the desaturated darkness, so clicks flash-reveal the scene.
- Honest depth + audio rim: write a real depth bump inside the spot (spotlight * 0.05) instead of pure passthrough, and let per-bin treble (`plasmaBuffer[1..8]` high bins) flicker the beam rim band rather than only the global treble alpha term.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the desaturate-outside / saturate-inside mix structure, the beam ring band (dist - spotSize*0.8), and the hotspot term VERBATIM - the stage-light look is hand-tuned. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.

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
  "id": "kimi-spotlight",
  "name": "Kimi Spotlight",
  "url": "shaders/kimi_spotlight.wgsl",
  "description": "Flashlight effect that reveals full color under the beam while surroundings are desaturated and darkened. Audio-reactive spotlight size pulses with bass.",
  "features": [
    "mouse-driven",
    "interactive",
    "spotlight",
    "reveal",
    "audio-reactive",
    "upgraded-rgba"
  ],
  "params": [
    {
      "id": "spotSize",
      "name": "Spotlight Size",
      "min": 0,
      "max": 1,
      "default": 0.5,
      "step": 0.01
    },
    {
      "id": "spotSoftness",
      "name": "Edge Softness",
      "min": 0,
      "max": 1,
      "default": 0.3,
      "step": 0.01
    },
    {
      "id": "edgeDarkness",
      "name": "Edge Darkness",
      "min": 0,
      "max": 1,
      "default": 0.7,
      "step": 0.01
    },
    {
      "id": "saturationBoost",
      "name": "Color Boost",
      "min": 0,
      "max": 1,
      "default": 0.5,
      "step": 0.01
    }
  ],
  "tags": [
    "mouse-driven",
    "interactive",
    "spotlight",
    "reveal",
    "audio-reactive"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Spotlight Size",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Edge Softness",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Edge Darkness",
      "default": 0.7,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Color Boost",
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
//  Kimi Spotlight
//  Category: interactive-mouse
//  Features: mouse-driven, interactive, spotlight, reveal, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-06-28
//  By: Agent 1a - Alpha Channel Specialist
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
    let coords = vec2<i32>(global_id.xy);
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    let aspect = resolution.x / resolution.y;
    let p = vec2<f32>(uv.x * aspect, uv.y);
    let mousePos = vec2<f32>(mouse.x * aspect, mouse.y);

    let dist = length(p - mousePos);

    let spotSize = mix(0.1, 0.6, clamp(u.zoom_params.x, 0.0, 1.0)) * (1.0 + bass * 0.15 + mids * 0.05);
    let spotSoftness = max(mix(0.001, 0.5, clamp(u.zoom_params.y, 0.0, 1.0)), 0.001);
    let edgeDarkness = mix(0.1, 1.0, clamp(u.zoom_params.z, 0.0, 1.0));
    let saturationBoost = mix(1.0, 3.0, clamp(u.zoom_params.w, 0.0, 1.0));

    var spotlight = 1.0 - smoothstep(spotSize - spotSoftness, spotSize + spotSoftness, dist);

    let clickPulse = mouseDown * sin(time * 10.0) * 0.1;
    spotlight = clamp(min(1.0, spotlight + clickPulse), 0.0, 1.0);

    let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    let gray = dot(original.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let desaturated = vec3<f32>(gray) * 0.3;

    let luminance = dot(original.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let saturated = mix(vec3<f32>(luminance), original.rgb, saturationBoost);

    var color = mix(desaturated * edgeDarkness, saturated, spotlight);

    let beamWidth = max(spotSize * 0.1, 0.001);
    let beamDist = abs(dist - spotSize * 0.8);
    let beam = smoothstep(beamWidth, 0.0, beamDist) * 0.2 * spotlight;
    color = color + vec3<f32>(0.9, 0.95, 1.0) * beam;

    let hotspot = smoothstep(spotSize * 0.3, 0.0, dist) * 0.3;
    color = color + vec3<f32>(hotspot);

    let noise = fract(sin(dot(uv * max(time, 0.001), vec2<f32>(12.9898, 78.233))) * 43758.5453);
    color = color + (noise - 0.5) * 0.02 * (1.0 - spotlight);

    color = clamp(color, vec3<f32>(0.0), vec3<f32>(1.0));

    let alpha = clamp(original.a * (spotlight * 0.7 + hotspot * 0.2 + beam * 0.1 + 0.15 + treble * 0.05), 0.0, 1.0);

    let finalRGBA = vec4<f32>(color, alpha);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, coords, finalRGBA);
    textureStore(dataTextureA, global_id.xy, finalRGBA);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```
