// ═══════════════════════════════════════════════════════════════════
//  Boids RGBA Ecosystem
//  Category: advanced-hybrid
//  Features: mouse-driven, temporal, rgba-state-machine, flocking
//  Complexity: Very High
//  Chunks From: boids.wgsl (flocking velocity), alpha-multi-state-ecosystem.wgsl (RGBA ecosystem)
//  Created: 2026-04-18
//  By: Agent CB-11
// ═══════════════════════════════════════════════════════════════════
//  Boids-inspired flow-field combined with continuous multi-species
//  ecosystem. RGBA channels store species densities that advect,
//  flock, and compete in a shared environment.
//  R = Species 1 (flockers)
//  G = Species 2 (predators)
//  B = Resource / food
//  A = Toxin / waste
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

// ═══ CHUNK: hash12 (from alpha-multi-state-ecosystem.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Sample 3x3 neighborhood for flocking vectors
fn sampleNeighbors(uv: vec2<f32>, ps: vec2<f32>) -> array<vec4<f32>, 9> {
    var n: array<vec4<f32>, 9>;
    var idx = 0;
    for (var dy: i32 = -1; dy <= 1; dy = dy + 1) {
        for (var dx: i32 = -1; dx <= 1; dx = dx + 1) {
            let sampleUV = clamp(uv + vec2<f32>(f32(dx), f32(dy)) * ps, vec2<f32>(0.0), vec2<f32>(1.0));
            n[idx] = textureSampleLevel(dataTextureC, u_sampler, sampleUV, 0.0);
            idx = idx + 1;
        }
    }
    return n;
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
    var s1 = prevState.r;
    var s2 = prevState.g;
    var resource = prevState.b;
    var toxin = prevState.a;

    // Seed on first frame
    if (time < 0.1) {
        s1 = 0.0;
        s2 = 0.0;
        resource = 0.5;
        toxin = 0.0;
        let n1 = hash12(uv * 100.0 + vec2<f32>(12.9898, 78.233));
        if (n1 > 0.92) { s1 = 0.8; }
        let n2 = hash12(uv * 100.0 + vec2<f32>(93.0, 17.0));
        if (n2 > 0.95) { s2 = 0.7; }
    }

    s1 = clamp(s1, 0.0, 2.0);
    s2 = clamp(s2, 0.0, 2.0);
    resource = clamp(resource, 0.0, 2.0);
    toxin = clamp(toxin, 0.0, 2.0);

    let n = sampleNeighbors(uv, ps);
    let center = n[4];

    // === FLOCKING VECTOR FIELD ===
    // Compute average neighbor positions weighted by density
    var s1Avg = vec2<f32>(0.0);
    var s2Avg = vec2<f32>(0.0);
    var s1Count = 0.0;
    var s2Count = 0.0;
    var s1Sep = vec2<f32>(0.0);
    var s2Sep = vec2<f32>(0.0);

    for (var i: i32 = 0; i < 9; i = i + 1) {
        if (i == 4) { continue; }
        let offset = vec2<f32>(f32(i % 3 - 1), f32(i / 3 - 1)) * ps;
        if (n[i].r > 0.1) {
            s1Avg = s1Avg + offset * n[i].r;
            s1Count = s1Count + n[i].r;
            // Separation: push away if too close
            let dist = length(offset);
            if (dist < ps.x * 2.0 && dist > 0.0) {
                s1Sep = s1Sep - normalize(offset) / dist * ps.x;
            }
        }
        if (n[i].g > 0.1) {
            s2Avg = s2Avg + offset * n[i].g;
            s2Count = s2Count + n[i].g;
            let dist = length(offset);
            if (dist < ps.x * 2.0 && dist > 0.0) {
                s2Sep = s2Sep - normalize(offset) / dist * ps.x;
            }
        }
    }

    // Normalize flocking vectors
    var s1Flow = vec2<f32>(0.0);
    var s2Flow = vec2<f32>(0.0);
    if (s1Count > 0.0) {
        s1Flow = s1Avg / s1Count * 0.3 + s1Sep * 2.0;
    }
    if (s2Count > 0.0) {
        s2Flow = s2Avg / s2Count * 0.3 + s2Sep * 2.0;
    }

    // Advection: move species along their flocking flow
    let advectS1UV = clamp(uv + s1Flow, vec2<f32>(0.0), vec2<f32>(1.0));
    let advectS2UV = clamp(uv + s2Flow, vec2<f32>(0.0), vec2<f32>(1.0));
    let advectedS1 = textureSampleLevel(dataTextureC, u_sampler, advectS1UV, 0.0).r;
    let advectedS2 = textureSampleLevel(dataTextureC, u_sampler, advectS2UV, 0.0).g;

    // Blend current with advected (semi-Lagrangian)
    let advectionStrength = 0.6;
    s1 = mix(s1, advectedS1, advectionStrength);
    s2 = mix(s2, advectedS2, advectionStrength);

    // === DIFFUSION ===
    let lapS1 = n[3].r + n[5].r + n[1].r + n[7].r - 4.0 * s1;
    let lapS2 = n[3].g + n[5].g + n[1].g + n[7].g - 4.0 * s2;
    let lapResource = n[3].b + n[5].b + n[1].b + n[7].b - 4.0 * resource;
    let lapToxin = n[3].a + n[5].a + n[1].a + n[7].a - 4.0 * toxin;

    // === PARAMETERS ===
    let flockCohesion = mix(0.01, 0.06, u.zoom_params.x);
    let predationRate = mix(0.01, 0.05, u.zoom_params.y);
    let toxinDecay = 0.95;
    let resourceRegen = 0.001;
    let dt = 0.5;

    // === ECOSYSTEM DYNAMICS ===
    // Species consume resource to grow
    let food1 = s1 * resource * flockCohesion;
    let food2 = s2 * resource * flockCohesion * 0.8;

    // Predation: s2 eats s1
    let predation = s1 * s2 * predationRate;

    // Species produce toxin
    let toxinProduction1 = s1 * 0.005;
    let toxinProduction2 = s2 * 0.004;

    // Toxin hurts both species
    let toxinDamage = toxin * 0.02;

    // Resource regeneration
    resource += resourceRegen - food1 - food2;
    resource += lapResource * 0.1;

    // Species update
    s1 += food1 - predation - toxinDamage + lapS1 * 0.05;
    s2 += food2 + predation * 0.3 - toxinDamage + lapS2 * 0.05;

    // Toxin update
    toxin += toxinProduction1 + toxinProduction2 - toxin * 0.01;
    toxin += lapToxin * 0.08;
    toxin *= toxinDecay;

    // Natural death
    s1 *= 0.998;
    s2 *= 0.998;

    // Clamp
    s1 = clamp(s1, 0.0, 2.0);
    s2 = clamp(s2, 0.0, 2.0);
    resource = clamp(resource, 0.0, 2.0);
    toxin = clamp(toxin, 0.0, 2.0);

    // === MOUSE INTERACTION ===
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = smoothstep(0.1, 0.0, mouseDist) * mouseDown;
    // Mouse adds resource and removes toxin (nurturing)
    resource += mouseInfluence * 0.5;
    toxin -= mouseInfluence * 0.3;
    toxin = max(toxin, 0.0);
    // Mouse attracts species 1 (flocking toward cursor)
    s1 += mouseInfluence * 0.3;

    // Ripples seed new life
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age < 1.0 && rDist < 0.04) {
            let strength = smoothstep(0.04, 0.0, rDist) * max(0.0, 1.0 - age);
            let isEven = select(1.0, 0.0, f32(i) % 2.0 < 1.0);
            s1 += strength * isEven * 0.5;
            s2 += strength * (1.0 - isEven) * 0.5;
        }
    }
    s1 = clamp(s1, 0.0, 2.0);
    s2 = clamp(s2, 0.0, 2.0);

    // === STORE STATE ===
    textureStore(dataTextureA, coord, vec4<f32>(s1, s2, resource, toxin));

    // === VISUALIZATION ===
    // Species 1 = cyan/teal, Species 2 = magenta/pink, Resource = green, Toxin = dark purple
    let colorS1 = vec3<f32>(0.0, 0.8, 1.0) * min(s1, 1.0);
    let colorS2 = vec3<f32>(1.0, 0.2, 0.6) * min(s2, 1.0);
    let colorResource = vec3<f32>(0.2, 0.7, 0.2) * min(resource, 1.0) * 0.3;
    let colorToxin = vec3<f32>(0.3, 0.0, 0.4) * min(toxin, 1.0) * 0.5;

    var displayColor = colorS1 + colorS2 + colorResource + colorToxin;
    displayColor = clamp(displayColor, vec3<f32>(0.0), vec3<f32>(1.0));

    // Highlight flow edges
    let s1Grad = length(vec2<f32>(n[3].r - n[5].r, n[1].r - n[7].r));
    let s2Grad = length(vec2<f32>(n[3].g - n[5].g, n[1].g - n[7].g));
    let edgeHighlight = (s1Grad + s2Grad) * 2.0;
    displayColor += vec3<f32>(1.0, 0.9, 0.5) * edgeHighlight * 0.3;
    displayColor = clamp(displayColor, vec3<f32>(0.0), vec3<f32>(1.0));

    // Alpha = total biomass (meaningful, not hardcoded)
    let biomass = min(s1 + s2, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(displayColor, biomass));

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
