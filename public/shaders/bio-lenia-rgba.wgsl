// ═══════════════════════════════════════════════════════════════════
//  Bio Lenia RGBA
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, temporal, rgba-state-machine, continuous-ca, upgraded-rgba
//  Complexity: Very High
//  Chunks From: bio_lenia_continuous.wgsl (Lenia kernel/growth),
//               alpha-reaction-diffusion-rgba.wgsl (4-species RGBA)
//  Created: 2026-04-18
//  By: Agent CB-11
//  Upgraded: 2026-10-31
//  Ideas: isotropic 9-point Laplacian on the inhibitors (taps already in the kernel loop); nutrient-richness feed map + bass nutrient pulse (Gray-Scott feed made spatial); reaction-front chemiluminescence from A·B² / C·D² (promoted intermediate)
//  A packing: raw sim state (A, B, C, D species concentrations) — C feeds back as state; ACES display RGBA on writeTexture only
// ═══════════════════════════════════════════════════════════════════
//  Four-species continuous cellular automata with Lenia-style smooth
//  growth functions. Each RGBA channel is an independent Lenia species
//  with cross-inhibition between pairs creating complex emergence.
//  R = Species A (activator 1)
//  G = Species B (inhibitor 1)
//  B = Species C (activator 2)
//  A = Species D (inhibitor 2)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    let v = max(x, vec3<f32>(0.0));
    return clamp((v * (a * v + b)) / (v * (c * v + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ CHUNK: bell (from bio_lenia_continuous.wgsl) ═══
fn bell(x: f32, m: f32, s: f32) -> f32 {
    let z = (x - m) / s;
    return exp(-z * z / 2.0);
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

// Smooth value noise: the seed field must be organic blobs, not pixel hash
fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    let a = rand(i);
    let b = rand(i + vec2<f32>(1.0, 0.0));
    let c = rand(i + vec2<f32>(0.0, 1.0));
    let d = rand(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

@compute @workgroup_size(16, 16, 1)
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

    // Seed on an empty state. HEAD seeded only at time < 0.1, i.e. never when the
    // shader is switched to mid-session: C was all zero forever (black screen).
    if (A + B + C + D < 0.00001) {
        let sp = uv * res / 18.0;
        A = 0.5 * vnoise(sp + vec2<f32>(3.1, 7.7));
        C = 0.5 * vnoise(sp + vec2<f32>(11.3, 1.9));
        B = 0.6 * smoothstep(0.55, 0.75, vnoise(sp * 1.3 + vec2<f32>(5.5, 2.2)));
        D = 0.6 * smoothstep(0.55, 0.75, vnoise(sp * 1.3 + vec2<f32>(9.1, 4.4)));
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
    var lapB = 0.0;
    var lapD = 0.0;

    for (var dy: i32 = -r; dy <= r; dy = dy + 1) {
        for (var dx: i32 = -r; dx <= r; dx = dx + 1) {
            let d = sqrt(f32(dx * dx + dy * dy));
            if (d > radius) { continue; }
            let samp = textureLoad(dataTextureC, clamp(coord + vec2<i32>(dx, dy), vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1)), 0);
            let k = kernel(d, radius);
            nbrA += samp.r * k;
            nbrB += samp.g * k;
            nbrC += samp.b * k;
            nbrD += samp.a * k;
            kernelSum += k;
            // ── Idea 1: isotropic 9-point Laplacian (§12.2D) ──
            // Weights 0.2 (edge) / 0.05 (corner) taken from the 3x3 taps this loop already fetches.
            let inner = f32(abs(dx) <= 1 && abs(dy) <= 1 && (dx != 0 || dy != 0));
            let w9 = inner * select(0.05, 0.2, dx == 0 || dy == 0);
            lapB += w9 * samp.g;
            lapD += w9 * samp.a;
        }
    }

    if (kernelSum > 0.0) {
        nbrA /= kernelSum;
        nbrB /= kernelSum;
        nbrC /= kernelSum;
        nbrD /= kernelSum;
    }

    lapB = lapB - B;
    lapD = lapD - D;

    // === LENIA GROWTH FOR EACH SPECIES ===
    // Pair 1: A activates, B inhibits
    let gA = growth(nbrA, growthCenterBase, growthWidth);
    let gB = growth(nbrB, growthCenterBase * 0.8, growthWidth * 1.2);

    // Pair 2: C activates, D inhibits
    let gC = growth(nbrC, growthCenterBase * 1.1, growthWidth * 0.9);
    let gD = growth(nbrD, growthCenterBase * 0.7, growthWidth * 1.3);

    // === 4-SPECIES REACTION-DIFFUSION WITH LENIA GROWTH ===
    // ── Idea 2: nutrient-richness feed map (Gray-Scott feed made spatial) ──
    // Slow drifting patches of richer / poorer feed: colonies thrive in rich patches and
    // thin out in poor ones; bass is a global nutrient pulse. Mean feed stays 0.03.
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let richness = vnoise(uv * res / 70.0 + vec2<f32>(time * 0.03, -time * 0.02)) - 0.5;
    let feed = 0.03 * (1.0 + richness * 0.8) * (1.0 + bass * 0.5);
    let kill = 0.055;
    let diffA = 0.8;
    let diffB = 0.3;
    let diffC = 0.7;
    let diffD = 0.25;

    // Reaction terms + Lenia growth terms
    let dA = diffA * (nbrA - A) * 4.0 - A * B * B + feed * (1.0 - A) - crossInhibit * A * D + gA * 0.5;
    let dB = diffB * (nbrB - B) * 4.0 + lapB * 0.35 + A * B * B - (feed + kill) * B + gB * 0.3;
    let dC = diffC * (nbrC - C) * 4.0 - C * D * D + feed * (1.0 - C) - crossInhibit * C * B + gC * 0.5;
    let dD = diffD * (nbrD - D) * 4.0 + lapD * 0.35 + C * D * D - (feed + kill) * D + gD * 0.3;

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

    // ── Idea 3: reaction-front chemiluminescence ──
    // A·B² and C·D² are the rates the chemistry consumes fuel at; they were computed and
    // thrown away. Light is emitted where the front is actually burning.
    let rate = A * B * B + C * D * D;
    displayColor = displayColor + vec3<f32>(0.55, 0.9, 1.0) * smoothstep(0.0, 0.08, rate) * (0.35 + bass * 0.4);
    displayColor = acesToneMap(displayColor);

    // Mix with source image based on param4
    let sourceMix = u.zoom_params.w;
    let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let finalColor = mix(displayColor, sourceColor, sourceMix * 0.5);

    // Alpha = coverage of the colony field (inhibitor species + burning fronts)
    let coverage = clamp(max(B, D) * 1.6 + rate * 3.0, 0.0, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(finalColor, coverage));

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
