// ═══════════════════════════════════════════════════════════════════
//  Boids RGBA Ecosystem
//  Category: advanced-hybrid
//  Features: mouse-driven, temporal, rgba-state-machine, flocking, upgraded-rgba
//  Complexity: Very High
//  Chunks From: boids.wgsl (flocking velocity), alpha-multi-state-ecosystem.wgsl (RGBA ecosystem)
//  Created: 2026-04-18
//  Upgraded: 2026-10-31
//  Ideas: predator-evasion and prey-interception steering; flock-heading wing-flash and wake
//  A packing: raw (s1, s2, resourceVal, toxin)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) /
        max(x * (2.43 * x + 0.59) + 0.14, vec3<f32>(0.001)),
        vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ CHUNK: hash12 (from alpha-multi-state-ecosystem.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn stateAt(p: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
    return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), dims - vec2<i32>(1)), 0);
}

// Exact bilinear read on dataTextureC via textureLoad (never filtered sampler on C)
fn sampleStateBilinear(uv: vec2<f32>, dims: vec2<i32>) -> vec4<f32> {
    let fcoord = clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * vec2<f32>(dims) - vec2<f32>(0.5);
    let p0 = vec2<i32>(floor(fcoord));
    let f = fract(fcoord);
    let c00 = stateAt(p0, dims);
    let c10 = stateAt(p0 + vec2<i32>(1, 0), dims);
    let c01 = stateAt(p0 + vec2<i32>(0, 1), dims);
    let c11 = stateAt(p0 + vec2<i32>(1, 1), dims);
    return mix(mix(c00, c10, f.x), mix(c01, c11, f.x), f.y);
}

// Sample 3x3 neighborhood for flocking vectors via exact textureLoad
fn sampleNeighbors(coord: vec2<i32>, dims: vec2<i32>) -> array<vec4<f32>, 9> {
    var n: array<vec4<f32>, 9>;
    var idx = 0;
    for (var dy: i32 = -1; dy <= 1; dy = dy + 1) {
        for (var dx: i32 = -1; dx <= 1; dx = dx + 1) {
            n[idx] = stateAt(coord + vec2<i32>(dx, dy), dims);
            idx = idx + 1;
        }
    }
    return n;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let dims = vec2<i32>(res);
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let ps = 1.0 / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let time = u.config.x;

    // Read previous state
    let prevState = stateAt(coord, dims);
    var s1 = prevState.r;
    var s2 = prevState.g;
    var resourceVal = prevState.b;
    var toxin = prevState.a;

    // Seed on first frame
    if (time < 0.1) {
        s1 = 0.0;
        s2 = 0.0;
        resourceVal = 0.5;
        toxin = 0.0;
        let n1 = hash12(uv * 100.0 + vec2<f32>(12.9898, 78.233));
        if (n1 > 0.92) { s1 = 0.8; }
        let n2 = hash12(uv * 100.0 + vec2<f32>(93.0, 17.0));
        if (n2 > 0.95) { s2 = 0.7; }
    }

    s1 = clamp(s1, 0.0, 2.0);
    s2 = clamp(s2, 0.0, 2.0);
    resourceVal = clamp(resourceVal, 0.0, 2.0);
    toxin = clamp(toxin, 0.0, 2.0);

    let n = sampleNeighbors(coord, dims);

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

    // === PARAMETERS ===
    let flockCohesion = mix(0.01, 0.06, u.zoom_params.x);
    let predationRate = mix(0.01, 0.05, u.zoom_params.y);
    let diffusion = mix(0.02, 0.14, u.zoom_params.z);
    let toxinStrength = mix(0.005, 0.045, u.zoom_params.w);
    let toxinDecay = 0.95;
    let resourceRegen = 0.001;

    // Normalize flocking vectors
    var s1Flow = vec2<f32>(0.0);
    var s2Flow = vec2<f32>(0.0);
    if (s1Count > 0.0) {
        s1Flow = s1Avg / s1Count * (0.2 + u.zoom_params.x * 0.25) + s1Sep * 2.0;
    }
    if (s2Count > 0.0) {
        s2Flow = s2Avg / s2Count * (0.2 + u.zoom_params.x * 0.25) + s2Sep * 2.0;
    }

    // ── Idea 1: predator-evasion & prey-interception steering ──
    let resGrad = vec2<f32>(n[5].b - n[3].b, n[7].b - n[1].b) * ps * 0.45;
    if (s2Count > 0.0) {
        let threatVec = s2Avg / s2Count;
        s1Flow -= threatVec * (0.45 + u.zoom_params.y * 0.35);
    }
    s1Flow += resGrad;
    if (s1Count > 0.0) {
        let preyVec = s1Avg / s1Count;
        s2Flow += preyVec * (0.40 + u.zoom_params.y * 0.40);
    }

    // Advection: move species along their flocking flow
    let advectS1UV = clamp(uv + s1Flow, vec2<f32>(0.0), vec2<f32>(1.0));
    let advectS2UV = clamp(uv + s2Flow, vec2<f32>(0.0), vec2<f32>(1.0));
    let advectedS1 = sampleStateBilinear(advectS1UV, dims).r;
    let advectedS2 = sampleStateBilinear(advectS2UV, dims).g;

    // Blend current with advected (semi-Lagrangian)
    let advectionStrength = 0.6;
    s1 = mix(s1, advectedS1, advectionStrength);
    s2 = mix(s2, advectedS2, advectionStrength);

    // === DIFFUSION ===
    let lapS1 = n[3].r + n[5].r + n[1].r + n[7].r - 4.0 * s1;
    let lapS2 = n[3].g + n[5].g + n[1].g + n[7].g - 4.0 * s2;
    let lapResource = n[3].b + n[5].b + n[1].b + n[7].b - 4.0 * resourceVal;
    let lapToxin = n[3].a + n[5].a + n[1].a + n[7].a - 4.0 * toxin;

    // === ECOSYSTEM DYNAMICS ===
    // Species consume resourceVal to grow
    let food1 = s1 * resourceVal * flockCohesion;
    let food2 = s2 * resourceVal * flockCohesion * 0.8;

    // Predation: s2 eats s1
    let predation = s1 * s2 * predationRate;

    // Species produce toxin (scaled by toxinStrength slider)
    let toxinProduction1 = s1 * (0.002 + toxinStrength * 0.16);
    let toxinProduction2 = s2 * (0.0015 + toxinStrength * 0.13);

    // Toxin hurts both species
    let toxinDamage = toxin * toxinStrength;

    // Resource regeneration
    resourceVal += resourceRegen - food1 - food2;
    resourceVal += lapResource * (diffusion * 1.4);

    // Species update
    s1 += food1 - predation - toxinDamage + lapS1 * diffusion;
    s2 += food2 + predation * 0.3 - toxinDamage + lapS2 * diffusion;

    // Toxin update
    toxin += toxinProduction1 + toxinProduction2 - toxin * 0.01;
    toxin += lapToxin * (diffusion * 1.15);
    toxin *= toxinDecay;

    // Natural death
    s1 *= 0.998;
    s2 *= 0.998;

    // Clamp
    s1 = clamp(s1, 0.0, 2.0);
    s2 = clamp(s2, 0.0, 2.0);
    resourceVal = clamp(resourceVal, 0.0, 2.0);
    toxin = clamp(toxin, 0.0, 2.0);

    // === MOUSE INTERACTION ===
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = smoothstep(0.1, 0.0, mouseDist) * mouseDown;
    // Mouse adds resourceVal and removes toxin (nurturing)
    resourceVal += mouseInfluence * 0.5;
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
    textureStore(dataTextureA, coord, vec4<f32>(s1, s2, resourceVal, toxin));

    // === VISUALIZATION ===
    // Species 1 = cyan/teal, Species 2 = magenta/pink, Resource = green, Toxin = dark purple
    let colorS1 = vec3<f32>(0.0, 0.8, 1.0) * min(s1, 1.0);
    let colorS2 = vec3<f32>(1.0, 0.2, 0.6) * min(s2, 1.0);
    let colorResource = vec3<f32>(0.2, 0.7, 0.2) * min(resourceVal, 1.0) * 0.3;
    let colorToxin = vec3<f32>(0.3, 0.0, 0.4) * min(toxin, 1.0) * 0.5;

    var displayColor = colorS1 + colorS2 + colorResource + colorToxin;

    // Highlight flow edges
    let s1GradVec = vec2<f32>(n[5].r - n[3].r, n[7].r - n[1].r);
    let s2GradVec = vec2<f32>(n[5].g - n[3].g, n[7].g - n[1].g);
    let s1Grad = length(s1GradVec);
    let s2Grad = length(s2GradVec);
    let edgeHighlight = (s1Grad + s2Grad) * 2.0;
    displayColor += vec3<f32>(1.0, 0.9, 0.5) * edgeHighlight * 0.3;

    // ── Idea 2: flock-heading wing-flash & wake along s1Flow / s2Flow ──
    let s1Dir = s1Flow / max(length(s1Flow), 0.0001);
    let s2Dir = s2Flow / max(length(s2Flow), 0.0001);
    let s1WingCrest = max(dot(s1GradVec / max(s1Grad, 0.001), s1Dir), 0.0) * smoothstep(0.0, 0.004, length(s1Flow));
    let s2WingCrest = max(dot(s2GradVec / max(s2Grad, 0.001), s2Dir), 0.0) * smoothstep(0.0, 0.004, length(s2Flow));
    displayColor += vec3<f32>(0.45, 0.98, 1.0) * s1WingCrest * min(s1, 1.0) * 0.32;
    displayColor += vec3<f32>(1.0, 0.45, 0.78) * s2WingCrest * min(s2, 1.0) * 0.32;

    let toneMapped = aces(max(displayColor, vec3<f32>(0.0)));

    // Alpha = total biomass (meaningful, not hardcoded)
    let biomass = clamp(s1 + s2, 0.0, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(toneMapped, biomass));

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
