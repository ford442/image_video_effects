// ═══════════════════════════════════════════════════════════════════
//  Multi-Scale Evolutionary Cellular Gardens
//  Category: generative
//  Description: Multi-state cellular automata where rules evolve based
//  on local conditions and global audio input. Audio drives genetic
//  pressure. Mouse is a spring-smoothed nutrient attractor introducing
//  invasive species; clicks spawn bounded colony-burst shockwaves.
//  Temporal feedback memory (dataTextureA/C) gives colonies persistent
//  age and bioluminescent trails, so growth self-organizes along its
//  own history. Organic coral-like emergent structures.
//  Features: audio-reactive (bass/mids/treble + guarded FFT bins 1-8),
//  mouse-gravity-well, click-reactive, temporal-feedback, generated
//  depth, semantic alpha
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
    let mouseDown = u.zoom_config.w;

    let cellScale     = u.zoom_params.x * 1.5 + 0.5;  // 0.5..2.0
    let evolutionSpd  = u.zoom_params.y * 0.5 + 0.1;  // 0.1..0.6
    let invasiveForce = u.zoom_params.z;               // 0..1 invasive species strength
    let glow          = u.zoom_params.w * 2.0 + 0.5;  // 0.5..2.5

    // ── Persistent state: spring-smoothed nutrient attractor + click edge ──
    // extraBuffer[133..136] = attractor pos/vel (aspect uv), [137] = prev
    // mouseDown, [138] = last click timestamp (-10 = never fired)
    let sbLen = arrayLength(&extraBuffer);
    let canState = sbLen > 138u;
    let rawMouse = vec2<f32>(u.zoom_config.y * aspect, u.zoom_config.z);
    if (global_id.x == 0u && global_id.y == 0u && canState) {
        let h = 0.016;
        let spx = extraBuffer[133];
        let spy = extraBuffer[134];
        let svx = extraBuffer[135];
        let svy = extraBuffer[136];
        let lo = vec2<f32>(-0.2);
        let hi = vec2<f32>(aspect + 0.2, 1.2);
        let nvx = clamp(svx + ((rawMouse.x - spx) * 70.0 - svx * 10.0) * h, -4.0, 4.0);
        let nvy = clamp(svy + ((rawMouse.y - spy) * 70.0 - svy * 10.0) * h, -4.0, 4.0);
        extraBuffer[133] = clamp(spx + nvx * h, lo.x, hi.x);
        extraBuffer[134] = clamp(spy + nvy * h, lo.y, hi.y);
        extraBuffer[135] = nvx;
        extraBuffer[136] = nvy;
        let prevDown = extraBuffer[137];
        if (mouseDown > 0.5 && prevDown <= 0.5) {
            extraBuffer[138] = max(t, 0.001);
        } else if (extraBuffer[138] == 0.0) {
            extraBuffer[138] = -10.0;
        }
        extraBuffer[137] = mouseDown;
    }
    var sm = rawMouse;
    var clickT = -10.0;
    if (canState) {
        sm = vec2<f32>(extraBuffer[133], extraBuffer[134]);
        clickT = extraBuffer[138];
    }

    // ── Guarded FFT bands (engine bins 1-8 at extraBuffer[6..13], read-only) ──
    var fftLo = 0.0;
    var fftHi = 0.0;
    if (sbLen > 13u) {
        fftLo = (extraBuffer[6] + extraBuffer[7] + extraBuffer[8]) * 0.3333;
        fftHi = (extraBuffer[11] + extraBuffer[12] + extraBuffer[13]) * 0.3333;
    }

    // Mouse nutrient attractor (gravity well: lagged, not 1:1)
    let mousePos = sm;
    let mouseDist = length(uvA - mousePos);

    // Click colony-burst: bounded expanding growth front
    let clickAge = max(t - clickT, 0.0);
    let clickEnergy = select(0.0, exp(-clickAge * 1.2), clickT > 0.0);
    let burstRing = exp(-pow((mouseDist - clickAge * 0.5) * 12.0, 2.0)) * clickEnergy;

    // Mouse interaction: within radius, plant invasive species or protected zone
    let mouseRadius = 0.12 + bass * 0.05;
    let inMouseZone = smoothstep(mouseRadius, mouseRadius * 0.5, mouseDist);

    // Invasive species disturbs local cellular rules; click burst seeds a
    // vigorous growth front; engine ripples act as spore-seed nutrient bumps
    var nutrientBump = inMouseZone * invasiveForce * 1.5 + burstRing * invasiveForce * 2.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i++) {
        let rp = u.ripples[i];
        let age = t - rp.z;
        if (age > 0.0) {
            let d2 = distance(uv, rp.xy);
            nutrientBump += exp(-d2 * d2 * 60.0) * exp(-age * 2.0) * 1.2;
        }
    }
    let localBassBoost = bass + nutrientBump;
    let localMidsBoost = mids + inMouseZone * invasiveForce * 0.5 + burstRing * 0.4;
    let localTreble = treble * (1.0 - inMouseZone * invasiveForce * 0.3);

    // FFT low bands subtly accelerate local evolution (genetic pressure)
    let localEvolution = evolutionSpd * (1.0 + fftLo * 0.35 + inMouseZone * invasiveForce * 0.5);

    // Compute multi-scale garden
    let garden = cellularGarden(uvA, t, localBassBoost, localMidsBoost,
                                 localTreble, cellScale, localEvolution);

    let fine   = garden.x;
    let mid    = garden.y;
    let coarse = garden.z;
    let organic = garden.w;

    // ── Temporal feedback memory: colony age + bioluminescent trails ──
    let px = vec2<i32>(global_id.xy);
    let prev = textureLoad(dataTextureC, px, 0); // non-filtering history read
    // Colony age: long-lived occupation becomes "established" (slow approach)
    let colonyAge = clamp(mix(prev.a, clamp(organic, 0.0, 1.0), 0.05), 0.0, 1.0);

    // Background: deep ocean-like darkness
    var color = vec3<f32>(0.01, 0.03, 0.05);

    // Add cellular layers
    let specCol = speciesColor(fine, mid, coarse, uvA, t, bass, mids, treble);
    color = mix(color, specCol, clamp(organic, 0.0, 1.0));

    // Established colonies mature: richer body, golden structural patina
    color *= 0.8 + colonyAge * 0.45;
    color += vec3<f32>(0.9, 0.7, 0.3) * colonyAge * coarse * 0.15;

    // Glow: bioluminescent inner light
    let bioluminescence = fine * treble * glow * 0.5;
    color += vec3<f32>(0.1, 0.8, 0.6) * bioluminescence;

    // Coarse structure silhouette shading
    let shadowEdge = smoothstep(0.4, 0.6, coarse) - smoothstep(0.6, 0.8, coarse);
    color += vec3<f32>(0.5 + bass * 0.3, 0.3, 0.7) * shadowEdge * mids * 0.4;

    // Mouse zone highlight (invasive species pulse)
    color += vec3<f32>(0.9, 0.2, 0.3) * inMouseZone * invasiveForce *
             (0.5 + 0.5 * sin(t * 8.0)) * 0.5;

    // Click colony-burst bloom along the growth front
    color += vec3<f32>(0.4, 0.9, 0.5) * burstRing * invasiveForce * 0.9;

    // Temporal evolution shimmer (FFT high bands drive the sparkle rate)
    let shimmer = hash13(vec3<f32>(uvA * 50.0, floor(t * localEvolution * 4.0)));
    color += vec3<f32>(0.2, 0.5, 0.3) * shimmer * (treble + fftHi) * 0.1;

    // Vignette
    let v = 1.0 - smoothstep(0.3, 0.8, length(uv - 0.5) * 1.3);
    color *= v;

    // ── Feedback trails: history bioluminesces and guides future growth ──
    var trail = prev.rgb * 0.93 + color * 0.09;
    trail = min(trail, vec3<f32>(2.5));
    textureStore(dataTextureA, px, vec4<f32>(trail, colonyAge));
    color += trail * 0.12 * (0.5 + treble * 0.5);

    let outColor = clamp(color * glow, vec3<f32>(0.0), vec3<f32>(1.0));

    // Generated depth: structural relief (coarse skeleton highest, age adds)
    let depth = clamp(coarse * 0.5 + mid * 0.3 + fine * 0.15 + colonyAge * 0.2, 0.0, 1.0);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));

    // Semantic alpha: colony density + bioluminescent intensity
    let alpha = clamp(0.2 + clamp(organic, 0.0, 1.0) * 0.55 + bioluminescence * 0.4 + burstRing * 0.3, 0.0, 1.0);
    textureStore(writeTexture, global_id.xy, vec4<f32>(outColor, alpha));
}
