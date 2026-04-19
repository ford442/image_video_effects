// ═══════════════════════════════════════════════════════════════════
//  Bio Lenia RGBA
//  Category: advanced-hybrid
//  Features: mouse-driven, temporal, rgba-state-machine, continuous-ca
//  Complexity: Very High
//  Chunks From: bio_lenia_continuous.wgsl (Lenia kernel/growth),
//               alpha-reaction-diffusion-rgba.wgsl (4-species RGBA)
//  Created: 2026-04-18
//  By: Agent CB-11
// ═══════════════════════════════════════════════════════════════════
//  Four-species continuous cellular automata with Lenia-style smooth
//  growth functions. Each RGBA channel is an independent Lenia species
//  with cross-inhibition between pairs creating complex emergence.
//  R = Species A (activator 1)
//  G = Species B (inhibitor 1)
//  B = Species C (activator 2)
//  A = Species D (inhibitor 2)
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

// ═══ CHUNK: bell (from bio_lenia_continuous.wgsl) ═══
fn bell(x: f32, m: f32, s: f32) -> f32 {
    return exp(-pow((x - m) / s, 2.0) / 2.0);
}

// ═══ CHUNK: smoothStep (from bio_lenia_continuous.wgsl) ═══
fn smoothStep(edge0: f32, edge1: f32, x: f32) -> f32 {
    let t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

// ═══ CHUNK: kernel (from bio_lenia_continuous.wgsl) ═══
fn kernel(r: f32, radius: f32) -> f32 {
    if (r > radius) { return 0.0; }
    let peak = radius * 0.5;
    return bell(r, peak, radius * 0.15);
}

// ═══ CHUNK: growth (from bio_lenia_continuous.wgsl) ═══
fn growth(neighborhood: f32, growthCenter: f32, growthWidth: f32) -> f32 {
    return bell(neighborhood, growthCenter, growthWidth) * 2.0 - 1.0;
}

// ═══ CHUNK: rand (from bio_lenia_continuous.wgsl) ═══
fn rand(co: vec2<f32>) -> f32 {
    return fract(sin(dot(co, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let ps = 1.0 / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let time = u.config.x;

    // Read current state from dataTextureC
    let state = textureLoad(dataTextureC, coord, 0);
    var A = state.r;
    var B = state.g;
    var C = state.b;
    var D = state.a;

    // Seed on first frame
    if (time < 0.1) {
        A = 1.0;
        B = 0.0;
        C = 1.0;
        D = 0.0;
        let centerDist = length(uv - vec2<f32>(0.5));
        if (centerDist < 0.05) {
            B = 0.5;
            D = 0.3;
        }
        let seed2Dist = length(uv - vec2<f32>(0.3, 0.7));
        if (seed2Dist < 0.03) {
            B = 0.4;
        }
    }

    // Parameters
    let radius = 3.0 + u.zoom_params.x * 4.0;
    let growthCenterBase = 0.15 + u.zoom_params.y * 0.25;
    let growthWidth = 0.01 + u.zoom_params.z * 0.04;
    let dt = 0.1 + u.zoom_params.w * 0.2;
    let crossInhibit = u.zoom_params.z * 0.2;

    let invRes = 1.0 / res;
    let r = i32(radius);

    // === LENIA NEIGHBORHOOD INTEGRAL FOR ALL 4 SPECIES ===
    var nbrA = 0.0;
    var nbrB = 0.0;
    var nbrC = 0.0;
    var nbrD = 0.0;
    var kernelSum = 0.0;

    for (var dy: i32 = -r; dy <= r; dy = dy + 1) {
        for (var dx: i32 = -r; dx <= r; dx = dx + 1) {
            let d = sqrt(f32(dx * dx + dy * dy));
            if (d > radius) { continue; }
            let sampleUV = uv + vec2<f32>(f32(dx), f32(dy)) * invRes;
            let samp = textureSampleLevel(dataTextureC, non_filtering_sampler, sampleUV, 0.0);
            let k = kernel(d, radius);
            nbrA += samp.r * k;
            nbrB += samp.g * k;
            nbrC += samp.b * k;
            nbrD += samp.a * k;
            kernelSum += k;
        }
    }

    if (kernelSum > 0.0) {
        nbrA /= kernelSum;
        nbrB /= kernelSum;
        nbrC /= kernelSum;
        nbrD /= kernelSum;
    }

    // === LENIA GROWTH FOR EACH SPECIES ===
    // Pair 1: A activates, B inhibits
    let gA = growth(nbrA, growthCenterBase, growthWidth);
    let gB = growth(nbrB, growthCenterBase * 0.8, growthWidth * 1.2);

    // Pair 2: C activates, D inhibits
    let gC = growth(nbrC, growthCenterBase * 1.1, growthWidth * 0.9);
    let gD = growth(nbrD, growthCenterBase * 0.7, growthWidth * 1.3);

    // === 4-SPECIES REACTION-DIFFUSION WITH LENIA GROWTH ===
    let feed = 0.03;
    let kill = 0.055;
    let diffA = 0.8;
    let diffB = 0.3;
    let diffC = 0.7;
    let diffD = 0.25;

    // Reaction terms + Lenia growth terms
    let dA = diffA * (nbrA - A) * 4.0 - A * B * B + feed * (1.0 - A) - crossInhibit * A * D + gA * 0.5;
    let dB = diffB * (nbrB - B) * 4.0 + A * B * B - (feed + kill) * B + gB * 0.3;
    let dC = diffC * (nbrC - C) * 4.0 - C * D * D + feed * (1.0 - C) - crossInhibit * C * B + gC * 0.5;
    let dD = diffD * (nbrD - D) * 4.0 + C * D * D - (feed + kill) * D + gD * 0.3;

    A = A + dA * dt;
    B = B + dB * dt;
    C = C + dC * dt;
    D = D + dD * dt;

    A = clamp(A, 0.0, 1.0);
    B = clamp(B, 0.0, 1.0);
    C = clamp(C, 0.0, 1.0);
    D = clamp(D, 0.0, 1.0);

    // === MOUSE INJECTION ===
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = smoothstep(0.1, 0.0, mouseDist) * mouseDown;
    B += mouseInfluence * 0.3;
    D += mouseInfluence * 0.2;
    B = clamp(B, 0.0, 1.0);
    D = clamp(D, 0.0, 1.0);

    // === RIPPLE PERTURBATION ===
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age < 1.5 && rDist < 0.06) {
            let strength = smoothstep(0.06, 0.0, rDist) * max(0.0, 1.0 - age);
            B += strength * 0.4;
            D += strength * 0.2;
        }
    }
    B = clamp(B, 0.0, 1.0);
    D = clamp(D, 0.0, 1.0);

    // === RANDOM SEEDING ===
    if (A < 0.01 && rand(uv + time) < 0.001) {
        A = rand(uv + time * 2.0);
    }

    // === STORE STATE ===
    textureStore(dataTextureA, coord, vec4<f32>(A, B, C, D));

    // === VISUALIZATION ===
    let colorA = vec3<f32>(0.0, 0.4, 1.0) * A;
    let colorB = vec3<f32>(1.0, 0.2, 0.0) * B;
    let colorC = vec3<f32>(0.0, 1.0, 0.3) * C;
    let colorD = vec3<f32>(1.0, 0.8, 0.0) * D;
    var displayColor = colorA + colorB + colorC + colorD;
    displayColor = clamp(displayColor, vec3<f32>(0.0), vec3<f32>(1.0));

    // Mix with source image based on param4
    let sourceMix = u.zoom_params.w;
    let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let finalColor = mix(displayColor, sourceColor, sourceMix * 0.5);

    // Alpha = total activator concentration (meaningful)
    let activatorSum = A + C;
    textureStore(writeTexture, coord, vec4<f32>(finalColor, activatorSum));

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
