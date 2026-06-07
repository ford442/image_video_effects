// ═══════════════════════════════════════════════════════════════════
//  Predator-Prey RGBA
//  Category: advanced-hybrid
//  Features: mouse-driven, temporal, rgba-state-machine, ecology
//  Complexity: Very High
//  Chunks From: predator-prey.wgsl (ecosystem dynamics),
//               alpha-multi-state-ecosystem.wgsl (RGBA state machine)
//  Created: 2026-04-18
//  By: Agent CB-11
// ═══════════════════════════════════════════════════════════════════
//  Continuous-density predator-prey ecosystem packed into RGBA32FLOAT.
//  Plants photosynthesize, herbivores graze, carnivores hunt. Toxins
//  accumulate from overpopulation. Species diffuse across the grid.
//  R = Plant density
//  G = Herbivore density
//  B = Carnivore density
//  A = Environmental toxin / nutrient cycle
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

fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let ps = 1.0 / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let time = u.config.x;

    // Read previous state
    let prevState = textureLoad(dataTextureC, coord, 0);
    var plants = prevState.r;
    var herbivores = prevState.g;
    var carnivores = prevState.b;
    var toxin = prevState.a;

    // Seed on first frame
    if (time < 0.1) {
        plants = 0.0;
        herbivores = 0.0;
        carnivores = 0.0;
        toxin = 0.0;
        let n = hash21(uv * 500.0);
        if (n > 0.85) { plants = 0.6; }
        if (n > 0.95) { herbivores = 0.3; }
        if (n > 0.98) { carnivores = 0.15; }
    }

    plants = clamp(plants, 0.0, 2.0);
    herbivores = clamp(herbivores, 0.0, 2.0);
    carnivores = clamp(carnivores, 0.0, 2.0);
    toxin = clamp(toxin, 0.0, 2.0);

    // Sample neighbors
    let left = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let right = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let down = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let up = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    let lapP = left.r + right.r + down.r + up.r - 4.0 * plants;
    let lapH = left.g + right.g + down.g + up.g - 4.0 * herbivores;
    let lapC = left.b + right.b + down.b + up.b - 4.0 * carnivores;
    let lapT = left.a + right.a + down.a + up.a - 4.0 * toxin;

    // Parameters
    let eatProbability = mix(0.1, 0.5, u.zoom_params.x);
    let deathRate = mix(0.001, 0.05, u.zoom_params.y);
    let plantGrowth = mix(0.01, 0.05, u.zoom_params.z);
    let toxinDecay = 0.95;

    // Source image influence (light drives photosynthesis)
    let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let sourceLum = dot(sourceColor.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // === ECOSYSTEM DYNAMICS ===
    // Plants photosynthesize and diffuse
    plants += plantGrowth * sourceLum + lapP * 0.05;

    // Herbivores eat plants
    let grazing = plants * herbivores * eatProbability;
    plants -= grazing;
    herbivores += grazing * 0.5;

    // Carnivores eat herbivores
    let hunting = herbivores * carnivores * eatProbability * 0.8;
    herbivores -= hunting;
    carnivores += hunting * 0.4;

    // Natural death
    herbivores -= herbivores * deathRate * 0.5;
    carnivores -= carnivores * deathRate * 0.8;

    // Overpopulation produces toxin
    toxin += (herbivores * herbivores + carnivores * carnivores) * 0.002;
    toxin += lapT * 0.02;
    toxin *= toxinDecay;

    // Toxin kills all species
    let toxinKill = toxin * 0.01;
    plants -= toxinKill;
    herbivores -= toxinKill * 2.0;
    carnivores -= toxinKill * 3.0;

    // Diffusion of animals
    herbivores += lapH * 0.03;
    carnivores += lapC * 0.02;

    // Clamp
    plants = clamp(plants, 0.0, 2.0);
    herbivores = clamp(herbivores, 0.0, 2.0);
    carnivores = clamp(carnivores, 0.0, 2.0);
    toxin = clamp(toxin, 0.0, 2.0);

    // === MOUSE INTERACTION ===
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = smoothstep(0.08, 0.0, mouseDist) * mouseDown;
    // Mouse spawns carnivores
    carnivores += mouseInfluence * 0.5;
    // Mouse clears toxin
    toxin -= mouseInfluence * 0.3;
    toxin = max(toxin, 0.0);

    // === RIPPLE SPAWN ===
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age < 0.5 && rDist < 0.03) {
            let strength = smoothstep(0.03, 0.0, rDist) * max(0.0, 1.0 - age * 2.0);
            plants += strength * 0.5;
        }
    }
    plants = clamp(plants, 0.0, 2.0);

    // === STORE STATE ===
    textureStore(dataTextureA, coord, vec4<f32>(plants, herbivores, carnivores, toxin));

    // === VISUALIZATION ===
    let plantColor = vec3<f32>(0.2, 0.8, 0.2) * min(plants, 1.0);
    let herbColor = vec3<f32>(0.2, 0.5, 0.9) * min(herbivores, 1.0);
    let carnColor = vec3<f32>(0.9, 0.2, 0.2) * min(carnivores, 1.0);
    let toxinColor = vec3<f32>(0.4, 0.0, 0.5) * min(toxin, 1.0) * 0.4;

    var displayColor = plantColor + herbColor + carnColor + toxinColor;
    displayColor = clamp(displayColor, vec3<f32>(0.0), vec3<f32>(1.0));

    // Energy glow around animals
    let animalEnergy = herbivores + carnivores;
    displayColor += vec3<f32>(0.1, 0.1, 0.15) * animalEnergy * 0.3;
    displayColor = clamp(displayColor, vec3<f32>(0.0), vec3<f32>(1.0));

    // Alpha = total ecosystem density (meaningful)
    let ecoDensity = min(plants + herbivores + carnivores, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(displayColor, ecoDensity));

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
