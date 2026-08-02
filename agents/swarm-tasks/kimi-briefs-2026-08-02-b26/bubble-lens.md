# Swarm Brief: bubble-lens

**Role:** Visualist
**Name:** Bubble Lens
**Category:** distortion
**Description:** A thin-film soap bubble lens magnifies the source image and blooms into beat-reactive interference colors around the cursor.
**Current lines:** 116
**Target lines:** 166–206 (expand by +50 to +90)

## Role Instructions

You are the Visualist. This bubble's thin-film drainage and fresnel rim are genuinely physical - but the bubble snaps to the cursor and clicks never pop it. Give the soap some life:
- Spring-damper the bubble (priority 1): ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the bubble floats after the cursor with buoyancy; raw mouse stays the spring target. Keep the aspect-corrected delta.
- Click pops and satellite bubbles: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple spawns a small satellite bubble at its click point (radius ~0.06 growing then popping over ~1.2s - reuse the same lens displacement + interference evaluation at reduced strength) AND pops a brief film-shockwave on the main bubble (drainedThickness perturbation ring expanding from the click side), so clicks ripple the soap film.
- Per-octave FFT shimmer: modulate the two turbulence noise octaves by different bins (plasmaBuffer[2].x for the broad octave, plasmaBuffer[6].x for the fine octave, +-15%), so the film interference dances across the spectrum; keep audio.x on filmThickness and audio.y on spec as now.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: dataTextureA stores MASK data (inside, drainedThickness*0.2, spec, finalAlpha) - NOT display color - keep that packing VERBATIM. Preserve the safeNormalize helper, the lens displacement math, the drainage/turbulence/drainedThickness construction, the 3-phase interference cosines + blackSpot, the fresnel (Schlick from ior), the rim/spec terms, and the transmittance/alpha clamps VERBATIM - the soap physics are hand-tuned. All 4 sliders honestly wired - keep roles EXACTLY. extraBuffer in [133..255] ONLY.

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
  "id": "bubble-lens",
  "name": "Bubble Lens",
  "category": "distortion",
  "url": "shaders/bubble-lens.wgsl",
  "description": "A thin-film soap bubble lens magnifies the source image and blooms into beat-reactive interference colors around the cursor.",
  "features": [
    "mouse-driven",
    "audio-reactive",
    "upgraded-rgba"
  ],
  "tags": [
    "bubble",
    "soap",
    "interference",
    "lens",
    "audio-reactive"
  ],
  "params": [
    {
      "id": "bubble_size",
      "name": "Bubble Size",
      "default": 0.45,
      "min": 0,
      "max": 1
    },
    {
      "id": "magnification",
      "name": "Magnification",
      "default": 0.55,
      "min": 0,
      "max": 1
    },
    {
      "id": "film_thickness",
      "name": "Film Thickness",
      "default": 0.45,
      "min": 0,
      "max": 1
    },
    {
      "id": "ior",
      "name": "IOR",
      "default": 0.5,
      "min": 0,
      "max": 1
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Bubble Size",
      "default": 0.45,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Magnification",
      "default": 0.55,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Film Thickness",
      "default": 0.45,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "IOR",
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
// ================================================================
//  Bubble Lens
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba, thin-film
//  Complexity: Medium
//  Chunks From: bubble-lens
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
  zoom_params: vec4<f32>,  // x=BubbleSize, y=Magnification, z=FilmThickness, w=IOR
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

fn safeNormalize(v: vec2<f32>) -> vec2<f32> {
  let lenSq = max(dot(v, v), 1e-6);
  return v * inverseSqrt(lenSq);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / dims;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let aspect = dims.x / dims.y;
  let audio = plasmaBuffer[0].xyz;

  let bubbleRadius = mix(0.10, 0.42, u.zoom_params.x);
  let magnification = mix(1.05, 4.0, u.zoom_params.y);
  let filmThickness = mix(0.25, 2.5, u.zoom_params.z) * (1.0 + audio.x * 0.25);
  let ior = mix(1.15, 1.65, u.zoom_params.w);

  let delta = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(delta);
  let inside = 1.0 - smoothstep(bubbleRadius, bubbleRadius + 0.02, dist);
  let factor = clamp(dist / max(bubbleRadius, 1e-4), 0.0, 1.0);
  let direction = safeNormalize(delta);

  let lensStrength = (1.0 - factor * factor) * (magnification - 1.0);
  let displacement = direction * lensStrength * bubbleRadius * (1.0 - factor);
  let warpedUV = clamp(uv - displacement / vec2<f32>(aspect, 1.0), vec2<f32>(0.0), vec2<f32>(1.0));

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let bubbleSample = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0);

  let drainage = clamp(0.5 + delta.y / max(bubbleRadius, 1e-4) * 0.5 + sin(time * 0.45) * 0.04, 0.0, 1.0);
  let turbulence = noise(warpedUV * 8.0 + vec2<f32>(0.0, -time * 0.25))
    * 0.6 + noise(warpedUV * 15.0 - vec2<f32>(time * 0.1, 0.0)) * 0.4;
  let drainedThickness = filmThickness * (0.14 + drainage * 1.6) * (0.75 + turbulence * 0.6);
  let phase = drainedThickness * 9.0 * (1.0 - factor * 0.45) + audio.z * 2.0;

  var interference = vec3<f32>(
    0.5 + 0.5 * cos(phase),
    0.5 + 0.5 * cos(phase + 2.09),
    0.5 + 0.5 * cos(phase + 4.18)
  );
  let blackSpot = smoothstep(0.12, 0.0, drainedThickness);
  interference = mix(interference, vec3<f32>(0.03, 0.03, 0.04), blackSpot);

  let fresnelBase = pow((ior - 1.0) / (ior + 1.0), 2.0);
  let cosTheta = max(dot(-direction, vec2<f32>(0.0, 1.0)), 0.0);
  let fresnel = fresnelBase + (1.0 - fresnelBase) * pow(1.0 - cosTheta, 5.0);
  let rim = smoothstep(0.65, 1.0, factor) * inside;
  let spec = pow(max(0.0, 1.0 - factor), 4.0) * (0.25 + audio.y * 0.6);

  var bubbleColor = bubbleSample.rgb;
  bubbleColor = mix(bubbleColor, bubbleSample.rgb * interference * 1.2, 0.35 + fresnel * 0.35);
  bubbleColor = bubbleColor + vec3<f32>(1.0, 0.95, 0.92) * spec + interference * rim * 0.18;

  let transmittance = exp(-drainedThickness * 0.35) * (0.85 + fresnel * 0.15);
  let finalColor = mix(src.rgb, bubbleColor, inside);
  let finalAlpha = clamp(mix(src.a, transmittance, inside) + inside * (0.14 + rim * 0.08), 0.08, 0.98);
  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, warpedUV, 0.0).r;
  let outDepth = clamp(mix(textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r, baseDepth, inside), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(inside, drainedThickness * 0.2, spec, finalAlpha));
}
```
