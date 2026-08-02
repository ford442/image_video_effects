# Swarm Brief: magnetic-ring

**Role:** Interactivist
**Name:** Magnetic Ring
**Category:** interactive-mouse
**Description:** (no description field)
**Current lines:** 102
**Target lines:** 152–192 (expand by +50 to +90)

## Role Instructions

You are the Interactivist. These field rings are honestly wired (the JSON even carries explicit mapping fields) - but the ring center snaps to the cursor, clicks do nothing, and all three rings follow the same global audio bands. Make it magnetic for real:
- Spring-damper the ring center (priority 1): ease the mouse target with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the ring system drags after the cursor like a real magnet; raw mouse stays the spring target. Keep the aspect correction applied to the SPRUNG position.
- Click flux shockwaves: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a temporary fourth ring expanding from its click point (ringMask += decaying smoothstep band at radius age*0.4, ~1.5s fade) plus a local pulse boost, so clicks fire flux surges across the field.
- Per-ring FFT voices: drive ring i's pulse/glow from its own spectrum bin (`plasmaBuffer[i + 1u].x` for i in 0..2 - bass/mids/treble neighbors) instead of the single global `pulse`, so the concentric rings throb at different frequencies; the z slider stays the global pulse speed.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the hash21/bass_env helpers, the 3-ring loop structure (radii baseRadius*(1+i*0.6), fieldAngle 8/(i+1) spokes), the safeDir normalize guard, and the chromatic rUV/gUV/bUV tap structure VERBATIM. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.

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
  "id": "magnetic-ring",
  "url": "shaders/magnetic-ring.wgsl",
  "features": [
    "mouse-driven"
  ],
  "params": [
    {
      "id": "base_radius",
      "name": "Base Radius",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x",
      "description": "Base radius of the magnetic ring"
    },
    {
      "id": "strength",
      "name": "Distortion Strength",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y",
      "description": "Strength of the distortion effect"
    },
    {
      "id": "pulse_speed",
      "name": "Pulse Speed",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z",
      "description": "Speed of the ring pulse animation"
    },
    {
      "id": "ring_thickness",
      "name": "Ring Thickness",
      "default": 0.3,
      "min": 0.01,
      "max": 0.3,
      "step": 0.01,
      "mapping": "zoom_params.w",
      "description": "Thickness of the magnetic ring"
    }
  ],
  "tags": [
    "filter",
    "image-processing"
  ],
  "name": "Magnetic Ring",
  "updatedParams": [
    {
      "index": 0,
      "name": "Base Radius",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Distortion Strength",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Pulse Speed",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Ring Thickness",
      "default": 0.3,
      "min": 0.01,
      "max": 0.3,
      "step": 0.01
    }
  ],
  "updated": true
}
```

## Current WGSL Code

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  Magnetic Ring
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, magnetic-field, particle-trails, upgraded-rgba
//  Complexity: High
//  Chunks From: magnetic-ring, bass_env, hash21
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mousePos = u.zoom_config.yz;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let baseRadius = mix(0.02, 0.45, u.zoom_params.x);
    let strength = u.zoom_params.y * bass_env(bass, mids);
    let pulseSpeed = mix(0.5, 8.0, u.zoom_params.z);
    let ringThickness = mix(0.01, 0.18, u.zoom_params.w);

    let dVec = uv - mousePos;
    let dVecAspect = vec2<f32>(dVec.x * aspect, dVec.y);
    let dist = length(dVecAspect);
    let safeDir = dVecAspect / max(dist, 0.001);
    let pulse = sin(time * pulseSpeed * bass_env(bass, mids) - dist * 20.0) * 0.5 + 0.5;

    // Multiple concentric rings for field line effect
    let rings = 3.0;
    var ringMask = 0.0;
    var fieldLines = 0.0;
    for (var i: f32 = 0.0; i < rings; i = i + 1.0) {
      let r = baseRadius * (1.0 + i * 0.6);
      let m = 1.0 - smoothstep(0.0, ringThickness, abs(dist - r));
      ringMask = ringMask + m;
      let fieldAngle = atan2(dVecAspect.y, dVecAspect.x) + i * 1.047;
      let fl = smoothstep(0.0, 0.05, abs(fract(fieldAngle * 8.0 / (i + 1.0)) - 0.5)) * m;
      fieldLines = fieldLines + fl;
    }
    ringMask = clamp(ringMask, 0.0, 1.0);

    let displacement = safeDir * ringMask * strength * (0.03 + pulse * 0.04);
    let offsetUV = vec2<f32>(displacement.x / aspect, displacement.y);

    let baseUV = clamp(uv + offsetUV, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
    let rgbOffset = offsetUV * (0.35 + strength * 0.85);
    let rUV = clamp(uv + rgbOffset, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
    let gUV = baseUV;
    let bUV = clamp(uv - rgbOffset, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));

    let gColor = textureSampleLevel(readTexture, u_sampler, gUV, 0.0);
    let ringGlow = vec3<f32>(0.2 + treble * 0.1, 0.4 + mids * 0.1, 0.7) * ringMask * (0.3 + pulse * 0.7);
    let fieldGlow = vec3<f32>(0.1, 0.8, 1.0) * fieldLines * pulse * 0.5;
    let finalColor = vec3<f32>(
        textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r,
        gColor.g,
        textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b
    ) + ringGlow + fieldGlow;

    let alpha = clamp(gColor.a * 0.45 + ringMask * 0.3 + bass * 0.05 + fieldLines * 0.1, 0.08, 1.0);
    let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r + ringMask * 0.05, 0.0, 1.0);
    let finalPixel = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalPixel);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalPixel);
}
```
