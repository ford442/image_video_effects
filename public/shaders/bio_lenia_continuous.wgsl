// ═══════════════════════════════════════════════════════════════════════════════
//  bio_lenia_continuous.wgsl - Continuous Cellular Automata (Lenia)
//  
//  Agent: Algorithmist + Interactivist
//  Techniques:
//    - Lenia continuous CA (smoothLife-like)
//    - Multiple kernel radii
//    - Growth function with bell curve
//    - Mouse-DOWN gated spawn (fixed from stuck ripple-count gate)
//    - Audio-reactive growth parameters (real mids -> slow growthCenter "seasons")
//    - Second competing species in dataTextureA.g with cross-feeding inhibition
//    - Click seed bombs from the ripples[] ring buffer (species-B colonies)
//  
//  Target: 4.7★ rating
//
//  Upgraded: 2026-10-25
//  Ideas: isotropic 9-point Laplacian diffusion on both species (§12.2D); metabolic growth
//         rim — the growth value g, already computed, lights advancing fronts and dims
//         starving cores (§12.1 tactic 3)
//  HEAD fixes: single-pixel spores always died (growth(≈0) = -1) → soft noisy spore blobs where
//         the neighbourhood is empty; growth window re-centred (the old 0.25/0.018 default was
//         dead or froze into stamps in a numpy port); inherited-C sentinel in A.b
//  A packing: raw sim state — A.r species A, A.g species B, A.b = 0.4375 "I wrote this" marker,
//         A.a = 1. Display (ACES) is on writeTexture only.
// ═══════════════════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;

// Bell curve function for Lenia growth
fn bell(x: f32, m: f32, s: f32) -> f32 {
    return exp(-pow((x - m) / s, 2.0) / 2.0);
}

// Smooth step
fn smoothStep(edge0: f32, edge1: f32, x: f32) -> f32 {
    let t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

// Lenia kernel (smooth ring)
fn kernel(r: f32, radius: f32) -> f32 {
    if (r > radius) {
        return 0.0;
    }
    // Ring kernel: peaks at r = radius/2
    let peak = radius * 0.5;
    return bell(r, peak, radius * 0.15);
}

// Growth function for Lenia
fn growth(neighborhood: f32, growthCenter: f32, growthWidth: f32) -> f32 {
    return bell(neighborhood, growthCenter, growthWidth) * 2.0 - 1.0;
}

// Marker in A.b: a shader switch leaves the PREVIOUS shader's A in C (alpha 1, arbitrary rgb);
// without the marker that would be read as Lenia state.
const MARK: f32 = 0.4375;

// Previous state of one texel: (species A, species B), exact load, zero when C is foreign.
fn loadState(c: vec2<i32>, dims: vec2<i32>) -> vec2<f32> {
    let v = textureLoad(dataTextureC, clamp(c, vec2<i32>(0), dims - vec2<i32>(1)), 0);
    let own = select(0.0, 1.0, abs(v.b - MARK) < 0.002);
    return v.rg * own;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Pseudo-random
fn rand(co: vec2<f32>) -> f32 {
    return fract(sin(dot(co, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// HSV to RGB helper
fn hsv2rgb(hue: f32, sat: f32, val: f32) -> vec3<f32> {
    let c = val * sat;
    let x = c * (1.0 - abs(fract(hue * 6.0) * 2.0 - 1.0));
    let m = val - c;

    var rgb: vec3<f32>;
    let h = hue * 6.0;
    if (h < 1.0) {
        rgb = vec3<f32>(c, x, 0.0);
    } else if (h < 2.0) {
        rgb = vec3<f32>(x, c, 0.0);
    } else if (h < 3.0) {
        rgb = vec3<f32>(0.0, c, x);
    } else if (h < 4.0) {
        rgb = vec3<f32>(0.0, x, c);
    } else if (h < 5.0) {
        rgb = vec3<f32>(x, 0.0, c);
    } else {
        rgb = vec3<f32>(c, 0.0, x);
    }

    return rgb + m;
}

// Species A color: biological green-to-yellow palette
fn leniaColor(value: f32, time: f32) -> vec3<f32> {
    let hue = 0.25 + value * 0.15 + sin(time * 0.1) * 0.05;
    let sat = 0.6 + value * 0.4;
    let val = 0.3 + value * 0.7;
    return hsv2rgb(hue, sat, val);
}

// Species B color: cool magenta/violet palette so colonies visibly compete
fn leniaColorB(value: f32, time: f32) -> vec3<f32> {
    let hue = 0.78 + value * 0.12 + sin(time * 0.07) * 0.04;
    let sat = 0.55 + value * 0.45;
    let val = 0.25 + value * 0.75;
    return hsv2rgb(hue, sat, val);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let dims = vec2<i32>(resolution);
    
    // ── Parameters (slider contract: zoom_params.x/y/z/w) ───────────────────
    let radius = 5.0 + u.zoom_params.x * 15.0;           // 5-20 pixel radius
    // Re-centred so the saved defaults (0.4 / 0.2) land in the living window (μ≈0.15, σ≈0.028);
    // the old 0.15+0.25y / 0.01+0.04z mapping put them at μ 0.25, σ 0.018, where every blob died.
    let growthCenter = 0.07 + u.zoom_params.y * 0.2;     // 0.07-0.27
    let growthWidth = 0.02 + u.zoom_params.z * 0.04;     // 0.02-0.06
    let dt = 0.1 + u.zoom_params.w * 0.2;                // 0.1-0.3 time step
    
    // Species B: same bell() family, tuned to a smaller, hungrier niche
    let radiusB = radius * 0.6;                          // tighter kernel
    let growthCenterB = growthCenter + 0.06;             // prefers denser crowds
    let growthWidthB = growthWidth * 1.3;                // more tolerant
    let dtB = dt * 0.85;                                 // slightly slower metabolism
    
    // ── Interaction & audio truth ───────────────────────────────────────────
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;                     // 1.0 only while held
    let audioMids = clamp(plasmaBuffer[0].y, 0.0, 1.0);  // real mids
    
    // Audio "seasons": slow wobble of the growth center driven by mids.
    // Classic Lenia modulation - shifts the whole ecosystem's climate gently.
    let season = sin(time * 0.23) * 0.5 + 0.5;
    let growthCenterA = growthCenter + (audioMids - 0.5) * 0.08 * season;
    
    // ── Sample current state from dataTextureC (feedback) ───────────────────
    let cur = loadState(coord, dims);
    let currentState = cur.x;
    let currentStateB = cur.y;
    
    // ── Neighborhood integral (O(r^2) kernel loop - expensive by design) ────
    var neighborhood = 0.0;
    var neighborhoodB = 0.0;
    var kernelSum = 0.0;
    var kernelSumB = 0.0;
    // ── Idea 1: isotropic 9-point Laplacian taps (§12.2D), gathered from the loop's own loads ──
    var nbrA = 0.0;
    var nbrB = 0.0;
    let r = i32(radius);
    
    for (var dy: i32 = -r; dy <= r; dy = dy + 1) {
        for (var dx: i32 = -r; dx <= r; dx = dx + 1) {
            let d = sqrt(f32(dx * dx + dy * dy));
            if (d > radius) {
                continue;
            }
            
            // One exact load feeds both species (was two samples per tap)
            let tap = loadState(coord + vec2<i32>(dx, dy), dims);
            let k = kernel(d, radius);
            neighborhood += tap.x * k;
            kernelSum += k;
            // Species B shares the sample tap, weighted by its own kernel
            let kB = kernel(d, radiusB);
            neighborhoodB += tap.y * kB;
            kernelSumB += kB;
            // edges 0.2, corners 0.05, centre 0 (centre subtracted below)
            let man = abs(dx) + abs(dy);
            let w9 = select(0.0, select(0.05, 0.2, man == 1), man >= 1 && abs(dx) <= 1 && abs(dy) <= 1);
            nbrA += tap.x * w9;
            nbrB += tap.y * w9;
        }
    }
    
    // Normalize
    if (kernelSum > 0.0) {
        neighborhood /= kernelSum;
    }
    if (kernelSumB > 0.0) {
        neighborhoodB /= kernelSumB;
    }
    
    // ── Growth + cross-feeding competition ──────────────────────────────────
    let g = growth(neighborhood, growthCenterA, growthWidth);
    let gB = growth(neighborhoodB, growthCenterB, growthWidthB);
    
    // Update species A (primary state layout preserved verbatim)
    // Idea 1: diffusion lets fronts creep and keeps blobs from freezing into saturated stamps
    let lapA = nbrA - currentState;
    let lapB = nbrB - currentStateB;
    var newState = currentState + dt * g + 0.5 * lapA;
    newState = clamp(newState, 0.0, 1.0);
    
    // Species B update: dense A colonies inhibit B (resource competition),
    // while sparse A edges slightly fertilize B (mutualist fringe).
    let inhibition = smoothStep(0.45, 0.85, currentState) * 0.35;
    let fertilize = smoothStep(0.05, 0.25, currentState)
                  * (1.0 - smoothStep(0.25, 0.5, currentState)) * 0.15;
    var newStateB = currentStateB + dtB * (gB - inhibition + fertilize) + 0.5 * lapB;
    newStateB = clamp(newStateB, 0.0, 1.0);
    
    // Dense B also grazes A back a touch, so fronts visibly swap territory
    newState = clamp(newState - smoothStep(0.5, 0.9, currentStateB) * dt * 0.25, 0.0, 1.0);
    
    // ── Mouse-DOWN spawn (fixed gate: was stuck-on ripple count) ────────────
    let toMouse = length(uv - mousePos);
    if (toMouse < 0.05 && mouseDown > 0.5) {
        // Soft radial species-A brush instead of a hard overwrite
        let brush = 1.0 - smoothStep(0.0, 0.05, toMouse);
        newState = clamp(newState + brush * 0.5, 0.0, 1.0);
    }
    
    // ── Click seed bombs: live ripples drop species-B blobs ─────────────────
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age < 0.0 || age > 3.0) {
            continue;
        }
        let blobDist = length(uv - ripple.xy);
        let blobRadius = 0.03 + age * 0.015;             // bomb swells as it decays
        if (blobDist < blobRadius) {
            let decay = 1.0 - age / 3.0;                 // fades with ripple age
            let blob = (1.0 - smoothStep(0.0, blobRadius, blobDist)) * decay;
            newStateB = clamp(newStateB + blob * 0.8, 0.0, 1.0);
        }
    }
    
    // ── Spore rain (mids boost): soft noisy blobs where the neighbourhood is empty ───────
    // HEAD dropped single pixels; growth(≈0) = -1 killed every one, so nothing ever ignited.
    let px = vec2<f32>(coord);
    for (var sp = 0; sp < 2; sp = sp + 1) {
        let isB = sp == 1;
        let sR = select(radius, radiusB, isB);
        let cell = 2.6 * sR;
        let cxy = floor(px / cell) + select(0.0, 17.0, isB);
        let phase = time / 3.0 + rand(cxy + vec2<f32>(5.0, 2.0));
        let ep = floor(phase);
        let thr = select(0.3, 0.6, isB) - 0.15 * audioMids;
        let fire = rand(cxy + vec2<f32>(ep * 13.1, -ep * 7.7)) > thr && fract(phase) < 0.05;
        let jit = vec2<f32>(rand(cxy + vec2<f32>(ep, 3.0)), rand(cxy + vec2<f32>(1.0, ep)));
        let sd = length(px - (cxy - select(0.0, 17.0, isB) + 0.25 + 0.5 * jit) * cell) / (cell * 0.32);
        let kf = 1.6 / sR;
        let sn = 0.5 + 0.25 * (sin(px.x * kf * 1.3 + ep * 1.7 + sin(px.y * kf * 0.9))
                             + sin(px.y * kf * 1.1 - ep * 2.3 + sin(px.x * kf * 0.7)));
        let blob = clamp(sn * (1.0 - sd * sd) * 1.2, 0.0, 1.0);
        let empty = select(neighborhood, neighborhoodB, isB) < 0.03;
        let put = select(0.0, blob, fire && sd < 1.0 && empty);
        newState = select(newState, max(newState, put), !isB);
        newStateB = select(max(newStateB, put), newStateB, !isB);
    }
    
    // ── Color mapping: two species blended by local dominance ───────────────
    var color = leniaColor(newState, time);
    let colorB = leniaColorB(newStateB, time);
    let dominance = smoothStep(0.15, 0.6, newStateB) * (1.0 - smoothStep(0.3, 0.8, newState));
    color = mix(color, colorB, clamp(dominance + newStateB * 0.5, 0.0, 1.0));
    
    // Add glow around living cells (A warm, B cool)
    let glow = smoothStep(0.2, 0.8, newState) * 0.5;
    let glowB = smoothStep(0.2, 0.8, newStateB) * 0.5;
    color += vec3<f32>(0.4, 0.8, 0.3) * glow;
    color += vec3<f32>(0.5, 0.3, 0.9) * glowB;
    
    // ── Idea 2: metabolic rim — g (growth) is already computed and was thrown away after the
    // update. Advancing fronts (g > 0 on living cells) glow; starving cores (g < 0) dim.
    let live = smoothStep(0.05, 0.3, max(newState, newStateB));
    let gm = select(g, gB, newStateB > newState);
    color += vec3<f32>(0.25, 0.9, 0.45) * smoothStep(0.0, 0.6, gm) * live * 0.35;
    color *= 1.0 - 0.3 * smoothStep(0.0, 0.8, -gm) * live;

    // Tone map (display only - sim state below is never tonemapped)
    color = acesToneMap(max(color, vec3<f32>(0.0)));
    let coverage = max(newState, newStateB);
    
    textureStore(writeTexture, coord, vec4<f32>(color, mix(0.55, 1.0, coverage)));
    textureStore(writeDepthTexture, coord, vec4<f32>(max(newState, newStateB), 0.0, 0.0, 1.0));
    
    // Store state for next frame: A in .r (contract), B in .g, MARK in .b (sentinel)
    textureStore(dataTextureA, coord, vec4<f32>(newState, newStateB, MARK, 1.0));
}
