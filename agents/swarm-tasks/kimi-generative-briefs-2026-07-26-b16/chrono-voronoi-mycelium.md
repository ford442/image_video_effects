# Swarm Brief: chrono-voronoi-mycelium

**Role:** Algorithmist
**Name:** Chrono-Voronoi Mycelium
**Category:** generative
**Description:** A living fungal network that grows across multiple time scales. Voronoi cells represent fungal colonies; cell edges glow as mycelium hyphae. Different generations coexist as translucent layers. Temporal feedback accumulates growth rings. Bass = nutrient pulse triggers spore bursts and faster spread via golden-ratio seed displacement. Mouse inoculates new colonies. ACES tonemapped with chromatic aberration.
**Current lines:** 194
**Target lines:** 244–284 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. All four of this shader's sliders are trapped in generic applyGenerativePrimaryControls boilerplate (brightness/speed-pulse/contrast/mouse-gain) - every label is a lie. Evict the boilerplate and wire the real mycelium constants:
- EVICT THE BOILERPLATE (priority 1): rewire the sliders to shader-specific constants, defaults reproducing the current look - Growth Bias (x) -> layer ageMix blend exponent, Temporal Scale (y) -> the actual time multiplier of the layer clocks, Decay Influence (z) -> the layer decay rate (e.g. mix(0.970, 0.995, z)), Pattern Complexity (w) -> the primary voronoi scale (e.g. mix(4.0, 16.0, w)). Remove the shared helper call entirely. Keep JSON ids/names/defaults EXACTLY (saved-preset contract).
- Clean the feedback path: delete the duplicate dataTextureC sample (`prevLayer2` re-reads the same texel as `prevLayer1` - dead code) and the redundant dataTextureB store (B is never read; A packs all three layers). Keep the A packing and caps untouched.
- Spectral seed jitter: offset each voronoi seed by a per-bin FFT term `plasmaBuffer[(cellId % 8) + 1].x` so colonies shimmer with the spectrum; spring-damper the inoculation point (extraBuffer[133..134]) so it glides.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the layer cap values (1.8/1.6/1.9), the decay formula structure, and the dataTextureA channel packing (layer1->r, layer2->g, layer3->b) VERBATIM - temporal feedback stability depends on them. dataTextureA is SIM STATE - never clamp/tonemap it. extraBuffer in [133..255] ONLY.

## Required Output Format

- Return exactly one fenced WGSL block (` ```wgsl ` ... ` ``` `).
- No prose before or after the fence.
- Preserve the canonical 13-binding compute layout:
  - @binding(0) sampler, (1) readTexture, (2) writeTexture, (3) Uniforms, (4) readDepthTexture, (5) non_filtering_sampler, (6) writeDepthTexture, (7) dataTextureA, (8) dataTextureB, (9) dataTextureC, (10) extraBuffer (read_write), (11) comparison_sampler, (12) plasmaBuffer (read).
- Workgroup size must be `@workgroup_size(16, 16, 1)`.
- Write to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Use `textureSampleLevel(..., 0.0)` for sampler reads and `textureLoad` for storage reads.
- Do not use WGSL reserved keywords as identifiers (e.g. `target`). Do not add or renumber bindings. Binding 13 (historyTexture) is optional - only declare it if the shader already uses it.
- extraBuffer (if ever used): [0..4] reserved, [5..132] = engine FFT bins - persistent shader state goes in [133..255] ONLY.
- Engine uniform truth (verified src/renderer/UniformBuffer.ts): config = [time, rippleCount, resW, resH]; zoom_config = [time, mouseX, mouseY, mouseDown]. Guard ripple loops with `min(u32(u.config.y), 50u)`.

## JSON Parameters / Controls

```json
{
  "id": "chrono-voronoi-mycelium",
  "name": "Chrono-Voronoi Mycelium",
  "url": "shaders/chrono-voronoi-mycelium.wgsl",
  "category": "generative",
  "description": "A living fungal network that grows across multiple time scales. Voronoi cells represent fungal colonies; cell edges glow as mycelium hyphae. Different generations coexist as translucent layers. Temporal feedback accumulates growth rings. Bass = nutrient pulse triggers spore bursts and faster spread via golden-ratio seed displacement. Mouse inoculates new colonies. ACES tonemapped with chromatic aberration.",
  "features": [
    "temporal-layers",
    "voronoi-growth",
    "audio-seasons",
    "mouse-seeding",
    "multi-scale",
    "temporal",
    "upgraded-rgba",
    "depth-aware",
    "audio-reactive",
    "mouse-driven"
  ],
  "tags": [
    "organic",
    "mycelium",
    "temporal",
    "voronoi",
    "generative",
    "audio-reactive",
    "mouse-driven",
    "golden-ratio",
    "biological"
  ],
  "params": [
    {
      "id": "growthBias",
      "name": "Growth Bias",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x",
      "description": "Favors newer vs older growth generations"
    },
    {
      "id": "timeScale",
      "name": "Temporal Scale",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y",
      "description": "How spread out the different time layers are"
    },
    {
      "id": "decayRate",
      "name": "Decay Influence",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z",
      "description": "How strongly older generations fade"
    },
    {
      "id": "complexity",
      "name": "Pattern Complexity",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w",
      "description": "Controls the density of the smallest mycelium threads"
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Growth Bias",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Temporal Scale",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Decay Influence",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Pattern Complexity",
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
//  Chrono-Voronoi Mycelium
//  Category: generative
//  Features: upgraded-rgba, temporal, audio-reactive, mouse-driven,
//            voronoi-colonies, mycelium-hyphae, spore-bursts,
//            golden-ratio, nutrient-pulse, growth-rings
//  Complexity: High
//  Chunks From: standard voronoi + temporal feedback patterns
//  Description: Voronoi cells represent fungal colonies.
//  Cell edges glow as mycelium hyphae. Temporal feedback accumulates
//  growth rings. Bass = nutrient pulse triggers spore bursts.
//  Mouse inoculates new colonies. Golden-ratio seed displacement.
//  Created: 2026-05-31
//  By: Grok (creative technical artist)
//  Upgraded: 2026-06-07
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

const GOLDEN: f32 = 1.6180339887;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn applyGenerativePrimaryControls(color: vec4<f32>) -> vec4<f32> {
  let primaryIntensity = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
  let speedPulse = 0.92 + 0.16 * (0.5 + 0.5 * sin(u.config.x * mix(0.25, 5.0, clamp(u.zoom_params.y, 0.0, 1.0))));
  let detailContrast = mix(0.75, 1.6, clamp(u.zoom_params.z, 0.0, 1.0));
  let mouseDistance = length(u.zoom_config.yz - vec2<f32>(0.5));
  let mouseInfluence = mix(0.95, 1.15, clamp(u.zoom_params.w * mouseDistance * 2.0, 0.0, 1.0));
  let controlled = pow(max(color.rgb * primaryIntensity * speedPulse * mouseInfluence, vec3<f32>(0.0)), vec3<f32>(1.0 / detailContrast));
  return vec4<f32>(controlled, color.a);
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Voronoi returning nearest + second-nearest distance for mycelium hyphae edges
fn voronoi(p: vec2<f32>, time: f32, seed: f32, nutrient: f32) -> vec4<f32> {
    let n = floor(p);
    let f = fract(p);
    var minDist = 8.0;
    var secondDist = 8.0;
    var minO = vec2<f32>(0.0);

    for (var j = -1; j <= 1; j++) {
        for (var i = -1; i <= 1; i++) {
            let g = vec2<f32>(f32(i), f32(j));
            let h = hash12(n + g + seed);
            // Nutrient pulse: bass displaces seeds = faster fungal spread
            let o = vec2<f32>(h, fract(h * GOLDEN)) * (1.0 + nutrient * 0.4)
                  + vec2<f32>(cos(time * nutrient * 2.0), sin(time * nutrient * 2.0)) * nutrient * 0.2;
            let r = g + o - f;
            let d = dot(r, r);
            if (d < minDist) {
                secondDist = minDist;
                minDist = d;
                minO = o;
            } else if (d < secondDist) {
                secondDist = d;
            }
        }
    }
    return vec4<f32>(minDist, secondDist, minO.x, minO.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x * 0.4;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Audio seasons
    let seasonBloom = mids * 0.8;
    let seasonHarsh = bass * 0.6;
    let seasonVolatile = treble * 0.9;

    // Nutrient pulse from bass drives faster spread / seed displacement
    let nutrient = bass * 0.7;

    // Mouse inoculates new colonies
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mouse);
    let mouseInoculate = smoothstep(0.12, 0.0, mouseDist) * mouseDown * 3.0;

    // Read previous temporal layers
    let prevLayer1 = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let prevLayer2 = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

    // Multi-scale Voronoi growth
    let scale1 = 8.0 + seasonVolatile * 6.0;
    let scale2 = 18.0 + seasonBloom * 8.0;
    let scale3 = 32.0;

    let v1 = voronoi(uv * scale1, time * (0.6 + seasonHarsh * 0.4), 0.0, nutrient);
    let v2 = voronoi(uv * scale2, time * (0.9 + seasonBloom * 0.3), 1.3, nutrient);
    let v3 = voronoi(uv * scale3, time * 1.2, 3.7, nutrient);

    // Mycelium hyphae = Voronoi cell edges (second-nearest - nearest)
    let hyphae1 = sqrt(v1.y) - sqrt(v1.x);
    let hyphae2 = sqrt(v2.y) - sqrt(v2.x);
    let hyphae3 = sqrt(v3.y) - sqrt(v3.x);

    // Growth with temporal memory — hyphae edges glow like mycelium threads
    let growth1 = smoothstep(0.02, 0.18, v1.x) * (0.6 + seasonBloom * 0.5)
                + smoothstep(0.05, 0.0, hyphae1) * 0.35;
    let growth2 = smoothstep(0.015, 0.12, v2.x) * (0.5 + seasonVolatile * 0.6)
                + smoothstep(0.04, 0.0, hyphae2) * 0.3;
    let growth3 = smoothstep(0.01, 0.08, v3.x) * (0.4 + seasonHarsh * 0.3)
                + smoothstep(0.03, 0.0, hyphae3) * 0.25;

    // Combine layers with decay
    let decay = 0.985 - seasonHarsh * 0.02;
    var layer1 = prevLayer1.r * decay + growth1 * 0.7;
    var layer2 = prevLayer2.g * (decay - 0.01) + growth2 * 0.65;
    var layer3 = prevLayer1.b * (decay - 0.02) + growth3 * 0.55;

    // Bass triggers spore bursts (new seed points appear)
    let sporeBurst = smoothstep(0.55, 0.85, bass) * (0.5 + 0.5 * sin(time * 10.0));
    layer1 += sporeBurst * 0.5;
    layer2 += sporeBurst * 0.35;
    layer3 += sporeBurst * 0.25;

    // Mouse inoculation affects all layers
    layer1 = min(layer1 + mouseInoculate * 0.8, 1.8);
    layer2 = min(layer2 + mouseInoculate * 0.6, 1.6);
    layer3 = min(layer3 + mouseInoculate * 0.9, 1.9);

    // Temporal feedback accumulates growth rings
    let ringAge = fract((layer1 + layer2 * 0.7) * 1.8 - time * 0.18);
    let growthRing = smoothstep(0.92, 0.98, ringAge) * 0.3 * (1.0 + bass);
    layer1 += growthRing;

    // Store temporal layers
    textureStore(dataTextureA, gid.xy, vec4<f32>(layer1, layer2, layer3, 0.0));
    textureStore(dataTextureB, gid.xy, vec4<f32>(layer2, layer3, layer1, 0.0));

    // Visualization — layered organic colors
    let ageMix = vec3<f32>(layer1, layer2 * 0.8, layer3 * 0.6);
    var col = mix(vec3<f32>(0.1, 0.15, 0.1), vec3<f32>(0.9, 0.95, 0.7), ageMix);

    // Temporal feedback blend
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    col = mix(col, prev.rgb * 0.9, 0.03 + bass * 0.01);

    // Subtle depth from layers
    let depth = (layer1 * 0.3 + layer2 * 0.5 + layer3 * 0.7) * 0.6 + 0.2;

    // Apply generative controls
    let controlled = applyGenerativePrimaryControls(vec4<f32>(col, 1.0));
    var color = controlled.rgb;

    // Chromatic aberration
    let caStr = 0.003 * (1.0 + bass);
    color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);

    // ACES tone mapping
    color = acesToneMap(color * 1.1);

    // Semantic alpha
    let alpha = clamp(length(color) * 1.2, 0.2, 0.95);

    textureStore(writeTexture, gid.xy, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```
