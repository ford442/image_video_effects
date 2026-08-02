# Swarm Brief: neon-edge-reveal

**Role:** Algorithmist
**Name:** Neon Edge Reveal
**Category:** visual-effects
**Description:** Neon edge detection with interactive flashlight reveal.
**Current lines:** 104
**Target lines:** 154–194 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. Every one of this shader's four slider labels is a placeholder - 'Intensity' drives the reveal radius, 'Speed' drives edge boost, 'Scale' drives glow, and 'Detail' only tweaks alpha. Meanwhile the emission is unclamped HDR that can hit ~20x. Rewire honest, then tame the blowout:
- REWIRE THE GENERIC LABELS (priority 1 - saved-preset contract: ids/names/defaults stay EXACTLY, only the WGSL roles change; default 0.5 must reproduce the current look): x ('Intensity', 0.5) -> emission/glow intensity (takes over glowIntensity's role: *2.0 mapping, default = x1.0); y ('Speed', 0.5) -> the neon hue-cycle speed (currently hardcoded time*2.0 - map mix(0.0, 4.0, y), default 0.5 = 2.0 bit-identical); z ('Scale', 0.5) -> reveal radius scale (takes over revealRadius's role: (0.2 + z * 0.3), default = 0.35 exactly as today); w ('Detail', 0.5) -> edge detail (Sobel smoothstep window: smoothstep(mix(0.10, 0.02, w), mix(0.5, 0.15, w), edgeStrength), default 0.5 = current 0.05/0.3 window). The old edgeBoost role folds into the emission chain as a constant 1.0 factor (its (1.0 + treble * 0.3) audio term moves onto the emission). occlusionBalance's alpha role can stay on w's alpha term OR ride along - document your choice.
- TAME THE HDR: the emission chain neonColor * glow * edge * edgeBoost * glowIntensity can reach ~19.8 - add a hue-preserving soft-knee (e.g. e / (1.0 + max(e - 1.5, 0.0) * 0.5) per-channel-max style, or the huePreserveClamp pattern) capping ~1.5-2.0 so the neon blows out gracefully instead of clipping to white.
- Click flare bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple flashes the reveal (temporary revealFalloff boost at its click point, ~1.2s fade) so edges near clicks ignite. Spring-damper the flashlight (extraBuffer[133..136]) so the beam glides.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the 9-tap Sobel (full vec4 neighbor samples, clamped), the neonColor1/2 palette + mixFactor cycling structure, and the branchless emission style VERBATIM - only the hardcoded speed constant and the param roles change. Fix the stale header comment ('Category: lighting-effects' -> visual-effects, comment-only). dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.

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
  "id": "neon-edge-reveal",
  "name": "Neon Edge Reveal",
  "url": "shaders/neon-edge-reveal.wgsl",
  "description": "Neon edge detection with interactive flashlight reveal.",
  "params": [
    {
      "id": "param1",
      "name": "Intensity",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param2",
      "name": "Speed",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param3",
      "name": "Scale",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param4",
      "name": "Detail",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    }
  ],
  "features": [
    "mouse-driven",
    "audio-reactive",
    "audio-driven",
    "upgraded-rgba"
  ],
  "tags": [
    "filter",
    "image-processing",
    "audio",
    "music",
    "reactive"
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Intensity",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Speed",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Scale",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Detail",
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
//  Neon Edge Reveal
//  Category: lighting-effects
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

fn getLuminance(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }

    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audioReactivity = 1.0 + mids * 0.3;

    // Params
    let revealRadius = (0.2 + u.zoom_params.x * 0.3) * (1.0 + bass * 0.4);
    let edgeBoost = u.zoom_params.y * 2.0 * (1.0 + treble * 0.3);
    let glowIntensity = u.zoom_params.z * 2.0;
    let occlusionBalance = u.zoom_params.w;

    let stepX = 1.0 / max(resolution.x, 1.0);
    let stepY = 1.0 / max(resolution.y, 1.0);

    // Sample neighbors as full vec4 (preserve alpha)
    let s_tl = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(-stepX, -stepY), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let s_tc = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, -stepY), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let s_tr = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(stepX, -stepY), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let s_ml = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(-stepX, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let s_mc = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let s_mr = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(stepX, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let s_bl = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(-stepX, stepY), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let s_bc = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, stepY), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let s_br = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(stepX, stepY), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    // Sobel on luminance
    let gx = -getLuminance(s_tl.rgb) - 2.0 * getLuminance(s_ml.rgb) - getLuminance(s_bl.rgb)
           + getLuminance(s_tr.rgb) + 2.0 * getLuminance(s_mr.rgb) + getLuminance(s_br.rgb);
    let gy = -getLuminance(s_tl.rgb) - 2.0 * getLuminance(s_tc.rgb) - getLuminance(s_tr.rgb)
           + getLuminance(s_bl.rgb) + 2.0 * getLuminance(s_bc.rgb) + getLuminance(s_br.rgb);
    let edgeStrength = sqrt(gx * gx + gy * gy);

    // Mouse flashlight
    let mousePos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let aspect = resolution.x / resolution.y;
    let distToMouse = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(mousePos.x * aspect, mousePos.y));
    let revealFalloff = 1.0 - smoothstep(0.0, max(revealRadius, 0.0001), distToMouse);

    // Neon color cycling (mids drives hue speed)
    let neonColor1 = vec3<f32>(1.0, 0.0, 0.8);
    let neonColor2 = vec3<f32>(0.0, 1.0, 1.0);
    let mixFactor = 0.5 + 0.5 * sin(time * 2.0 * audioReactivity + uv.x * 3.0);
    let neonColor = mix(neonColor1, neonColor2, mixFactor);

    // Emission (branchless)
    let edge = smoothstep(0.05, 0.3, edgeStrength);
    let glow = 0.3 + (2.0 + bass * 1.5) * revealFalloff;
    let emission = neonColor * glow * edge * edgeBoost * glowIntensity;

    let glowStrength = length(emission);

    // Meaningful alpha: edge strength + reveal + source alpha + audio sparkle
    let baseAlpha = s_mc.a;
    let alpha = clamp(edge * 0.5 + revealFalloff * 0.3 + baseAlpha * 0.2 + glowStrength * 0.1 * occlusionBalance + treble * 0.1, 0.0, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, coord, vec4<f32>(emission, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(emission, alpha));
}
```
