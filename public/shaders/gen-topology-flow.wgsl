// ═══════════════════════════════════════════════════════════════════
//  Topology Flow - Topological surface flow with Morse theory
//  Category: generative
//  Features: procedural, gradient flow, critical point detection
//  Created: 2026-03-22
//  By: Agent 4A
//  Upgrade (Batch 36 / Visualist): split-toned relief palette,
//  warm-key/cool-fill relief lighting, HDR flow lines + critical
//  point glow (bloom-ready), valley haze, ACES grade, audio-
//  reactive energy, bounded mouse stir, semantic alpha.
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
  config: vec4<f32>,       // x=time, y=rippleCount, zw=resolution
  zoom_config: vec4<f32>,  // x=time, yz=mouse_uv (0-1, y=0 top), w=mouse_down
  zoom_params: vec4<f32>,  // x=flow speed, y=complexity, z=particle density, w=trail persistence
  ripples: array<vec4<f32>, 50>,
};

// ── Color science helpers ─────────────────────────────────────────
// ACES filmic approximation (HDR in, display-ready out)
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Value noise
fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

// FBM for height field
fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var pp = p;
    for (var i: i32 = 0; i < octaves; i++) {
        v += a * noise(pp);
        pp = pp * 2.0 + vec2<f32>(100.0);
        a *= 0.5;
    }
    return v;
}

// Height field function
fn heightField(p: vec2<f32>, complexity: f32, t: f32) -> f32 {
    let octaves = i32(mix(2.0, 6.0, complexity));
    var h = fbm(p + t * 0.1, octaves);

    // Add ridge-like features for Morse theory
    let ridge1 = sin(p.x * 3.0 + t * 0.2) * cos(p.y * 2.5);
    let ridge2 = sin((p.x + p.y) * 2.0 - t * 0.15);
    h += ridge1 * 0.2 + ridge2 * 0.15;

    // Add saddle points
    let saddle = (p.x * p.x - p.y * p.y) * 0.5;
    h += saddle * 0.1 * sin(t * 0.1);

    return h;
}

// Calculate gradient for flow direction
fn gradient(p: vec2<f32>, complexity: f32, t: f32) -> vec2<f32> {
    let eps = 0.01;
    let h = heightField(p, complexity, t);
    let hx = heightField(p + vec2<f32>(eps, 0.0), complexity, t);
    let hy = heightField(p + vec2<f32>(0.0, eps), complexity, t);
    return vec2<f32>((hx - h) / eps, (hy - h) / eps);
}

// Detect critical points (where gradient is near zero)
fn detectCritical(grad: vec2<f32>, secondDeriv: f32) -> i32 {
    let gradMag = length(grad);

    if (gradMag < 0.05) {
        // Max, min, or saddle based on second derivative
        if (secondDeriv < -0.1) { return 1; } // Maximum (peak)
        else if (secondDeriv > 0.1) { return 2; } // Minimum (valley)
        else { return 3; } // Saddle point
    }
    return 0; // Not critical
}

// Split-toned relief palette: abyssal indigo valleys, verdant mids,
// ember-gold peaks (cool shadows / warm highlights harmony).
fn heightColor(h: f32) -> vec3<f32> {
    let valley = vec3<f32>(0.06, 0.14, 0.52);
    let mid = vec3<f32>(0.16, 0.50, 0.34);
    let peak = vec3<f32>(0.98, 0.42, 0.12);

    if (h < 0.4) {
        return mix(valley, mid, h / 0.4);
    } else {
        return mix(mid, peak, (h - 0.4) / 0.6);
    }
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let px = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let t = u.config.x;

    // === AUDIO (plasma bands + guarded engine FFT bins 1-8) ===
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    var fftShimmer = 0.0;
    if (arrayLength(&extraBuffer) > 13u) {
        for (var k = 1u; k <= 8u; k = k + 1u) {
            fftShimmer += extraBuffer[5u + k];
        }
        fftShimmer = clamp(fftShimmer * 0.125, 0.0, 1.5);
    }

    // Parameters - safe randomization (all four sliders live)
    let flowSpeed = mix(0.2, 2.0, u.zoom_params.x) * (1.0 + mids * 0.45);
    let complexity = u.zoom_params.y;
    let particleDensity = mix(50.0, 300.0, u.zoom_params.z);
    let trailPersistence = clamp(mix(0.8, 0.98, u.zoom_params.w) + bass * 0.02, 0.0, 0.985);

    // Map UV to flow space
    let aspect = resolution.x / resolution.y;
    let p = uv * vec2<f32>(aspect * 3.0, 3.0) - vec2<f32>(aspect * 1.5, 1.5);

    // Get height and gradient
    var h = heightField(p, complexity, t);
    let grad = gradient(p, complexity, t);

    // Second derivative approximation (Laplacian)
    let eps = 0.02;
    let hL = heightField(p - vec2<f32>(eps, 0.0), complexity, t);
    let hR = heightField(p + vec2<f32>(eps, 0.0), complexity, t);
    let hD = heightField(p - vec2<f32>(0.0, eps), complexity, t);
    let hU = heightField(p + vec2<f32>(0.0, eps), complexity, t);
    let laplacian = (hL + hR + hD + hU - 4.0 * h) / (eps * eps);

    // Detect critical points
    let critical = detectCritical(grad, laplacian);

    // === BOUNDED MOUSE STIR (finite, spatially local bump + lantern glow) ===
    let mDown = select(0.0, 1.0, u.zoom_config.w > 0.5);
    let mp = u.zoom_config.yz * vec2<f32>(aspect * 3.0, 3.0) - vec2<f32>(aspect * 1.5, 1.5);
    let mDist = length(p - mp);
    let stir = exp(-mDist * mDist * 5.0); // gaussian falloff, <= 1
    h += stir * (0.10 + 0.22 * mDown);

    // === RELIEF LIGHTING: warm key + cool fill (two temperatures) ===
    let reliefN = normalize(vec3<f32>(-grad.x * 0.12, 1.0, -grad.y * 0.12));
    let keyDir = normalize(vec3<f32>(0.55, 0.75, 0.35));
    let keyCol = vec3<f32>(1.25, 1.02, 0.78);  // warm afternoon key
    let fillDir = normalize(vec3<f32>(-0.55, 0.45, -0.65));
    let fillCol = vec3<f32>(0.28, 0.48, 0.95); // cool sky fill
    let lighting = keyCol * max(dot(reliefN, keyDir), 0.0) * 0.85
                 + fillCol * max(dot(reliefN, fillDir), 0.0) * 0.45
                 + vec3<f32>(0.22, 0.24, 0.30);

    // Base color from split-toned height palette, shaped by relief light
    var col = heightColor(h) * lighting;

    // Draw flow lines using streamline integration
    var flowAccum = 0.0;

    // Seed particles across the field
    let numParticles = i32(particleDensity);
    for (var i: i32 = 0; i < numParticles; i++) {
        let seed = vec2<f32>(f32(i) * 0.1, f32(i) * 0.07);
        var particlePos = fract(seed + t * flowSpeed * 0.1) * vec2<f32>(aspect * 3.0, 3.0) - vec2<f32>(aspect * 1.5, 1.5);

        // Advect particle backwards to see if it passes through current pixel
        for (var step: i32 = 0; step < 20; step++) {
            let g = gradient(particlePos, complexity, t);
            particlePos = particlePos - normalize(g + vec2<f32>(0.0001, 0.0)) * 0.02;

            let dist = length(particlePos - p);
            if (dist < 0.03) {
                flowAccum += 1.0 - dist / 0.03;
            }
        }
    }

    // === HDR FLOW ENERGY (bloom-ready, bass-charged) ===
    let flowIntensity = flowAccum * 0.12;
    let flowDir = normalize(grad + vec2<f32>(0.0001, 0.0));
    let flowCol = vec3<f32>(0.35 + flowDir.x * 0.4, 0.55 + flowDir.y * 0.4, 1.05) * (1.15 + bass * 0.55);
    col = mix(col, flowCol, min(flowIntensity, 0.6));

    // === CRITICAL POINTS: HDR glow, treble sparkle ===
    var critBoost = 0.0;
    if (critical == 1) {
        // Peak - hot golden beacon (HDR > 1)
        col += vec3<f32>(1.40, 1.05, 0.62) * (0.55 + treble * 0.65);
        critBoost = 0.6;
    } else if (critical == 2) {
        // Valley - deep indigo sink with cool charge
        col = mix(col, vec3<f32>(0.02, 0.10, 0.42), 0.55);
        col += vec3<f32>(0.05, 0.25, 0.90) * treble * 0.4;
        critBoost = 0.4;
    } else if (critical == 3) {
        // Saddle - warm gold hinge
        col += vec3<f32>(1.05, 0.85, 0.25) * (0.40 + treble * 0.5);
        critBoost = 0.5;
    }

    // Contour lines + FFT shimmer trace
    let contour = abs(fract(h * 10.0) - 0.5);
    let contourMask = smoothstep(0.02, 0.0, contour);
    col = mix(col, col * 0.65, contourMask * 0.5);
    col += vec3<f32>(0.90, 0.95, 1.10) * contourMask * fftShimmer * 0.35;

    // Soft local lantern glow around the cursor
    col += vec3<f32>(0.90, 0.75, 0.50) * stir * (0.10 + 0.25 * mDown);

    // === ATMOSPHERE: cool haze pooling in the valleys ===
    let haze = smoothstep(0.45, 0.0, h);
    let hazeCol = vec3<f32>(0.10, 0.16, 0.30) * (0.8 + 0.4 * sin(t * 0.3 + p.x * 0.5));
    col = mix(col, hazeCol, haze * 0.38);

    // Previous frame for trails (HDR history, bounded to 4.0)
    let prev = textureLoad(dataTextureC, px, 0).rgb;
    let colHDR = clamp(col * 0.35 + prev * trailPersistence, vec3<f32>(0.0), vec3<f32>(4.0));

    // Semantic alpha: ink/energy coverage of the field
    let energy = clamp(flowIntensity + critBoost + stir * mDown, 0.0, 1.0);
    let alpha = clamp(0.72 + 0.28 * energy, 0.0, 1.0);

    // Relief depth: peaks near (1.0), valleys far (0.0)
    let depth = clamp(h * 0.5 + 0.5, 0.0, 1.0);

    // Store for feedback (HDR history in A; ACES only for presentation)
    textureStore(dataTextureA, px, vec4<f32>(colHDR, alpha));
    textureStore(writeTexture, px, vec4<f32>(acesToneMap(colHDR * (0.9 + mids * 0.2)), alpha));
    textureStore(writeDepthTexture, px, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
