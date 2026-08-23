// ═══════════════════════════════════════════════════════════════════
//  Chrono-Voronoi Mycelium
//  Category: generative
//  Features: upgraded-rgba, temporal, audio-reactive, mouse-driven,
//            voronoi-colonies, mycelium-hyphae, spore-bursts,
//            golden-ratio, nutrient-pulse, growth-rings,
//            spectral-seed-jitter, spring-damped-inoculation
//  Complexity: High
//  Chunks From: standard voronoi + temporal feedback patterns
//  Description: Voronoi cells represent fungal colonies.
//  Cell edges glow as mycelium hyphae. Temporal feedback accumulates
//  growth rings. Bass = nutrient pulse triggers spore bursts.
//  Mouse inoculates new colonies. Golden-ratio seed displacement.
//  Per-bin FFT jitter makes colonies shimmer with the spectrum.
//  Created: 2026-05-31
//  By: Grok (creative technical artist)
//  Upgraded: 2026-06-07
//  Upgraded: 2026-07-26 (Batch 16 - Algorithmist)
//    * Evicted generic applyGenerativePrimaryControls boilerplate;
//      sliders now drive real mycelium constants:
//        x Growth Bias        -> ageMix blend exponent (young vs old)
//        y Temporal Scale     -> layer clock time multiplier
//        z Decay Influence    -> layer decay rate mix(0.970, 0.995, z)
//        w Pattern Complexity -> primary voronoi scale
//    * Cleaned feedback path (single dataTextureC read, no dead
//      dataTextureB store; A packs layer1->r, layer2->g, layer3->b).
//    * Spectral seed jitter from plasmaBuffer FFT bins.
//    * Spring-damped inoculation point in extraBuffer[133..134].
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Voronoi returning nearest + second-nearest distance for mycelium hyphae edges.
// Each seed is additionally offset by a per-bin FFT term so whole colonies
// shimmer with the spectrum instead of only pulsing with the bass band.
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
            // Spectral seed jitter: stable per-cell id picks one of 8 FFT bins
            let cellId = u32(h * 4096.0);
            let spectral = plasmaBuffer[(cellId % 8u) + 1u].x;
            let shimmer = vec2<f32>(cos(spectral * 6.2831 + h * 12.0),
                                    sin(spectral * 6.2831 + h * 12.0)) * spectral * 0.08;
            // Nutrient pulse: bass displaces seeds = faster fungal spread
            let o = vec2<f32>(h, fract(h * GOLDEN)) * (1.0 + nutrient * 0.4)
                  + vec2<f32>(cos(time * nutrient * 2.0), sin(time * nutrient * 2.0)) * nutrient * 0.2
                  + shimmer;
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

// Expanding spore ring emitted from a center point on strong bass hits.
// The ring radius advances at a golden-ratio-scaled rate and fades as it
// travels, seeding new colonies in its wake like a sporulation wavefront.
fn sporeRing(uv: vec2<f32>, center: vec2<f32>, time: f32, bass: f32) -> f32 {
    let d = length(uv - center);
    let phase = fract(time * 0.5 * GOLDEN * 0.309); // golden-scaled expansion
    let radius = phase * 0.45;
    let band = smoothstep(0.03, 0.0, abs(d - radius));
    let trigger = smoothstep(0.5, 0.8, bass);
    return band * trigger * (1.0 - phase);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let uv = vec2<f32>(gid.xy) / res;

    // ── Slider wiring (saved-preset contract: ids/defaults unchanged) ──
    // Growth Bias (x)        -> ageMix blend exponent: favors new vs old layers
    // Temporal Scale (y)     -> actual time multiplier of the layer clocks
    // Decay Influence (z)    -> layer decay rate
    // Pattern Complexity (w) -> primary voronoi scale
    let growthBias = clamp(u.zoom_params.x, 0.0, 1.0);
    let temporalScale = clamp(u.zoom_params.y, 0.0, 1.0);
    let decayInfluence = clamp(u.zoom_params.z, 0.0, 1.0);
    let complexity = clamp(u.zoom_params.w, 0.0, 1.0);

    // Layer clock: default (y = 0.5) reproduces the legacy 0.4x time rate
    let time = u.config.x * mix(0.15, 0.65, temporalScale);

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Audio seasons
    let seasonBloom = mids * 0.8;
    let seasonHarsh = bass * 0.6;
    let seasonVolatile = treble * 0.9;

    // Nutrient pulse from bass drives faster spread / seed displacement
    let nutrient = bass * 0.7;

    // Spring-damped inoculation point: persistent state glides toward the
    // cursor instead of teleporting, so seeded colonies trail smoothly.
    // extraBuffer[133..134] = damped inoculation xy (shader state range only).
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    var inoc = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    if (inoc.x <= 0.0 && inoc.y <= 0.0) {
        inoc = mouse; // cold start: avoid gliding in from the corner
    }
    inoc = mix(inoc, mouse, 0.08); // critically-damped style follow
    extraBuffer[133] = inoc.x;
    extraBuffer[134] = inoc.y;
    let mouseDist = length(uv - inoc);
    let mouseInoculate = smoothstep(0.12, 0.0, mouseDist) * mouseDown * 3.0;

    // Read previous temporal layers (single fetch: A packs r/g/b = L1/L2/L3)
    let prevLayers = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

    // Multi-scale Voronoi growth — Pattern Complexity drives the primary
    // scale; secondary/tertiary scales keep their legacy 2.25x / 4x ratios.
    let scale1 = mix(2.0, 14.0, complexity) + seasonVolatile * 6.0;
    let scale2 = scale1 * 2.25 + seasonBloom * 8.0;
    let scale3 = scale1 * 4.0;

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

    // Combine layers with decay — Decay Influence sets the base rate;
    // the per-layer offsets (-0.01 / -0.02) and harsh-season term are kept.
    let decay = mix(0.970, 0.995, decayInfluence) - seasonHarsh * 0.02;
    var layer1 = prevLayers.r * decay + growth1 * 0.7;
    var layer2 = prevLayers.g * (decay - 0.01) + growth2 * 0.65;
    var layer3 = prevLayers.b * (decay - 0.02) + growth3 * 0.55;

    // Bass triggers spore bursts (new seed points appear)
    let sporeBurst = smoothstep(0.55, 0.85, bass) * (0.5 + 0.5 * sin(time * 10.0));
    layer1 += sporeBurst * 0.5;
    layer2 += sporeBurst * 0.35;
    layer3 += sporeBurst * 0.25;

    // Sporulation wavefront: an expanding ring radiates from the damped
    // inoculation point on hard bass hits, seeding every generation it
    // crosses — strongest on the youngest layer, faintest on the oldest.
    let ringWave = sporeRing(uv, inoc, u.config.x, bass);
    layer1 += ringWave * 0.55;
    layer2 += ringWave * 0.40;
    layer3 += ringWave * 0.30;

    // Mouse inoculation affects all layers (cap values preserved verbatim)
    layer1 = min(layer1 + mouseInoculate * 0.8, 1.8);
    layer2 = min(layer2 + mouseInoculate * 0.6, 1.6);
    layer3 = min(layer3 + mouseInoculate * 0.9, 1.9);

    // Temporal feedback accumulates growth rings
    let ringAge = fract((layer1 + layer2 * 0.7) * 1.8 - time * 0.18);
    let growthRing = smoothstep(0.92, 0.98, ringAge) * 0.3 * (1.0 + bass);
    layer1 += growthRing;

    // Store temporal layers — SIM STATE, never clamped/tonemapped.
    // Packing contract: layer1->r, layer2->g, layer3->b.
    textureStore(dataTextureA, gid.xy, vec4<f32>(layer1, layer2, layer3, 0.0));

    // Visualization — layered organic colors.
    // Growth Bias reshapes the blend exponent: >0.5 favors fresh growth,
    // <0.5 lets the older generations dominate. Default 0.5 = exponent 1.0.
    let ageExp = mix(1.4, 0.6, growthBias);
    let ageMix = pow(max(vec3<f32>(layer1, layer2 * 0.8, layer3 * 0.6), vec3<f32>(0.0)),
                     vec3<f32>(ageExp));
    var col = mix(vec3<f32>(0.1, 0.15, 0.1), vec3<f32>(0.9, 0.95, 0.7), ageMix);

    // Spectral tint on the hyphae threads so colonies shimmer with the FFT
    let threadTint = vec3<f32>(treble * 0.12, mids * 0.08, bass * 0.10);
    col += threadTint * (hyphae1 + hyphae2 * 0.5);

    // Temporal feedback blend
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    col = mix(col, prev.rgb * 0.9, 0.03 + bass * 0.01);

    // Subtle depth from layers
    let depth = (layer1 * 0.3 + layer2 * 0.5 + layer3 * 0.7) * 0.6 + 0.2;

    var color = col;

    // Chromatic aberration
    let caStr = 0.003 * (1.0 + bass);
    color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);

    // ACES tone mapping
    color = acesToneMap(color * 1.1);

    // Semantic alpha
    let alpha = clamp(length(color) * 1.2, 0.2, 0.95);

    
    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    let aspect = u.config.z / max(u.config.w, 1.0);
    let screenUV = vec2<f32>(gid.xy) / vec2<f32>(u.config.z, u.config.w);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let event = u.ripples[i];
        let age = max(time - event.z, 0.0);
        clickFront += exp(-age * 1.8) * exp(-abs(length((screenUV - event.xy) * vec2<f32>(aspect, 1.0)) - age * 0.38) * 58.0);
    }
    
    let clockRings = sin(length(screenUV - vec2<f32>(0.5)) * 95.0 - time * (5.0 + treble * 7.0));
    let spectral = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + clockRings * 3.0 + time * (0.8 + mids));

    let __finalRGB = vec4<f32>(color, alpha).rgb + spectral * (abs(clockRings) * 0.1 + clickFront * 0.25);
    textureStore(writeTexture, gid.xy, vec4<f32>(__finalRGB, vec4<f32>(color, alpha).a));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
