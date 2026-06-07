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
