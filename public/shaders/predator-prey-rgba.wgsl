// ═══════════════════════════════════════════════════════════════════
//  Predator-Prey RGBA
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-12
//  Ideas: carnivore pursuit along herbivore gradient; herbivore flee from carnivores
//  A packing: raw (plants, herbivores, carnivores, toxin)
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

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) /
        max(x * (2.43 * x + 0.59) + 0.14, vec3<f32>(0.001)),
        vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
    return fract((p3.x + p3.y) * p3.z);
}

fn stateAt(coord: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
    return textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), dims - vec2<i32>(1)), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let dims = vec2<i32>(res);
    let time = u.config.x;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));

    let prevState = stateAt(coord, dims);
    var plants = prevState.r;
    var herbivores = prevState.g;
    var carnivores = prevState.b;
    var toxin = prevState.a;

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

    let left = stateAt(coord + vec2<i32>(-1, 0), dims);
    let right = stateAt(coord + vec2<i32>(1, 0), dims);
    let down = stateAt(coord + vec2<i32>(0, -1), dims);
    let up = stateAt(coord + vec2<i32>(0, 1), dims);

    let lapP = left.r + right.r + down.r + up.r - 4.0 * plants;
    let lapH = left.g + right.g + down.g + up.g - 4.0 * herbivores;
    let lapC = left.b + right.b + down.b + up.b - 4.0 * carnivores;
    let lapT = left.a + right.a + down.a + up.a - 4.0 * toxin;

    let eatProbability = mix(0.1, 0.5, u.zoom_params.x) * (1.0 + audio.y * 0.2);
    let deathRate = mix(0.001, 0.05, u.zoom_params.y) * (1.0 + audio.x * 0.25);
    let plantGrowth = mix(0.01, 0.05, u.zoom_params.z);
    let toxinStrength = mix(0.4, 1.6, u.zoom_params.w);
    let toxinDecay = 0.95;

    let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let sourceLum = dot(sourceColor.rgb, vec3<f32>(0.299, 0.587, 0.114));

    plants += plantGrowth * sourceLum + lapP * 0.05;

    let grazing = plants * herbivores * eatProbability;
    plants -= grazing;
    herbivores += grazing * 0.5;

    let hunting = herbivores * carnivores * eatProbability * 0.8;
    herbivores -= hunting;
    carnivores += hunting * 0.4;

    herbivores -= herbivores * deathRate * 0.5;
    carnivores -= carnivores * deathRate * 0.8;

    toxin += (herbivores * herbivores + carnivores * carnivores) * 0.002;
    toxin += lapT * 0.02;
    toxin *= toxinDecay;

    let toxinKill = toxin * 0.01 * toxinStrength;
    plants -= toxinKill;
    herbivores -= toxinKill * 2.0;
    carnivores -= toxinKill * 3.0;

    herbivores += lapH * 0.03;
    carnivores += lapC * 0.02;

    // Idea 1 — carnivore pursuit along the herbivore gradient
    let herbGrad = vec2<f32>(right.g - left.g, up.g - down.g);
    let fromHx = select(left.b, right.b, herbGrad.x > 0.0);
    let fromHy = select(down.b, up.b, herbGrad.y > 0.0);
    let pursuit = (fromHx - carnivores) * abs(herbGrad.x) * 0.10 * carnivores
        + (fromHy - carnivores) * abs(herbGrad.y) * 0.10 * carnivores;
    carnivores += pursuit;

    // Idea 2 — herbivore flee away from the carnivore gradient
    let carnGrad = vec2<f32>(right.b - left.b, up.b - down.b);
    let fromFx = select(right.g, left.g, carnGrad.x > 0.0);
    let fromFy = select(up.g, down.g, carnGrad.y > 0.0);
    let flee = (fromFx - herbivores) * abs(carnGrad.x) * 0.10 * herbivores
        + (fromFy - herbivores) * abs(carnGrad.y) * 0.10 * herbivores;
    herbivores += flee;

    plants = clamp(plants, 0.0, 2.0);
    herbivores = clamp(herbivores, 0.0, 2.0);
    carnivores = clamp(carnivores, 0.0, 2.0);
    toxin = clamp(toxin, 0.0, 2.0);

    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = smoothstep(0.08, 0.0, mouseDist) * mouseDown;
    carnivores += mouseInfluence * 0.5;
    toxin -= mouseInfluence * 0.3;
    toxin = max(toxin, 0.0);

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
    carnivores = clamp(carnivores, 0.0, 2.0);
    herbivores = clamp(herbivores, 0.0, 2.0);

    textureStore(dataTextureA, coord, vec4<f32>(plants, herbivores, carnivores, toxin));

    let plantColor = vec3<f32>(0.2, 0.8, 0.2) * min(plants, 1.0);
    let herbColor = vec3<f32>(0.2, 0.5, 0.9) * min(herbivores, 1.0);
    let carnColor = vec3<f32>(0.9, 0.2, 0.2) * min(carnivores, 1.0);
    let toxinColor = vec3<f32>(0.4, 0.0, 0.5) * min(toxin, 1.0) * 0.4;

    var displayColor = plantColor + herbColor + carnColor + toxinColor;
    let animalEnergy = herbivores + carnivores;
    displayColor += vec3<f32>(0.1, 0.1, 0.15) * animalEnergy * 0.3;
    displayColor += vec3<f32>(0.15, 0.05, 0.02) * max(pursuit, 0.0) * 2.0;
    displayColor += vec3<f32>(0.02, 0.12, 0.18) * max(flee, 0.0) * 2.0;

    let mapped = aces(max(displayColor, vec3<f32>(0.0)));
    let ecoDensity = clamp(plants + herbivores + carnivores + toxin * 0.25, 0.0, 1.0);
    let alpha = clamp(sourceColor.a * 0.15 + ecoDensity * 0.75, 0.0, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(mapped, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
