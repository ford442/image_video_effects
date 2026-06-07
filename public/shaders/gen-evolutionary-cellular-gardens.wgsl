// ═══════════════════════════════════════════════════════════════════
//  Multi-Scale Evolutionary Cellular Gardens
//  Category: generative
//  Description: Multi-state cellular automata where rules evolve based
//  on local conditions and global audio input. Audio drives genetic
//  pressure. Mouse introduces invasive species or protected zones.
//  Organic coral-like emergent structures.
//  Complexity: High
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

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash13(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// Continuous Conway-like rules, parameterized
// state: 0=dead, 1=alive; birthRange and survivalRange are evolving
fn cellularState(uv: vec2<f32>, cellScale: f32, t: f32,
                 birthThreshLow: f32, birthThreshHigh: f32,
                 survLow: f32, survHigh: f32,
                 mutationFreq: f32) -> f32 {
    let cell = floor(uv * cellScale);

    // Evolving cellular state using temporal hash
    let timeSlot = floor(t * mutationFreq);
    let state = hash13(vec3<f32>(cell, timeSlot));

    // Neighbor sum (Moore neighborhood approximated via smooth hash)
    var neighborSum = 0.0;
    for (var j: i32 = -1; j <= 1; j++) {
        for (var i: i32 = -1; i <= 1; i++) {
            if (i == 0 && j == 0) { continue; }
            let neighbor = cell + vec2<f32>(f32(i), f32(j));
            let nState = hash13(vec3<f32>(neighbor, timeSlot));
            neighborSum += step(0.5, nState);
        }
    }

    // Birth rule: dead cell becomes alive if neighborSum in [birthLow, birthHigh]
    let wasDead = step(state, 0.5);
    let born = wasDead * step(birthThreshLow, neighborSum) * step(neighborSum, birthThreshHigh);

    // Survival rule: alive cell survives if neighborSum in [survLow, survHigh]
    let wasAlive = 1.0 - wasDead;
    let survives = wasAlive * step(survLow, neighborSum) * step(neighborSum, survHigh);

    return clamp(born + survives, 0.0, 1.0);
}

// Multi-scale cellular garden: layers at different scales
fn cellularGarden(uv: vec2<f32>, t: f32, bass: f32, mids: f32, treble: f32,
                  scale: f32, evolutionSpeed: f32) -> vec4<f32> {
    // Evolving rule parameters: driven by audio bands
    // Bass drives birth rules (tectonic growth), treble drives death/refinement
    let birthLow  = 2.5 + bass * 1.5;       // ~2.5..4
    let birthHigh = 3.5 + bass * 1.0;       // ~3.5..4.5
    let survLow   = 2.0 + mids * 1.0;       // ~2..3
    let survHigh  = 4.0 - treble * 1.5;     // ~2.5..4

    // Fine-grain layer (high frequency cells)
    let fine = cellularState(uv, scale * 20.0, t, birthLow, birthHigh,
                              survLow, survHigh, evolutionSpeed * 3.0);

    // Mid-grain layer
    let mid = cellularState(uv, scale * 8.0, t, birthLow - 0.5, birthHigh + 0.5,
                             survLow - 0.3, survHigh + 0.3, evolutionSpeed * 1.5);

    // Coarse structural layer (long-lived)
    let coarse = cellularState(uv, scale * 3.0, t, birthLow + 0.5, birthHigh + 1.0,
                                survLow + 0.5, survHigh - 0.5, evolutionSpeed * 0.5);

    // Organic blend: coral/plant-like layering
    let organic = fine * 0.3 + mid * 0.5 + coarse * 0.8;

    return vec4<f32>(fine, mid, coarse, organic);
}

// Species color: each "species" has a distinct color mapped from its birth parameters
fn speciesColor(fine: f32, mid: f32, coarse: f32, uv: vec2<f32>,
                t: f32, bass: f32, mids: f32, treble: f32) -> vec3<f32> {
    // Fine species: bioluminescent blue-green
    let col1 = vec3<f32>(0.1 + treble * 0.3, 0.8 + mids * 0.2, 0.5);

    // Mid species: coral pink-orange
    let col2 = vec3<f32>(0.9 + bass * 0.1, 0.3 + mids * 0.3, 0.2);

    // Coarse: deep purple structural
    let col3 = vec3<f32>(0.3 + bass * 0.2, 0.1, 0.6 + treble * 0.3);

    // Temporal color cycling from genetic pressure
    let pulse = 0.5 + 0.5 * sin(t * 1.5 + bass * PI);

    var col = col3 * coarse;
    col = mix(col, col2, mid);
    col = mix(col, col1, fine * treble);
    col *= pulse * 0.4 + 0.6;

    return col;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.zw);
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / res;
    let aspect = res.x / res.y;
    let uvA = vec2<f32>(uv.x * aspect, uv.y);

    let t = u.config.x;
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let cellScale     = u.zoom_params.x * 1.5 + 0.5;  // 0.5..2.0
    let evolutionSpd  = u.zoom_params.y * 0.5 + 0.1;  // 0.1..0.6
    let invasiveForce = u.zoom_params.z;               // 0..1 invasive species strength
    let glow          = u.zoom_params.w * 2.0 + 0.5;  // 0.5..2.5

    let mousePos = vec2<f32>(u.zoom_config.y * aspect, u.zoom_config.z);
    let mouseDist = length(uvA - mousePos);

    // Mouse interaction: within radius, plant invasive species or protected zone
    let mouseRadius = 0.12 + bass * 0.05;
    let inMouseZone = smoothstep(mouseRadius, mouseRadius * 0.5, mouseDist);

    // Invasive species disturbs local cellular rules
    let localBassBoost = bass + inMouseZone * invasiveForce * 1.5;
    let localMidsBoost = mids + inMouseZone * invasiveForce * 0.5;
    let localTreble = treble * (1.0 - inMouseZone * invasiveForce * 0.3);

    // Compute multi-scale garden
    let garden = cellularGarden(uvA, t, localBassBoost, localMidsBoost,
                                 localTreble, cellScale, evolutionSpd);

    let fine   = garden.x;
    let mid    = garden.y;
    let coarse = garden.z;
    let organic = garden.w;

    // Background: deep ocean-like darkness
    var color = vec3<f32>(0.01, 0.03, 0.05);

    // Add cellular layers
    let specCol = speciesColor(fine, mid, coarse, uvA, t, bass, mids, treble);
    color = mix(color, specCol, clamp(organic, 0.0, 1.0));

    // Glow: bioluminescent inner light
    let bioluminescence = fine * treble * glow * 0.5;
    color += vec3<f32>(0.1, 0.8, 0.6) * bioluminescence;

    // Coarse structure silhouette shading
    let shadowEdge = smoothstep(0.4, 0.6, coarse) - smoothstep(0.6, 0.8, coarse);
    color += vec3<f32>(0.5 + bass * 0.3, 0.3, 0.7) * shadowEdge * mids * 0.4;

    // Mouse zone highlight (invasive species pulse)
    color += vec3<f32>(0.9, 0.2, 0.3) * inMouseZone * invasiveForce *
             (0.5 + 0.5 * sin(t * 8.0)) * 0.5;

    // Temporal evolution shimmer
    let shimmer = hash13(vec3<f32>(uvA * 50.0, floor(t * evolutionSpd * 4.0)));
    color += vec3<f32>(0.2, 0.5, 0.3) * shimmer * treble * 0.1;

    // Vignette
    let v = 1.0 - smoothstep(0.3, 0.8, length(uv - 0.5) * 1.3);
    color *= v;

    textureStore(writeTexture, global_id.xy, vec4<f32>(clamp(color * glow, vec3<f32>(0.0), vec3<f32>(1.0)), 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0));
}
