# Swarm Brief: chroma-kinetic

**Role:** Optimizer
**Name:** Chroma Kinetic
**Category:** interactive-mouse
**Description:** Velocity chromatic aberration with directional smear and audio split. R channel leads, B lags based on motion direction; bass drives lead amount, mids drive smear glow. Directional motion trails sample along the velocity vector for cinematic motion blur.
**Current lines:** 117
**Target lines:** 167–207 (expand by +50 to +90)

## Role Instructions

You are the Optimizer. This velocity-chromatic smear is well-tuned - but the effect center snaps to the cursor and clicks never fire a kinetic burst. Precision work:
- Spring-damper the effect center (priority 1): ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the distortion field glides; raw mouse stays the spring target. The spring VELOCITY also feeds a small strength bonus (strength *= 1.0 + min(springSpeed * 3.0, 0.4)) so fast flicks smear harder - the shader is literally named kinetic.
- Click kinetic bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple fires a decaying directional smear pulse at its click point (local velocity boost exp(-rippleAge * 2.0) in an aspect-corrected ~0.25 radius, direction radial from the click, ~1.2s), so clicks punch motion trails.
- Per-sector FFT voices: divide the field into 8 angular sectors around the sprung center; each sector's smear mix (the finalR/G/B bass/mids/treble blends) rides its own bin (`plasmaBuffer[(sector % 8u) + 1u].x * 0.25`), so the chromatic trail shimmers directionally. Fix the stale comments (comment-only): config.y = ripple COUNT, zoom_config.w = mouseDown.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the bass_env helper, the rotation matrix + uvOffsetDir construction, the falloff/modFactor math, the lead/lag chromatic taps (uvR/uvG/uvB), the 3-sample smear loop with its (1.0 - t) weights, the per-channel smear mix structure, the depthMod, and the alpha formula VERBATIM - the velocity identity is hand-tuned. Sliders: luma_influence range is -2..2 (non-standard, keep EXACT), rotation default 0 - all ids/names/defaults/ranges EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.

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
  "id": "chroma-kinetic",
  "name": "Chroma Kinetic",
  "url": "shaders/chroma-kinetic.wgsl",
  "description": "Velocity chromatic aberration with directional smear and audio split. R channel leads, B lags based on motion direction; bass drives lead amount, mids drive smear glow. Directional motion trails sample along the velocity vector for cinematic motion blur.",
  "params": [
    {
      "id": "strength",
      "name": "Distortion Str",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "radius",
      "name": "Effect Radius",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "luma_influence",
      "name": "Luma Influence",
      "default": 1,
      "min": -2,
      "max": 2,
      "step": 0.01
    },
    {
      "id": "rotation",
      "name": "Direction Rot",
      "default": 0,
      "min": 0,
      "max": 1,
      "step": 0.01
    }
  ],
  "features": [
    "mouse-driven",
    "audio-reactive",
    "velocity-chromatic",
    "directional-smear",
    "upgraded-rgba"
  ],
  "tags": [
    "filter",
    "image-processing",
    "chromatic-aberration",
    "kinetic",
    "mouse",
    "motion-blur",
    "velocity"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Distortion Str",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Effect Radius",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Luma Influence",
      "default": 1,
      "min": -2.0,
      "max": 2.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Direction Rot",
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
//  Chroma Kinetic
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, velocity-chromatic, directional-smear, upgraded-rgba
//  Complexity: High
//  Chunks From: chroma-kinetic, bass_env, temporal-feedback
//  Created: 2026-05-10
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.4 + mids * 0.15;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthMod = mix(0.5, 1.5, depth);

    let strength = u.zoom_params.x * 0.1 * bass_env(bass, mids) * depthMod;
    let radius = u.zoom_params.y;
    let lumaInf = u.zoom_params.z;
    let rotation = u.zoom_params.w * 6.28318;

    let diff = uv - mousePos;
    let diffAspect = diff * vec2<f32>(aspect, 1.0);
    let dist = length(diffAspect);
    let dir = select(vec2<f32>(0.0), normalize(diffAspect), dist > 0.001);

    let c = cos(rotation);
    let s = sin(rotation);
    let rotDir = vec2<f32>(dir.x * c - dir.y * s, dir.x * s + dir.y * c);
    let uvOffsetDir = vec2<f32>(rotDir.x / max(aspect, 0.001), rotDir.y);

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(baseColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let falloff = smoothstep(max(radius, 0.001), 0.0, dist);
    let modFactor = max(0.0, 1.0 + (luma - 0.5) * lumaInf * 2.0);

    // Velocity chromatic aberration: R leads, B lags based on motion direction
    let velocity = uvOffsetDir * strength * falloff * modFactor;
    let leadAmount = velocity * (1.0 + bass * 0.5);
    let lagAmount = velocity * (1.0 + mids * 0.3);

    let uvR = clamp(uv - leadAmount, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvG = clamp(uv - velocity * 0.5, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvB = clamp(uv + lagAmount, vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;

    // Directional smear: sample along velocity vector for motion trails
    let smearSamples = 3;
    var smearR = 0.0;
    var smearG = 0.0;
    var smearB = 0.0;
    for (var i = 1; i <= smearSamples; i = i + 1) {
        let t = f32(i) / f32(smearSamples);
        let smearUV = clamp(uv + velocity * t * 2.0, vec2<f32>(0.0), vec2<f32>(1.0));
        let smearColor = textureSampleLevel(readTexture, u_sampler, smearUV, 0.0);
        smearR = smearR + smearColor.r * (1.0 - t);
        smearG = smearG + smearColor.g * (1.0 - t);
        smearB = smearB + smearColor.b * (1.0 - t);
    }
    smearR = smearR / f32(smearSamples);
    smearG = smearG / f32(smearSamples);
    smearB = smearB / f32(smearSamples);

    let finalR = mix(r, smearR, bass * 0.3);
    let finalG = mix(g, smearG, mids * 0.2);
    let finalB = mix(b, smearB, treble * 0.2);
    let color = vec3<f32>(finalR, finalG, finalB);

    // Audio split: bass shifts hue globally, mids add glow
    let dispersion = length(velocity) / max(strength, 0.001);
    let alpha = clamp(falloff * modFactor * 0.6 + dispersion * 0.3 + 0.1 + treble * 0.05, 0.0, 1.0);

    let finalRGBA = vec4<f32>(color, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalRGBA);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalRGBA);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```
