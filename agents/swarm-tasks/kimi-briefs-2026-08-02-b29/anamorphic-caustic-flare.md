# Swarm Brief: anamorphic-caustic-flare

**Role:** Visualist
**Name:** Anamorphic Caustic Flare
**Category:** visual-effects
**Description:** Premium cinematic anamorphic lens flares combined with living, refracting water caustics that distort and project the source footage. Bass stretches the flares dramatically while treble animates the caustic ripples. Mouse tilts the virtual lens.
**Current lines:** 119
**Target lines:** 169–209 (expand by +50 to +90)

## Role Instructions

You are the Visualist. This cinematic flare's caustic field is alive - but the flare is nailed to screen center, the tilt snaps with the cursor, and clicks never flash. Give it lens behavior:
- Spring-damper the tilt + flare anchor (priority 1): ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT); the mouseTilt rides the SPRUNG x, and the anamorphic flare line (currently pinned at uv.y = 0.5) follows the sprung y (centerDist = abs(uv.y - mix(0.5, sprungMouse.y, 0.35)) * 1.8 - mostly centered but the lens breathes toward the cursor).
- Click flare bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple fires a decaying anamorphic flash centered on its click's y-line (a second streak term: exp(-age * 2.0) * smoothstep(0.02, 0.0, abs(uv.y - clickY)) * flareStrength, ~1.2s) plus a brief caustic energy spike near the click point.
- Per-band FFT caustic shimmer: 8 vertical bands each modulate their causticMask by `plasmaBuffer[(band % 8u) + 1u].x * 0.3`, so the water light dances across the spectrum instead of only global mids/treble.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: dataTextureA stores FIELD data (c, causticMask, flareStrength, semantic_alpha) - NOT display color - keep that packing VERBATIM. Preserve the hash21/caustic helpers, the anamorphic smoothstep flare + streak construction, the refraction offset, the filmic chromatic aberration block (keep its branchy form), the contrast curve, the semantic alpha formula, and the depth-energy write VERBATIM. Slider ranges are custom (Flare 0-1.6, Caustic 0-1.8) - keep ids/names/defaults/ranges EXACTLY. extraBuffer in [133..255] ONLY.

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
  "id": "anamorphic-caustic-flare",
  "name": "Anamorphic Caustic Flare",
  "url": "shaders/anamorphic-caustic-flare.wgsl",
  "description": "Premium cinematic anamorphic lens flares combined with living, refracting water caustics that distort and project the source footage. Bass stretches the flares dramatically while treble animates the caustic ripples. Mouse tilts the virtual lens.",
  "tags": [
    "anamorphic",
    "caustic",
    "lens-flare",
    "cinematic",
    "refraction",
    "audio-reactive",
    "water"
  ],
  "features": [
    "audio-reactive",
    "audio-driven",
    "mouse-driven",
    "mouse-tilt",
    "semantic-alpha",
    "depth-aware"
  ],
  "params": [
    {
      "id": "flare",
      "name": "Anamorphic Flare",
      "default": 0.7,
      "min": 0.0,
      "max": 1.6,
      "step": 0.01
    },
    {
      "id": "caustic",
      "name": "Caustic Intensity",
      "default": 0.85,
      "min": 0.0,
      "max": 1.8,
      "step": 0.01
    },
    {
      "id": "refraction",
      "name": "Refraction Amount",
      "default": 0.6,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "id": "stretch",
      "name": "Caustic Stretch",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Anamorphic Flare",
      "default": 0.7,
      "min": 0.0,
      "max": 1.6,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Caustic Intensity",
      "default": 0.85,
      "min": 0.0,
      "max": 1.8,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Refraction Amount",
      "default": 0.6,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Caustic Stretch",
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
//  Anamorphic Caustic Flare
//  Category: visual-effects
//  Features: anamorphic, caustic, lens-flare, refraction, audio-stretch, mouse-tilt, cinematic, semantic-alpha
//  Complexity: High
//  Chunks From: _hash_library.wgsl (hash21)
//  Created: 2026-06-01
//  By: Grok (new image/video effect — premium anamorphic lens with living water caustics refracting the source)
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
  zoom_params: vec4<f32>,  // x=Flare, y=Caustic, z=Refraction, w=Stretch
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: hash21 (from _hash_library.wgsl) ═══
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn caustic(p: vec2<f32>, t: f32, freq: f32) -> f32 {
    let q = p * freq + vec2<f32>(t * 0.6, t * -0.4);
    let c1 = sin(q.x * 1.7 + sin(q.y * 2.3)) * 0.5 + 0.5;
    let c2 = sin(q.y * 2.1 + sin(q.x * 1.4 + t * 0.8)) * 0.5 + 0.5;
    return pow(c1 * c2, 1.6);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / res;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Sliders
    let flareStrength = u.zoom_params.x * (0.7 + bass * 0.9);
    let causticStrength = u.zoom_params.y * (0.8 + treble * 0.6);
    let refraction = u.zoom_params.z * 0.035;
    let stretch = u.zoom_params.w * (1.0 + bass * 0.8);

    let mouse = u.zoom_config.yz;
    let mouseTilt = (mouse.x - 0.5) * 0.6;

    // Sample input (will be refracted by caustics)
    let input = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Anamorphic horizontal flare (classic blue + orange)
    let centerDist = abs(uv.y - 0.5) * 1.8;
    let anamorph = smoothstep(0.08, 0.0, centerDist) * flareStrength;
    let flareCol = mix(vec3<f32>(0.2, 0.55, 1.0), vec3<f32>(1.0, 0.6, 0.15), uv.x * 0.6 + 0.2);
    var flare = flareCol * pow(anamorph, 1.3) * (1.0 + bass * 0.5);

    // Add horizontal light streaks (anamorphic signature)
    let streak = smoothstep(0.012, 0.0, abs(uv.y - 0.5)) * (0.6 + bass * 0.4);
    flare += vec3<f32>(0.85, 0.9, 1.0) * streak * flareStrength * 0.7;

    // Living water caustics that refract the image
    let c = caustic(uv + mouseTilt * 0.1, time * 0.7 + mids * 0.3, 9.0 + stretch * 4.0);
    let causticMask = pow(c, 2.2) * causticStrength;

    // Refraction offset (stronger where caustic is bright)
    let refractUV = uv + vec2<f32>(causticMask * refraction * (mouse.x - 0.5), causticMask * refraction * 0.6);
    let refracted = textureSampleLevel(readTexture, u_sampler, clamp(refractUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    // Blend refracted image with caustic highlights
    let causticLight = vec3<f32>(0.6, 0.85, 1.0) * causticMask * 1.8;
    var col = mix(input.rgb, refracted.rgb, 0.35 + causticMask * 0.5);
    col += causticLight * (0.4 + mids * 0.3);

    // Subtle filmic chromatic aberration on strong flares
    if (flareStrength > 0.4) {
        let caOff = flareStrength * 0.0018;
        let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(caOff, 0.0), 0.0).r;
        let b = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(caOff * 0.7, 0.0), 0.0).b;
        col.r = mix(col.r, r, 0.25);
        col.b = mix(col.b, b, 0.25);
    }

    // Final mix with anamorphic flare
    col = col * (1.0 - flareStrength * 0.25) + flare * 0.85;

    // Gentle contrast curve
    col = pow(max(col, vec3<f32>(0.0)), vec3<f32>(0.88));

    // Semantic alpha — strong on bright caustic and flare regions (great for layering)
    let energy = causticMask * 0.65 + anamorph * 0.9 + streak * 0.4;
    let semantic_alpha = clamp(0.68 + energy * 0.42, 0.5, 1.0);

    textureStore(writeTexture, global_id.xy, vec4<f32>(col, semantic_alpha));

    // Depth carries caustic energy for downstream effects
    let d = clamp(0.25 + causticMask * 0.55 + anamorph * 0.3, 0.0, 0.97);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));

    // Store caustic field for possible multi-pass use
    textureStore(dataTextureA, global_id.xy, vec4<f32>(c, causticMask, flareStrength, semantic_alpha));
}
```
