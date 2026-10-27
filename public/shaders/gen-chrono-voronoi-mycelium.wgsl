// ═══════════════════════════════════════════════════════════════════
//  Chrono-Voronoi Mycelium
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba, click-reactive
//  Complexity: High
//  Upgraded: 2026-10-19
//  Ideas: clamp connections across generation borders; apothecia cups on high-gen seeds;
//         cyclic birth-death regeneration per cell (colonies now die and regrow, not
//         settle to a static age); green rebirth burst when a cell starts a new cycle;
//         golden-angle leading hyphae fanning from each inoculation seed to the barrage
//         border, Y-branching, with a Spitzenkörper tip on the growth front (§12.2E);
//         fairy-ring senescence — the colony centre autolyses behind the front (§12.1 t2)
//  A packing: HDR display RGBA (pre-ACES in A, alpha 0.86 dark substrate → 1 on hyphae;
//             ACES on writeTexture)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=GrowthRate, y=Generations, z=Decay, w=Glow

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn hash31(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// FBM noise for organic texture
fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
    var v = 0.0;
    var amp = 0.5;
    var pos = p;
    for (var i = 0; i < octaves; i++) {
        v += amp * (sin(pos.x + sin(pos.y)) * 0.5 + 0.5);
        pos = pos * 2.1 + vec2<f32>(1.7, 0.3);
        amp *= 0.5;
    }
    return v;
}

var<private> g_toSeed: vec2<f32>;   // nearest seed minus pixel, cell units (set by voronoiLayer)

// Voronoi with temporal generation layers.
// .z is the true distance to the colony border (bisector of the two nearest seeds);
// the old squared-distance difference widened into multi-cell beams whenever two
// drifting seeds nearly coincided.
fn voronoiLayer(uv: vec2<f32>, scale: f32, timeLayer: f32, growthRate: f32) -> vec4<f32> {
    let s = uv * scale;
    let n = floor(s);
    let f = fract(s);

    var minDist1 = 9.0;
    var minDist2 = 9.0;
    var minCell = vec2<f32>(0.0);
    var minSeed = vec2<f32>(0.0);
    var o1 = vec2<f32>(0.0);
    var o2 = vec2<f32>(1.0, 0.0);

    for (var j: i32 = -2; j <= 2; j++) {
        for (var i: i32 = -2; i <= 2; i++) {
            let cell = n + vec2<f32>(f32(i), f32(j));
            let seed = hash22(cell);
            // Temporal animation: seeds drift over generations
            let phase = seed * TAU;
            let drift = vec2<f32>(
                sin(phase.x + timeLayer * growthRate * 0.3) * 0.4,
                cos(phase.y + timeLayer * growthRate * 0.25) * 0.4
            );
            let o = vec2<f32>(f32(i), f32(j)) + seed + drift - f;
            let d = dot(o, o);
            if (d < minDist1) {
                minDist2 = minDist1;
                o2 = o1;
                minDist1 = d;
                o1 = o;
                minCell = cell;
                minSeed = seed;
            } else if (d < minDist2) {
                minDist2 = d;
                o2 = o;
            }
        }
    }
    g_toSeed = o1;
    let sep = o2 - o1;
    let border = dot(0.5 * (o1 + o2), sep / max(length(sep), 1e-4));
    return vec4<f32>(sqrt(minDist1), sqrt(minDist2), border, hash21(minCell));
}

struct Branch {
    intensity: f32,   // barrage-border hypha
    border: f32,      // distance to the border (for clamp connections)
    rebirth: f32,     // Idea 4 — bright at the instant a cell starts a new cycle
    hyphae: f32,      // Idea 5 — living leading hyphae
    spitz: f32,       // Idea 5 — Spitzenkörper tips on the growth front
    senescent: f32,   // Idea 6 — autolysed hyphae behind the front
}

// Mycelium branch SDF approximation using distance transform.
fn myceliumBranch(uv: vec2<f32>, t: f32, generation: f32, bass: f32) -> Branch {
    let scale = 4.0 + generation * 2.0;
    let v = voronoiLayer(uv, scale, t, 1.0 + bass * 0.5);

    let border = v.z;
    let cell_id = v.w;

    // Idea 3 — cyclic regeneration: the old birth curve only ever aged toward
    // zero and stayed there, so "chrono" meant nothing after the first cycle.
    // Wrap the age clock per cell so colonies genuinely die and regrow.
    let cyclePeriod = 5.0 + generation * 1.5;
    let cycleRaw = t * 0.2 + cell_id * 3.0;
    let cycleT = cycleRaw - floor(cycleRaw / cyclePeriod) * cyclePeriod;
    let alive = smoothstep(0.0, 0.5, cycleT);
    let aged = 1.0 - smoothstep(cyclePeriod - 1.2, cyclePeriod - 0.2, cycleT);
    let lifeState = alive * aged;
    let rebirthFlash = exp(-pow(cycleT / 0.15, 2.0));

    let branchWidth = 0.03 + bass * 0.012;
    let branchIntensity = smoothstep(branchWidth, 0.0, border) * lifeState;

    // ── Idea 5: golden-angle leading hyphae ─────────────────────────────
    // Each Voronoi seed is an inoculation point; its colony extends radially as
    // leading hyphae spaced by the golden angle (no two ever align), each forking
    // once into a sister hypha, until they hit the barrage border where the
    // neighbouring colony stops them. The tip on the advancing front (the
    // Spitzenkörper) is the brightest point of a growing hypha.
    let q = -g_toSeed;
    let r = length(q);
    let ang = atan2(q.y, q.x);
    let frontR = 1.1 * clamp(cycleT / (cyclePeriod * 0.55), 0.0, 1.0);
    let inFront = smoothstep(frontR, frontR - 0.02, r);
    // ── Idea 6: fairy-ring senescence ───────────────────────────────────
    // A segment at radius r grew when the front passed it; once it is older than
    // ~40% of the cycle it autolyses, so the colony hollows into a living ring
    // that keeps pushing into the barrage while its centre browns out.
    let segAge = cycleT - r / 1.1 * cyclePeriod * 0.55;
    let living = 1.0 - smoothstep(cyclePeriod * 0.25, cyclePeriod * 0.45, segAge);
    var hyph = 0.0;
    var spitz = 0.0;
    let base = cell_id * TAU;
    for (var i = 0; i < 9; i++) {
        let fi = f32(i);
        let hh = hash21(vec2<f32>(cell_id * 37.0, fi));
        let bend = (hh - 0.5) * 1.4;
        let th = base + fi * 2.39996323 + bend * r;
        var dA = ang - th;
        dA = dA - TAU * round(dA / TAU);
        let perp = abs(r * sin(dA));
        let fwd = step(0.0, cos(dA));
        let w = 0.011 + bass * 0.004;
        hyph = max(hyph, smoothstep(w, w * 0.25, perp) * fwd);
        // sister hypha forks off at rb and diverges by ±0.5 rad
        let rb = 0.18 + 0.3 * fract(hh * 7.31);
        let thB = base + fi * 2.39996323 + bend * rb;
        let eB = vec2<f32>(cos(thB), sin(thB));
        let sB = select(-0.4794255, 0.4794255, fract(hh * 13.7) > 0.5);   // sin(±0.5)
        let dB = vec2<f32>(eB.x * 0.8775826 - eB.y * sB, eB.y * 0.8775826 + eB.x * sB);
        let qB = q - rb * eB;
        let alongB = dot(qB, dB);
        let perpB = abs(qB.x * dB.y - qB.y * dB.x);
        hyph = max(hyph, smoothstep(w * 0.8, w * 0.2, perpB) * step(0.0, alongB));
        // Spitzenkörper on the leading tip at the front radius
        let dAF = dA - bend * (frontR - r);
        let td2 = max(r * r + frontR * frontR - 2.0 * r * frontR * cos(dAF), 0.0);
        spitz = max(spitz, exp(-td2 * 1500.0));
    }
    let growing = 1.0 - smoothstep(0.92, 1.0, frontR / 1.1);
    let hyphTotal = hyph * inFront * alive;
    return Branch(branchIntensity, border, rebirthFlash,
                  hyphTotal * living * aged, spitz * growing * alive,
                  hyphTotal * (1.0 - living));
}

// Glowing tip effect at Voronoi seed points
// (v = voronoiLayer(uv, 4 + 2·gen, t, 1.0), shared with apotheciaCups)
fn glowingTips(v: vec4<f32>, t: f32, treble: f32) -> f32 {
    let tipRadius = 0.05 + treble * 0.02;
    return smoothstep(tipRadius, 0.0, v.x) * (0.5 + 0.5 * sin(t * 2.0 + v.w * TAU));
}

// Idea 2 — apothecia cups: dark well + bright rim at high-generation seeds (not tip spark)
fn apotheciaCups(v: vec4<f32>, t: f32, genFrac: f32, treble: f32) -> f32 {
    let cupR = 0.075 + treble * 0.018;
    let rim = smoothstep(cupR, cupR * 0.62, v.x) * smoothstep(cupR * 0.12, cupR * 0.42, v.x);
    // Relative to the layer count: the absolute 1.1..2.5 gate never opened at the
    // default two layers, so the cups were dead unless Generations was > 0.67.
    let highGen = smoothstep(0.5, 1.0, genFrac);
    return rim * highGen * (0.55 + 0.45 * sin(t * 1.6 + v.w * TAU));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.zw);
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / res;
    let aspect = res.x / res.y;
    let uvAspect = vec2<f32>(uv.x * aspect, uv.y);

    let t = u.config.x;
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let growthRate  = u.zoom_params.x * 2.0 + 0.5;  // 0.5..2.5
    let generations = u.zoom_params.y * 3.0 + 1.0;   // 1..4
    let decay       = u.zoom_params.z * 0.8 + 0.1;   // 0.1..0.9
    let glowAmt     = u.zoom_params.w * 2.0 + 0.5;   // 0.5..2.5

    let mousePos = vec2<f32>(u.zoom_config.y, u.zoom_config.z) * vec2<f32>(aspect, 1.0);

    // Nutrient gradient around mouse — affects growth locally
    let mouseDist = length(uvAspect - mousePos);
    let nutrient = exp(-mouseDist * mouseDist * 8.0);

    // Clicks launch fast nutrient fronts through the layered colony.
    var clickSurge = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = t - ripple.z;
        if (age >= 0.0 && age < 2.0) {
            let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            let radius = length(delta);
            let front = exp(-abs(radius - age * (0.34 + bass * 0.12)) * 55.0);
            clickSurge = max(clickSurge, front * exp(-age * 1.35));
        }
    }

    // Accumulate multiple temporal generations
    var totalMycelium = 0.0;
    var totalGlow = 0.0;
    var generationColor = vec3<f32>(0.0);
    var clampGlow = 0.0;
    var cupGlow = 0.0;
    var rebirthGlow = 0.0;
    var hyphGlow = 0.0;
    var spitzGlow = 0.0;
    var senGlow = 0.0;
    var prevBorder = -1.0;
    var prevBranch = 0.0;

    let numGen = i32(clamp(generations, 1.0, 4.0));
    for (var g = 0; g < numGen; g++) {
        let gf = f32(g);
        let timeOffset = gf * 1.7 + bass * 0.3;
        let layerTime = t * growthRate + timeOffset;

        let branchRes = myceliumBranch(uvAspect, layerTime, gf, bass);
        let branches = branchRes.intensity;
        let border = branchRes.border;
        let rebirthFlash = branchRes.rebirth;
        let vSeed = voronoiLayer(uvAspect, 4.0 + gf * 2.0, layerTime, 1.0);
        let tips = glowingTips(vSeed, layerTime, treble);
        let genFrac = gf / max(f32(numGen) - 1.0, 1.0);
        let cups = apotheciaCups(vSeed, layerTime, genFrac, treble);

        let genStrength = pow(decay, gf) * (1.0 + nutrient * 0.5 + clickSurge * 0.9);
        totalMycelium += branches * genStrength;
        totalGlow += tips * genStrength * glowAmt;
        cupGlow += cups * genStrength;
        rebirthGlow += rebirthFlash * genStrength;
        hyphGlow += branchRes.hyphae * genStrength;
        spitzGlow += branchRes.spitz * genStrength;
        senGlow += branchRes.senescent * genStrength;

        // Idea 1 — clamp connections where two generation borders coincide
        if (g > 0) {
            let coincide = 1.0 - smoothstep(0.0, 0.025, abs(border - prevBorder));
            clampGlow += coincide * min(branches, prevBranch) * genStrength;
        }
        prevBorder = border;
        prevBranch = branches;

        let ageHue = gf / max(f32(numGen) - 1.0, 1.0);
        let genHue = mix(0.5, 0.08, ageHue);
        let genCol = vec3<f32>(
            0.5 + 0.5 * cos(genHue * TAU),
            0.5 + 0.5 * cos(genHue * TAU + 2.094),
            0.5 + 0.5 * cos(genHue * TAU + 4.189)
        );
        generationColor += genCol * (branches + tips * 0.5) * genStrength;
    }

    // Background: deep organic dark
    var color = vec3<f32>(0.02, 0.04, 0.06);

    // Mycelium network glow
    let networkIntensity = clamp(totalMycelium, 0.0, 1.0);
    let tipIntensity = clamp(totalGlow, 0.0, 1.0);

    // Normalize generation color
    let colorMag = length(generationColor) + 0.001;
    let normColor = generationColor / colorMag;

    // Translucent network layer
    color = mix(color, normColor * (0.4 + mids * 0.3), networkIntensity * 0.7);

    // Bright glowing tips
    let tipColor = vec3<f32>(0.8 + treble * 0.2, 0.95, 0.6 + mids * 0.3);
    color += tipColor * tipIntensity * 1.5;
    color += vec3<f32>(0.95, 0.75, 0.35) * clampGlow * 1.35;
    // Apothecia: warm rim, darker cup well
    color += vec3<f32>(0.85, 0.35, 0.22) * cupGlow * 1.6;
    color -= vec3<f32>(0.12, 0.18, 0.10) * cupGlow * 0.45;
    // Idea 4 — rebirth burst: a green spark distinct from the warm clamp/apothecia
    // hues, marking the instant a cell re-enters its growth cycle.
    color += vec3<f32>(0.55, 0.95, 0.65) * rebirthGlow * 1.4;
    // Idea 5/6 — cream-white living hyphae over browned autolysed ones, gold
    // Spitzenkörper tips on the advancing front (bass feeds the tips).
    let hyphI = clamp(hyphGlow, 0.0, 1.0);
    let senI = clamp(senGlow, 0.0, 1.0);
    color = mix(color, vec3<f32>(0.30, 0.19, 0.11), senI * 0.55);
    color = mix(color, vec3<f32>(0.86, 0.84, 0.72) * (0.55 + mids * 0.3), hyphI * 0.62);
    color += vec3<f32>(1.25, 0.95, 0.45) * clamp(spitzGlow, 0.0, 1.5) * (0.9 + bass * 0.8) * glowAmt * 0.6;

    // Smooth traveling spores replace the old frame-hash sparkle. The long
    // vertical footprint reads as speed without temporal strobing.
    let sporeCell = floor(uvAspect * vec2<f32>(34.0, 22.0));
    let sporeSeed = hash21(sporeCell);
    let sporeUv = fract(uvAspect * vec2<f32>(34.0, 22.0) +
                        vec2<f32>(sporeSeed, t * (0.45 + treble * 0.55) + sporeSeed)) - 0.5;
    let spore = exp(-sporeUv.x * sporeUv.x * 220.0 - sporeUv.y * sporeUv.y * 34.0) *
                smoothstep(0.82, 1.0, sporeSeed) * (0.25 + treble * 0.9);
    color += vec3<f32>(1.1, 0.82, 0.38) * spore;

    // Vignette
    let vignette = 1.0 - dot(uv - 0.5, uv - 0.5) * 1.5;
    color *= max(vignette, 0.0);

    // Velocity-advected, HDR-bounded history turns the advancing network into
    // coherent fungal light trails instead of a static overlay.
    let flowVelocity = vec2<f32>(
        cos(t * 0.71 + uvAspect.y * 5.0),
        sin(t * 0.63 - uvAspect.x * 4.0)
    ) * (1.2 + growthRate * 0.8 + bass * 1.8);
    let maxCoord = vec2<i32>(max(i32(res.x) - 1, 0), max(i32(res.y) - 1, 0));
    let historyCoord = clamp(vec2<i32>(global_id.xy) - vec2<i32>(flowVelocity), vec2<i32>(0), maxCoord);
    let history = textureLoad(dataTextureC, historyCoord, 0).rgb;
    let historyDecay = clamp(0.76 + decay * 0.12, 0.76, 0.88);
    let trailMask = clamp(networkIntensity * 0.45 + tipIntensity * 0.7 + clickSurge, 0.0, 1.0);
    let hdrColor = clamp(color + history * historyDecay * (0.24 + trailMask * 0.36), vec3<f32>(0.0), vec3<f32>(5.0));
    // Dark substrate is opaque enough not to wash out over a light page; hyphae
    // and glow push it to full coverage.
    let alpha = clamp(0.86 + networkIntensity * 0.1 + hyphI * 0.1 + tipIntensity * 0.12 + spore * 0.1 + clickSurge * 0.1 + clampGlow * 0.08 + cupGlow * 0.08 + rebirthGlow * 0.06, 0.86, 1.0);
    let depth = clamp(networkIntensity * 0.48 + hyphI * 0.3 + tipIntensity * 0.38 + clickSurge * 0.24 + clampGlow * 0.15 + rebirthGlow * 0.1, 0.0, 1.0);
    let coords = vec2<i32>(global_id.xy);
    textureStore(dataTextureA, coords, vec4<f32>(hdrColor, alpha));
    textureStore(writeTexture, coords, vec4<f32>(acesToneMap(hdrColor * 1.15), alpha));
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
