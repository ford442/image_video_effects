# Swarm Brief: kaleido-portal-interactive

**Role:** Visualist
**Name:** Kaleido Portal
**Category:** interactive-mouse
**Description:** A circular portal that reveals a kaleidoscopic view of the video, controlled by the mouse.
**Current lines:** 96
**Target lines:** 146–186 (expand by +50 to +90)

## Role Instructions

You are the Visualist. This portal's border glow can hit 7.0+ with no tonemap - tame the HDR, then give the portal glide and counter-rotating click bursts:
- CLAMP THE HDR BORDER (priority 1): `borderGlow = border * (5.0 + bass * 2.0)` is added raw to base.rgb - values up to ~7.0 in an rgba32float chain with no clamp. Add a hue-preserving clamp at ~1.5 on the glow contribution (or soft-knee `glow / (1.0 + glow * 0.35)`) so the border stays hot but legal; keep bass pumping it.
- Spring-damper the portal: ease the mouse center with a critically-damped spring (extraBuffer[133..134]) so the kaleidoscope glides; keep raw mouse as spring target.
- Click counter-rotation bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a decaying angular velocity spike (opposite sign per alternating ripple index) to the fold angle over ~2s, so clicks visibly kick the mandala into a spin.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the angle-fold kaleidoscope math (segmentAngle fold, aspect-corrected rel vector) VERBATIM - geometric correctness. dataTextureA stores (mask, border, segments/16, alpha) mask data - keep that packing. extraBuffer in [133..255] ONLY.

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
  "id": "kaleido-portal-interactive",
  "url": "shaders/kaleido-portal-interactive.wgsl",
  "icon": "circle",
  "description": "A circular portal that reveals a kaleidoscopic view of the video, controlled by the mouse.",
  "features": [
    "mouse-driven"
  ],
  "params": [
    {
      "id": "x",
      "name": "Radius",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "y",
      "name": "Segments",
      "default": 0.5,
      "min": 0,
      "max": 1
    },
    {
      "id": "z",
      "name": "Rotation",
      "default": 0.2,
      "min": 0,
      "max": 1
    },
    {
      "id": "w",
      "name": "Hardness",
      "default": 0.1,
      "min": 0,
      "max": 1
    }
  ],
  "tags": [
    "mouse-driven",
    "interactive"
  ],
  "name": "Kaleido Portal",
  "updatedParams": [
    {
      "index": 0,
      "name": "Radius",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Segments",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Rotation",
      "default": 0.2,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Hardness",
      "default": 0.1,
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
// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
// ═══════════════════════════════════════════════════════════════════
//  Kaleido Portal Interactive
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: kaleido-portal-interactive
//  Created: 2026-05-30
//  By: Copilot CLI
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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    let radius = mix(0.1, 0.5, u.zoom_params.x) * (1.0 + bass * 0.12);
    let segments = floor(mix(3.0, 16.0, u.zoom_params.y) + treble * 2.0);
    let rotationSpeed = u.zoom_params.z * (0.5 + mids * 0.6);
    let hardness = mix(0.01, 0.2, u.zoom_params.w);

    var mouse = u.zoom_config.yz;
    let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);
    let mask = 1.0 - smoothstep(radius, radius + hardness, dist);

    var finalUV = uv;

    if (mask > 0.0) {
        let rel = uv - mouse;
        let relCorrected = rel * vec2<f32>(aspect, 1.0);
        var angle = atan2(relCorrected.y, relCorrected.x);
        let rad = length(relCorrected);
        let segmentAngle = 6.2831853 / max(segments, 1.0);

        angle = angle + time * rotationSpeed;
        if (angle < 0.0) {
            angle = angle + 6.2831853;
        }

        var a = angle % segmentAngle;
        if (a > segmentAngle * 0.5) {
            a = segmentAngle - a;
        }

        let newDir = vec2<f32>(cos(a), sin(a));
        let newRelCorrected = newDir * rad;
        let newRel = vec2<f32>(newRelCorrected.x / aspect, newRelCorrected.y);
        let kaleidoUV = clamp(mouse + newRel, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
        finalUV = mix(uv, kaleidoUV, mask);
    }

    let border = smoothstep(radius, radius + 0.01, dist) * (1.0 - smoothstep(radius + 0.01, radius + 0.02 + hardness, dist));
    let borderGlow = border * (5.0 + bass * 2.0);
    let borderColor = vec3<f32>(0.5 + treble * 0.2, 0.8 + mids * 0.15, 1.0);

    let base = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);
    let finalColor = base.rgb + borderColor * borderGlow;
    let finalAlpha = clamp(base.a * (1.0 - mask * 0.25) + border * (0.32 + bass * 0.16) + mask * 0.18, 0.08, 1.0);
    let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, finalUV, 0.0).r + mask * 0.04, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(mask, border, segments / 16.0, finalAlpha));
}
```
