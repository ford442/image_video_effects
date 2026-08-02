# Swarm Brief: quantum-flux

**Role:** Visualist
**Name:** Quantum Flux
**Category:** interactive-mouse
**Description:** Simulates quantum instability and probability waves emanating from the mouse cursor, causing jitter and color drift.
**Current lines:** 117
**Target lines:** 167–207 (expand by +50 to +90)

## Role Instructions

You are the Visualist. This flux field's jitter/wave/split composition is honest - but the influence snaps to the cursor and clicks never collapse the field. Give it quantum behavior:
- Spring-damper the flux center (priority 1): ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the influence zone trails the cursor; raw mouse stays the spring target. Keep the existing aspect correction (uvCorrected/mouseCorrected).
- Click decoherence bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple spikes the jitter locally at its click point (a decaying +0.6 jitterAmount bump in an aspect-corrected ~0.25 radius smoothstep, exp(-rippleAge * 2.0), ~1.2s), so clicks make reality flicker without holding the cursor still.
- Per-region FFT voices: divide the influence zone into 8 angular sectors; each sector's jitter seed rides its own bin (`plasmaBuffer[(sector % 8u) + 1u].x * 0.3` modulating the jitter magnitude), so different wedges vibrate to different frequencies.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the rgb2hsv/hsv2rgb/rand helpers, the jitter/wave/split construction, the 3 chromatic tap offsets, the hue-drift driftMask gate, the interference scanlines, and the splitMag alpha formula VERBATIM - the flux identity is hand-tuned. All 4 sliders honestly wired - keep roles EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.

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
  "id": "quantum-flux",
  "name": "Quantum Flux",
  "url": "shaders/quantum-flux.wgsl",
  "description": "Simulates quantum instability and probability waves emanating from the mouse cursor, causing jitter and color drift.",
  "params": [
    {
      "id": "jitter",
      "name": "Flux Jitter",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "frequency",
      "name": "Wave Freq",
      "default": 0.4,
      "min": 0,
      "max": 1
    },
    {
      "id": "drift",
      "name": "Color Drift",
      "default": 0.3,
      "min": 0,
      "max": 1
    },
    {
      "id": "radius",
      "name": "Flux Radius",
      "default": 0.6,
      "min": 0,
      "max": 1
    }
  ],
  "features": [
    "mouse-driven",
    "distortion",
    "audio-reactive",
    "upgraded-rgba"
  ],
  "tags": [
    "mouse-driven",
    "interactive"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Flux Jitter",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Wave Freq",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Color Drift",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Flux Radius",
      "default": 0.6,
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
//  Quantum Flux
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    let p = mix(vec4<f32>(c.bg, K.wz), vec4<f32>(c.gb, K.xy), step(c.b, c.g));
    let q = mix(vec4<f32>(p.xyw, c.r), vec4<f32>(c.r, p.yzx), step(p.x, c.r));
    let d = q.x - min(q.w, q.y);
    let e = 1.0e-10;
    return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

fn rand(co: vec2<f32>) -> f32 {
    return fract(sin(dot(co, vec2<f32>(12.9898, 78.233))) * 43758.5453);
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

    // Params with audio modulation
    let jitterAmount = u.zoom_params.x * (1.0 + treble * 0.6);
    let freq = u.zoom_params.y * (1.0 + mids * 0.4);
    let driftSpeed = u.zoom_params.z * (1.0 + mids * 0.5);
    let radiusParam = u.zoom_params.w * (1.0 + bass * 0.3);

    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
    let mouseCorrected = vec2<f32>(mouse.x * aspect, mouse.y);
    let dist = distance(uvCorrected, mouseCorrected);

    let influenceRadius = radiusParam * 0.8 + 0.1;
    let influence = smoothstep(influenceRadius, 0.0, dist);

    let seed = uv + vec2<f32>(time * 0.1, time * 0.1);
    let noiseX = (rand(seed) - 0.5) * 2.0;
    let noiseY = (rand(seed + vec2<f32>(1.0, 1.0)) - 0.5) * 2.0;
    let jitter = vec2<f32>(noiseX, noiseY) * jitterAmount * 0.05 * influence;
    let wave = sin(dist * (freq * 50.0) - time * 5.0) * 0.02 * influence;

    let split = jitterAmount * 0.02 * influence;
    let uvR = clamp(uv + jitter + vec2<f32>(wave + split, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let uvG = clamp(uv - jitter + vec2<f32>(0.0, wave), vec2<f32>(0.0), vec2<f32>(1.0));
    let uvB = clamp(uv + jitter * 0.5 - vec2<f32>(split + wave, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

    let sR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0);
    let sG = textureSampleLevel(readTexture, u_sampler, uvG, 0.0);
    let sB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0);
    let baseSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    var color = vec3<f32>(sR.r, sG.g, sB.b);

    // Hue drift (branchless via mix on influence)
    var hsv = rgb2hsv(color);
    hsv.x = fract(hsv.x + (time * driftSpeed * 0.5) + (dist * 2.0));
    hsv.y = min(1.0, hsv.y + influence * 0.2);
    let driftedColor = hsv2rgb(hsv);
    let driftMask = clamp(driftSpeed * 10.0, 0.0, 1.0) * smoothstep(0.0, 0.01, influence);
    color = mix(color, driftedColor, driftMask);

    // Interference scanlines
    let interference = sin(uv.y * resolution.y * 0.5 + time * 10.0) * 0.5 + 0.5;
    color = mix(color, color * (0.8 + 0.2 * interference), influence * 0.5);

    // Meaningful alpha: blend weight from influence + chromatic split + base alpha
    let splitMag = abs(sR.r - sB.b) + abs(sG.g - sR.r);
    let alpha = clamp(baseSample.a * 0.5 + influence * 0.3 + splitMag * 0.4 + treble * 0.1, 0.0, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, coord, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(color, alpha));
}
```
