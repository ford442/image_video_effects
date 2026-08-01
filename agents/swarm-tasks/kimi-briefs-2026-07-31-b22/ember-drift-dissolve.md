# Swarm Brief: ember-drift-dissolve

**Role:** Visualist
**Name:** Ember Drift Dissolve
**Category:** image
**Description:** Bright areas of the image lift off as glowing embers and are carried upward by a living heat field. Creates haunting, beautiful disintegration especially on video. Treble controls spark density while bass thickens the rising glow.
**Current lines:** 110
**Target lines:** 160–200 (expand by +50 to +90)

## Role Instructions

You are the Visualist. This ember dissolve is honest and its state feedback is well-built - but it's a fire shader that ignores the cursor entirely. Give the flames a hand:
- Click ignition (priority 1): loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple ignites embers at its click point (a birth burst: age += decaying ignition in a ~0.2 radius, ~1.5s), so clicks set fires that the heat field then carries.
- Mouse heat plume (optional flavor, not tagged mouse-driven): near the cursor, bend the heat field upward stronger (heatField.y *= 1.0 + mouseMask * 0.8, aspect-corrected smoothstep ~0.3) and add a faint glow lift, so the pointer stirs the thermals.
- Per-region FFT crackle: divide the screen into 8 vertical bands; each band's spark term rides its own bin (`plasmaBuffer[(band % 8u) + 1u].x`) so the crackle dances across the spectrum instead of global treble only.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: the ember state contract is SACRED - dataTextureA stores (age, lateral, intensity, glow) STATE and dataTextureC is read as prev state + advection source; the engine only reads history via C, so this packing is FORCED - keep it exactly, never tonemap the A write. Preserve the hash21 helper, the emberMask, the heatField construction, the birth/spark steps, the age/decay/turb/intensity math, the emberCol ramp, and the haze VERBATIM. Sliders have custom ranges (Rise 0-1.6, Spark 0-1.8, Decay 0.4-0.98) - keep roles AND ranges EXACTLY. extraBuffer (if used) in [133..255] ONLY.

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
  "id": "ember-drift-dissolve",
  "name": "Ember Drift Dissolve",
  "url": "shaders/ember-drift-dissolve.wgsl",
  "description": "Bright areas of the image lift off as glowing embers and are carried upward by a living heat field. Creates haunting, beautiful disintegration especially on video. Treble controls spark density while bass thickens the rising glow.",
  "tags": [
    "ember",
    "fire",
    "dissolve",
    "advection",
    "heat",
    "atmospheric",
    "audio-reactive"
  ],
  "features": [
    "audio-reactive",
    "audio-driven",
    "temporal",
    "semantic-alpha",
    "depth-aware"
  ],
  "params": [
    {
      "id": "rise",
      "name": "Rise Speed",
      "default": 0.7,
      "min": 0.0,
      "max": 1.6,
      "step": 0.01
    },
    {
      "id": "spark",
      "name": "Spark Density",
      "default": 0.75,
      "min": 0.0,
      "max": 1.8,
      "step": 0.01
    },
    {
      "id": "heat",
      "name": "Heat Turbulence",
      "default": 0.6,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "id": "decay",
      "name": "Ember Decay",
      "default": 0.82,
      "min": 0.4,
      "max": 0.98,
      "step": 0.01
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Rise Speed",
      "default": 0.7,
      "min": 0.0,
      "max": 1.6,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Spark Density",
      "default": 0.75,
      "min": 0.0,
      "max": 1.8,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Heat Turbulence",
      "default": 0.6,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Ember Decay",
      "default": 0.82,
      "min": 0.4,
      "max": 0.98,
      "step": 0.01
    }
  ],
  "updated": true
}
```

## Current WGSL Code

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  Ember Drift Dissolve
//  Category: image
//  Features: ember, dissolve, advection, heat, audio-sparks, semantic-alpha, temporal
//  Complexity: High
//  Chunks From: _hash_library.wgsl (hash21)
//  Created: 2026-06-01
//  By: Grok (new image/video effect — bright regions lift as glowing embers carried by rising heat, beautiful disintegration on video)
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
  zoom_params: vec4<f32>,  // x=Rise, y=Spark, z=Heat, w=Decay
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
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

    let riseSpeed = u.zoom_params.x * (0.7 + bass * 0.4);
    let sparkDensity = u.zoom_params.y * (0.6 + treble * 1.1);
    let heat = u.zoom_params.z;
    let decay = u.zoom_params.w * 0.9 + 0.1;

    // Previous ember state (age, intensity, lateral drift)
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

    let input = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(input.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Only bright areas produce embers
    let emberMask = smoothstep(0.35, 0.82, luma);

    // Rising heat advection field (with some curl)
    let heatField = vec2<f32>(
        sin(uv.y * 6.0 + time * 0.6) * 0.018,
        -riseSpeed * (0.018 + heat * 0.012 + prev.g * 0.008)
    );

    // Sample previous location (advection)
    let prevUV = clamp(uv - heatField * 1.6, vec2<f32>(0.0), vec2<f32>(1.0));
    let carried = textureSampleLevel(dataTextureC, u_sampler, prevUV, 0.0);

    // New ember birth from bright pixels + audio sparks
    let birth = emberMask * (0.4 + sparkDensity * 0.7) * step(0.82, hash21(uv * 140.0 + floor(time * 7.0)));
    let spark = step(0.91, hash21(uv * 290.0 + time * 19.0)) * treble * 0.9 * emberMask;

    var age = carried.r * decay + birth * 0.9 + spark * 0.6;
    age = clamp(age, 0.0, 1.0);

    // Lateral turbulence increases with age and treble
    let turb = (hash21(uv * 17.0 + time * 2.3) - 0.5) * 0.008 * (age * 0.7 + treble * 0.4);
    let lateral = carried.g * 0.92 + turb;

    let intensity = age * (0.7 + mids * 0.3) * smoothstep(1.0, 0.2, age);

    // Ember color (warm core → cooler ash)
    let emberCol = mix(vec3<f32>(1.0, 0.45, 0.08), vec3<f32>(0.2, 0.05, 0.01), smoothstep(0.3, 1.0, age));
    let glow = pow(intensity, 1.6) * (0.9 + bass * 0.4);

    // Composite: original darkens as embers lift, bright embers added on top
    var col = input.rgb * (1.0 - intensity * 0.65);
    col += emberCol * glow * 1.6;

    // Heat haze on rising areas
    let haze = intensity * 0.12 * (1.0 - depth);
    col = mix(col, col + vec3<f32>(0.15, 0.08, 0.02), haze);

    // Semantic alpha — embers are ethereal and glow
    let semantic_alpha = clamp(0.55 + glow * 0.65 + intensity * 0.3, 0.4, 1.0);

    textureStore(writeTexture, global_id.xy, vec4<f32>(col, semantic_alpha));

    // Write new ember state for next frame
    textureStore(dataTextureA, global_id.xy, vec4<f32>(age, lateral, intensity, glow));

    // Depth from ember height in scene
    let d = clamp(0.2 + intensity * 0.55, 0.0, 0.96);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
```
