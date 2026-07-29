# Swarm Brief: neural-resonance

**Role:** Algorithmist
**Name:** Neural Resonance
**Category:** artistic
**Description:** A temporal synaptic feedback field bends the source image into chromatic neural currents around the cursor.
**Current lines:** 100
**Target lines:** 150–190 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. This shader's feedback loop is drinking its own mask buffer - dataTextureA stores MASKS (mouseMask, feedbackMix, |curl|*10) but dataTextureC (prev A) is read back as COLOR, so the temporal feedback mixes masks into the display (spore-galaxy bug class). Fix the plumbing:
- FIX THE MASK-AS-COLOR FEEDBACK (priority 1): write the DISPLAY color to dataTextureA (so C = previous frame's color, which is what the feedback path expects) and move the mask quad (mouseMask, feedbackMix, |curl|*10, alpha) to dataTextureB. Same fix as Batch 14's spore-galaxy. After the fix, verify feedbackMix blending reads as intended (default 0.55 -> mix factor mix(0.25,0.96,0.55) ~ 0.64) and the |curl|*10 blue-channel garbage is out of the display path.
- Spring-damper the mouse mask: ease the mouse center with a critically-damped spring (extraBuffer[133..134]) so the warp emphasis glides; raw mouse stays the spring target.
- Click resonance rings: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple injects a decaying expanding ring into the feedback (a bright synapseTint band at radius age*0.5, ~1.5s fade) centered on its click point, so clicks ring through the resonance.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the curlField/noise helpers, the aspect-corrected warp, and the synapseTint sin() palette VERBATIM. dataTextureA becomes DISPLAY color (raw, never tonemapped); dataTextureB becomes the mask quad (keep the same 4 values in the same order). extraBuffer in [133..255] ONLY.

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
  "id": "neural-resonance",
  "name": "Neural Resonance",
  "category": "artistic",
  "url": "shaders/neural-resonance.wgsl",
  "description": "A temporal synaptic feedback field bends the source image into chromatic neural currents around the cursor.",
  "features": [
    "mouse-driven",
    "audio-reactive",
    "upgraded-rgba",
    "temporal"
  ],
  "tags": [
    "neural",
    "feedback",
    "chromatic",
    "synapse",
    "audio-reactive"
  ],
  "params": [
    {
      "id": "amplification",
      "name": "Amplification",
      "default": 0.45,
      "min": 0,
      "max": 1
    },
    {
      "id": "curl_strength",
      "name": "Curl Strength",
      "default": 0.45,
      "min": 0,
      "max": 1
    },
    {
      "id": "feedback_mix",
      "name": "Feedback Mix",
      "default": 0.55,
      "min": 0,
      "max": 1
    },
    {
      "id": "chromatic_drift",
      "name": "Chromatic Drift",
      "default": 0.35,
      "min": 0,
      "max": 1
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Amplification",
      "default": 0.45,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Curl Strength",
      "default": 0.45,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Feedback Mix",
      "default": 0.55,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Chromatic Drift",
      "default": 0.35,
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
// ================================================================
//  Neural Resonance
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba, temporal
//  Complexity: Medium
//  Chunks From: neural-resonance
//  Created: 2026-05-31
//  By: Copilot
// ================================================================

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
  zoom_params: vec4<f32>,  // x=Amplification, y=CurlStrength, z=FeedbackMix, w=ChromaticDrift
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let a = hash12(i);
  let b = hash12(i + vec2<f32>(1.0, 0.0));
  let c = hash12(i + vec2<f32>(0.0, 1.0));
  let d = hash12(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn curlField(p: vec2<f32>, t: f32) -> vec2<f32> {
  let e = 0.01;
  let n1 = noise(p + vec2<f32>(0.0, e) + t);
  let n2 = noise(p - vec2<f32>(0.0, e) + t);
  let n3 = noise(p + vec2<f32>(e, 0.0) - t);
  let n4 = noise(p - vec2<f32>(e, 0.0) - t);
  return vec2<f32>(n1 - n2, -(n3 - n4)) / (2.0 * e);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / dims;
  let mouse = u.zoom_config.yz;
  let aspect = dims.x / dims.y;
  let time = u.config.x;
  let audio = plasmaBuffer[0].xyz;

  let amplification = mix(0.15, 1.35, u.zoom_params.x) * (1.0 + audio.x * 0.45);
  let curlStrength = mix(0.005, 0.08, u.zoom_params.y);
  let feedbackMix = mix(0.25, 0.96, u.zoom_params.z);
  let chromaticDrift = mix(0.0, 0.03, u.zoom_params.w);

  let aspectUV = uv * vec2<f32>(aspect, 1.0);
  let mouseDelta = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let mouseMask = 1.0 - smoothstep(0.0, 0.65, length(mouseDelta));
  let curl = curlField(aspectUV * (2.0 + amplification), time * 0.15) * curlStrength;
  let warpedUV = clamp(uv + curl / vec2<f32>(aspect, 1.0) * (0.4 + mouseMask * 1.2), vec2<f32>(0.0), vec2<f32>(1.0));

  let source = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0);
  let feedback = textureSampleLevel(dataTextureC, u_sampler, warpedUV, 0.0);
  let split = curl * chromaticDrift * (0.8 + audio.z * 0.6);
  let chroma = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, clamp(warpedUV + split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r,
    source.g,
    textureSampleLevel(readTexture, u_sampler, clamp(warpedUV - split, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b
  );

  let synapseTint = mix(vec3<f32>(0.10, 0.75, 1.0), vec3<f32>(1.0, 0.35, 0.85), 0.5 + 0.5 * sin(time * 0.7 + noise(aspectUV * 4.0) * 6.28318));
  var finalColor = mix(chroma, feedback.rgb, feedbackMix * (0.4 + mouseMask * 0.6));
  finalColor = mix(finalColor, finalColor + synapseTint * (0.08 + audio.y * 0.18), 0.55);

  let finalAlpha = clamp(mix(source.a, feedback.a, feedbackMix) + mouseMask * 0.12, 0.02, 0.98);
  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, warpedUV, 0.0).r;
  let outDepth = clamp(mix(baseDepth, 0.24 + mouseMask * 0.58, 0.22), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(mouseMask, feedbackMix, length(curl) * 10.0, finalAlpha));
}
```
