// ═══════════════════════════════════════════════════════════════════
//  Cellular Automata RGBA
//  Category: simulation
//  Features: simulation, rgba-state-machine, temporal, mouse-driven, ecosystem
//  Complexity: High
//  Chunks From: cellular-automata-3d.wgsl, alpha-reaction-diffusion-rgba.wgsl
//  Created: 2026-04-18
//  By: Agent CB-2 - RGBA Simulation Upgrader
// ═══════════════════════════════════════════════════════════════════
//  2D ecosystem cellular automaton with 4 interacting species.
//  RGBA Channels:
//    R = Plant biomass (0=barren, 1=lush vegetation)
//    G = Herbivore density (0=none, 1=overpopulated)
//    B = Predator density (0=none, 1=overpopulated)
//    A = Soil nutrients / decay (0=depleted, 1=rich)
//  Rules: Plants grow from nutrients; herbivores eat plants;
//         predators eat herbivores; all dead matter becomes nutrients.
//  Why f32: Continuous densities allow gradual population changes
//  and stable predator-prey oscillations impossible in binary CA.
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let time = u.config.x;

    // Read current ecosystem state
    let state = textureLoad(dataTextureC, coord, 0);
    var plants = state.r;
    var herbivores = state.g;
    var predators = state.b;
    var nutrients = state.a;

    // Seed on first frame
    if (time < 0.1) {
        let h = hash12(uv * 13.37);
        plants = select(0.0, 0.5 + h * 0.5, h > 0.6);
        herbivores = select(0.0, 0.2 + h * 0.3, h > 0.85);
        predators = select(0.0, 0.1 + h * 0.2, h > 0.92);
        nutrients = 0.3 + h * 0.4;
    }

    // === PARAMETERS ===
    let growthRate = mix(0.01, 0.05, u.zoom_params.x);
    let herbivoreEfficiency = mix(0.1, 0.4, u.zoom_params.y);
    let predatorEfficiency = mix(0.05, 0.2, u.zoom_params.z);
    let decayRate = mix(0.005, 0.02, u.zoom_params.w);

    // === NEIGHBOR AVERAGES (for spread) ===
    let ps = 1.0 / res;
    let left = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let right = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let down = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let up = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    let avgPlants = (left.r + right.r + down.r + up.r) * 0.25;
    let avgHerbivores = (left.g + right.g + down.g + up.g) * 0.25;
    let avgPredators = (left.b + right.b + down.b + up.b) * 0.25;

    // === ECOSYSTEM DYNAMICS ===
    // Plants grow from nutrients, spread to neighbors
    let plantGrowth = growthRate * nutrients * (1.0 - plants) * (1.0 + avgPlants);
    let plantEaten = herbivores * plants * 0.3;
    plants = plants + plantGrowth - plantEaten;

    // Herbivores eat plants, reproduce, die, spread
    let herbivoreGrowth = herbivoreEfficiency * plantEaten;
    let herbivoreDeath = herbivores * decayRate * 2.0;
    let herbivorePredation = predators * herbivores * 0.5;
    let herbivoreSpread = (avgHerbivores - herbivores) * 0.02 * herbivores;
    herbivores = herbivores + herbivoreGrowth - herbivoreDeath - herbivorePredation + herbivoreSpread;

    // Predators eat herbivores, reproduce, die, spread
    let predatorGrowth = predatorEfficiency * herbivorePredation;
    let predatorDeath = predators * decayRate * 1.5;
    let predatorSpread = (avgPredators - predators) * 0.01 * predators;
    predators = predators + predatorGrowth - predatorDeath + predatorSpread;

    // Nutrients: dead matter + plant decomposition - plant consumption
    let decomposition = plantEaten * 0.1 + herbivoreDeath * 0.5 + predatorDeath * 0.7;
    let nutrientConsumption = plantGrowth * 0.8;
    nutrients = nutrients + decomposition - nutrientConsumption;

    // === MOUSE INTERACTION ===
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = smoothstep(0.12, 0.0, mouseDist) * mouseDown;

    // Clicking adds plants (seeds) and nutrients
    plants += mouseInfluence * 0.5;
    nutrients += mouseInfluence * 0.3;

    // === RIPPLE PERTURBATION ===
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age < 2.0 && rDist < 0.08) {
            let strength = smoothstep(0.08, 0.0, rDist) * max(0.0, 1.0 - age * 0.5);
            // Ripples disturb ecosystem: temporary nutrient boost
            nutrients += strength * 0.3;
            // Scare herbivores away
            herbivores -= strength * 0.1;
        }
    }

    // Clamp all
    plants = clamp(plants, 0.0, 1.0);
    herbivores = clamp(herbivores, 0.0, 1.0);
    predators = clamp(predators, 0.0, 1.0);
    nutrients = clamp(nutrients, 0.0, 1.0);

    // === STORE STATE ===
    textureStore(dataTextureA, coord, vec4<f32>(plants, herbivores, predators, nutrients));

    // === STATE -> VISUAL COLOR MAPPING ===
    let plantColor = vec3<f32>(0.1, 0.7, 0.2) * plants;
    let herbivoreColor = vec3<f32>(0.9, 0.8, 0.3) * herbivores;
    let predatorColor = vec3<f32>(0.7, 0.1, 0.1) * predators;
    let nutrientColor = vec3<f32>(0.4, 0.25, 0.1) * nutrients;

    var displayColor = plantColor + herbivoreColor + predatorColor + nutrientColor;
    displayColor = clamp(displayColor, vec3<f32>(0.0), vec3<f32>(1.0));

    // Add subtle texture variation
    let noise = hash12(uv * 200.0 + time * 0.01);
    displayColor *= 0.95 + noise * 0.1;

    // Glow from dense populations
    let totalBio = plants + herbivores + predators;
    displayColor += vec3<f32>(0.05, 0.08, 0.03) * totalBio * totalBio;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let alpha = mix(0.7, 1.0, totalBio * 0.5 + nutrients * 0.3);

    textureStore(writeTexture, coord, vec4<f32>(displayColor, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth * (1.0 - totalBio * 0.1), 0.0, 0.0, 0.0));
}
