// ═══════════════════════════════════════════════════════════════════
//  Ethereal Quantum-Holographic Fractal-Coral
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10
//  Ideas: polyp mouth pits on the branches (fold space); zooxanthellae symbiont pulse
//         on-branch from exact C; 2nd pass: polyp tentacle tufts at fold-trap tips
//         swaying with mids; bass spawning bursts released from the tips into the glow
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: params mapped from UI

const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.001;
// Depth convention: near = high, miss = 0; scene spans ~12 units from camera.
const DEPTH_FAR: f32 = 12.0;

// Per-invocation side outputs of map() (last evaluation wins): distance to
// the nearest tentacle tuft and to the nearest spawning particle.
var<private> gTuft: f32 = 1e3;
var<private> gBurst: f32 = 1e3;
var<private> gHitDist: f32 = 1e3;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D Cellular/Voronoi Noise approximation
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.6))
    );
    return fract(sin(q) * 43758.5453) * 2.0 - 1.0;
}

fn voronoi(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    var res = 8.0;
    for (var k = -1; k <= 1; k++) {
        for (var j = -1; j <= 1; j++) {
            for (var i = -1; i <= 1; i++) {
                let b = vec3<f32>(f32(i), f32(j), f32(k));
                let r = b - f + hash3(p + b) * 0.5 + 0.5;
                let d = dot(r, r);
                res = min(res, d);
            }
        }
    }
    return sqrt(res);
}

// smooth min
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

// parameters mapped from UI
// zoom_params.x = Fractal Density (1.0 to 8.0)
// zoom_params.y = Holographic Frequency (1.0 to 20.0)
// zoom_params.z = Bio-Luminescence Intensity (0.0 to 3.0)
// zoom_params.w = Audio Pulse Propagation (0.5 to 5.0)

fn map(p_in: vec3<f32>) -> f32 {
    var p = p_in;
    let t = u.config.x * 0.2;

    // Audio input (low frequency energy)
    let audioEnergy = plasmaBuffer[0].x * u.zoom_params.w;

    // Mouse attraction
    let mouse = u.zoom_config.yz * 2.0 - 1.0; // center mapped
    // The camera basis (cu ≈ -x, rd.y = +uv.y with rows top-down) shows the
    // world rotated 180°, so both axes are negated to pull toward the pointer.
    p = p - vec3<f32>(-mouse.x * 2.0, mouse.y * 2.0, 0.0) * exp(-length(p) * 0.5);

    // KIFS setup
    var d = 1000.0;
    var scale = 1.0;
    // Keep iteration math in f32 until the final cast (naga rejects f32 + i32).
    let iterations = i32(clamp(floor(u.zoom_params.x) + floor(audioEnergy * 2.0), 1.0, 10.0));

    let fold = vec3<f32>(1.5, 1.2, 1.5) + vec3<f32>(sin(t), cos(t * 0.8), sin(t * 1.2)) * 0.1;
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let tt = u.config.x;

    // Bass spawning bursts: hashed 1.4 s cycles, stateless. Each cycle picks
    // fresh launch directions; particles travel outward from the tuft tips
    // and are only lit while bass is up.
    let burstRate = 0.7;
    let burstPhase = fract(tt * burstRate);
    let burstEpoch = floor(tt * burstRate);

    var tuft = 1e3;
    var burst = 1e3;

    for (var i = 0; i < iterations; i++) {
        p = abs(p);
        p = p - fold;

        let rotMatrix1 = rot(t * 0.3 + f32(i) * 0.2);
        let rotMatrix2 = rot(t * 0.5 - f32(i) * 0.3);

        p = vec3<f32>(rotMatrix1 * p.xy, p.z);
        p = vec3<f32>(p.x, rotMatrix2 * p.yz);

        // Idea: polyp tentacle tufts — a small cluster of swaying spheres at
        // the fold-trap tip (the folded-space point the branches reach toward),
        // replicated by the KIFS symmetry onto every branch end. Mids widen
        // the sway.
        let fi = f32(i);
        let sway = vec3<f32>(sin(tt * 1.7 + fi * 1.3), 0.0, cos(tt * 1.3 + fi * 2.1)) * (0.06 + mids * 0.14);
        let tip = vec3<f32>(0.0, 0.62, 0.0) + sway;
        for (var k = 0; k < 3; k++) {
            let ang = f32(k) * 2.094 + tt * 0.4;
            let lean = vec3<f32>(cos(ang), 0.0, sin(ang)) * 0.11 + vec3<f32>(0.0, 0.08, 0.0);
            let tentacleTip = tip + lean + sway * 0.6;
            // Tapered tentacle (segment tip..tentacleTip) capped by a bead.
            let pa = p - tip;
            let ba = tentacleTip - tip;
            let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
            let stalk = length(pa - ba * h) - mix(0.035, 0.015, h);
            let bead = length(p - tentacleTip) - 0.04;
            tuft = min(tuft, min(stalk, bead) / scale);
        }

        // Idea: bass spawning bursts (particles leave the tip). The glow is
        // gated by smoothstep(0.2, 0.6, bass), so skip the loop below that.
        for (var k = 0; k < select(0, 3, bass > 0.2); k++) {
            let hk = hash3(vec3<f32>(burstEpoch, f32(k) * 7.3, fi * 3.1));
            let dir = normalize(hk + vec3<f32>(0.0, 1.2, 0.0));
            let pos = tip + dir * (0.1 + burstPhase * 0.9);
            burst = min(burst, (length(p - pos) - 0.02) / scale);
        }

        let r2 = dot(p, p);
        let s = max(0.5, 2.0 / clamp(r2, 0.1, 1.0));
        p = p * s;
        scale = scale * s;
    }

    // Base geometry is a sphere/cylinder combination in folded space
    let baseGeom = (length(p) - 1.2) / scale;

    // Combine with voronoi noise to make it organic coral-like
    let noiseFreq = u.zoom_params.y;
    let organicNoise = voronoi(p_in * noiseFreq + t) * 0.1;

    d = smin(baseGeom, baseGeom + organicNoise, 0.2);

    // Polyp mouth pits, carved in fold space so they sit on the branches:
    // a lattice of small spheres in the final folded frame (where the branch
    // surface is the |p| = 1.2 shell), scaled back to world units.
    let pitCell = fract(p * 2.5) - 0.5;
    let pitSDF = (length(pitCell) / 2.5 - 0.07) / scale;
    d = max(d, -pitSDF);

    // Tufts join the branch tips; side outputs for shading/glow.
    d = smin(d, tuft, 0.02);
    gTuft = tuft;
    gBurst = burst;

    return d;
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

// Holographic color palette generator
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn render(ro: vec3<f32>, rd: vec3<f32>) -> vec4<f32> {
    var p = ro;
    var tDist = 0.0;
    var d = 0.0;
    var col = vec3<f32>(0.0);

    var glow = 0.0;
    let maxGlow = u.zoom_params.z;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audioEnergy = bass;
    var tipGlow = 0.0;
    var burstGlow = 0.0;

    for (var i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * tDist;
        d = map(p);

        if (d < SURF_DIST) {
            break;
        }
        if (tDist > MAX_DIST) {
            break;
        }

        tDist = tDist + d;
        // Accumulate volumetric glow based on proximity and audio
        glow = glow + (0.01 / (0.01 + abs(d))) * (0.1 + audioEnergy * 0.5);
        // Glowing tentacle tips and bass spawning particles feed the same
        // scattering accumulator.
        tipGlow = tipGlow + 0.004 / (0.004 + max(gTuft, 0.0)) * (0.05 + mids * 0.1);
        burstGlow = burstGlow + 0.003 / (0.003 + max(gBurst, 0.0)) * smoothstep(0.2, 0.6, bass);
    }

    if (tDist < MAX_DIST) {
        let n = calcNormal(p);
        let viewDir = -rd;

        // Fresnel for holographic effect
        let fresnel = pow(1.0 - max(dot(n, viewDir), 0.0), 2.0);

        // Base color from position and normal
        let holoFreq = u.zoom_params.y * 0.1;
        let c1 = palette(length(p) * holoFreq + u.config.x * 0.5,
                         vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67));

        // Chromatic interference
        let interference = sin(dot(n, vec3<f32>(1.0)) * 10.0 + u.config.x) * 0.5 + 0.5;

        col = mix(c1, vec3<f32>(1.0, 0.8 + mids * 0.2, 1.0), fresnel * interference);

        // Audio reactive pulsing from the interior
        col = col + vec3<f32>(0.2, 0.8, 1.0) * audioEnergy * maxGlow * fresnel;

        // Tentacle tuft surface: pale polyp flesh with glowing beads.
        let onTuft = 1.0 - smoothstep(0.0, 0.01, gTuft - d);
        col = mix(col, vec3<f32>(1.0, 0.75, 0.9) * (0.6 + 0.6 * maxGlow), onTuft * 0.7);
    }
    // Volumetric tip glow (pink-white) and spawning particles (warm gold).
    col = col + vec3<f32>(1.0, 0.55, 0.85) * min(tipGlow, 6.0) * 0.05 * maxGlow;
    col = col + vec3<f32>(1.0, 0.85, 0.45) * min(burstGlow, 8.0) * 0.08 * (0.5 + maxGlow);

    // Add volumetric glow (scattering)
    col = col + vec3<f32>(0.1 + treble * 0.15, 0.5, 0.8) * glow * 0.05 * maxGlow;

    // Zooxanthellae symbiont glow in branch interior (volume channel)
    let symInterior = glow * (0.14 + audioEnergy * 0.42);
    col += vec3<f32>(0.22, 0.82, 0.36) * symInterior * maxGlow * 0.09;

    // Background fog / attenuation
    col = mix(col, vec3<f32>(0.01, 0.02, 0.05), 1.0 - exp(-0.02 * tDist));

    let hitMask = select(0.0, 1.0, tDist < MAX_DIST);
    gHitDist = tDist;
    return vec4<f32>(max(col, vec3<f32>(0.0)), hitMask);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));

    if (fragCoord.x >= res.x || fragCoord.y >= res.y) {
        return;
    }

    let uv = ((fragCoord + 0.5) * 2.0 - res) / min(res.x, res.y);

    // Camera setup
    let camTime = u.config.x * 0.1;
    let ro = vec3<f32>(sin(camTime) * 3.0, cos(camTime) * 2.0, -5.0 + sin(camTime * 0.5));
    // `target` is reserved in WGSL; camera look-at point
    let look_at = vec3<f32>(0.0, 0.0, 0.0);

    let cw = normalize(look_at - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = normalize(cross(cu, cw));

    let rd = normalize(uv.x * cu + uv.y * cv + 1.5 * cw);

    let rendered = render(ro, rd);
    let coord = vec2<i32>(id.xy);
    let previous = textureLoad(dataTextureC, coord, 0);
    var rawColor = rendered.rgb;

    // Zooxanthellae symbiont pulse, on-branch only (coverage mask): a green
    // breathing pulse whose memory is the exact-C green channel at low gain
    // (display RGB never re-enters the HDR path with gain >= 1).
    let bass = plasmaBuffer[0].x;
    let maxGlow = u.zoom_params.z;
    let coverage = rendered.a;
    let breath = 0.5 + 0.5 * sin(u.config.x * 1.6 - gHitDist * 2.5);
    let symMemory = clamp(previous.g, 0.0, 1.0) * 0.25;
    let symPulse = vec3<f32>(0.25, 0.85, 0.32) * (0.12 + bass * 0.24 + symMemory) * (0.4 + 0.6 * breath);
    rawColor += symPulse * coverage * maxGlow * 0.32;

    let rippleCount = min(i32(u.config.y), 50);
    for (var i = 0; i < rippleCount; i++) {
        let ripple = u.ripples[i];
        let age = u.config.x - ripple.z;
        if (age > 0.0 && age < 2.5) {
            let radius = age * (0.25 + u.zoom_params.w * 0.08);
            // ripple.w is always 0 (padding) — age alone fades the ring.
            let ring = exp(-abs(distance((fragCoord + 0.5) / res, ripple.xy) - radius) * 90.0) * exp(-age * 1.6);
            rawColor += vec3<f32>(0.15, 0.55, 1.0) * ring;
        }
    }

    let mapped = acesToneMap(max(rawColor, vec3<f32>(0.0)) * 1.25);
    let col = mix(mapped, previous.rgb, 0.08);
    // Semantic alpha: branch coverage, with a short exact-C persistence trail.
    let alpha = clamp(max(coverage, previous.a * 0.9), 0.0, 1.0);
    let packed = vec4<f32>(col, alpha);
    // Near = high, miss = 0 (catalog convention).
    let finalDepth = select(0.0, clamp(1.0 - gHitDist / DEPTH_FAR, 0.0, 1.0), coverage > 0.5);

    textureStore(writeTexture, coord, packed);
    textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 1.0));
    textureStore(dataTextureA, coord, packed);
}
