// ═══════════════════════════════════════════════════════════════════
//  Velocity Bloom - Velocity-sensitive bloom that intensifies on motion
//  Category: lighting-effects
//  Features: temporal, velocity-based, multi-octave bloom, optical-flow
//            streaks, curl-noise advection, diffusion feedback, audio pump
//  Created: 2026-03-22
//  By: Agent 4A
//  Upgraded: 2026-08-05 — Algorithmist b35 (Lucas-Kanade-style flow
//            direction, motion-aligned anamorphic streaks, curl-noise
//            advected trails, Gray-Scott-hint diffusion feedback, audio
//            pump + guarded FFT shimmer, click pulse via extraBuffer
//            spring, generated relief depth, bounds guard)
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
  config: vec4<f32>,       // .x = time (seconds), .y = rippleCount (0-50 active ripples), .zw = resolution (width, height)
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (0–1 canvas: y=0 top), .w = mouse_down (>0.5 = pressed)
  zoom_params: vec4<f32>,  // .xyzw = user params p1…p4 (mapped from UI sliders)
  ripples: array<vec4<f32>, 50>,  // .xy = ripple uv, .z = startTime (seconds), .w = padding (0)
};

const TAU: f32 = 6.28318530718;

fn luma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

// ── 2D value noise + curl (divergence-free flow field) ─────────────
fn hash21(p: vec2<f32>) -> f32 {
    var q = fract(p * vec2<f32>(0.1031, 0.1030));
    q += dot(q, q.yx + vec2<f32>(33.33));
    return fract((q.x + q.y) * q.x);
}

fn vnoise2(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    let a = hash21(i);
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

// Curl of a 2-octave noise potential: incompressible swirl, temporally
// coherent because time only scrolls the potential smoothly.
fn curlNoise(p: vec2<f32>, t: f32) -> vec2<f32> {
    let e = 0.35;
    let q = p + vec2<f32>(t * 0.13, -t * 0.09);
    let nT = vnoise2(q + vec2<f32>(0.0, e)) + 0.5 * vnoise2(q * 2.3 + vec2<f32>(0.0, e * 2.3));
    let nB = vnoise2(q - vec2<f32>(0.0, e)) + 0.5 * vnoise2(q * 2.3 - vec2<f32>(0.0, e * 2.3));
    let nR = vnoise2(q + vec2<f32>(e, 0.0)) + 0.5 * vnoise2(q * 2.3 + vec2<f32>(e * 2.3, 0.0));
    let nL = vnoise2(q - vec2<f32>(e, 0.0)) + 0.5 * vnoise2(q * 2.3 - vec2<f32>(e * 2.3, 0.0));
    return vec2<f32>(nT - nB, nL - nR) / (2.0 * e);
}

// ── Velocity magnitude (original soul, kept) + flow direction ──────
// Returns vec3(velocityMagnitude, flowDir.xy). Flow direction fuses the
// luminance-gradient normal (brightness-constancy motion cue) with the
// ambient curl field so streaks are anisotropic even on still frames.
fn velocityField(uv: vec2<f32>, pixel: vec2<f32>, coord: vec2<i32>, t: f32) -> vec3<f32> {
    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let previous = textureLoad(dataTextureC, coord, 0).rgb;

    let diff = current - previous;
    let lumaDiff = length(diff);

    let right = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(pixel.x, 0.0), 0.0).rgb;
    let left = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(pixel.x, 0.0), 0.0).rgb;
    let up = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, pixel.y), 0.0).rgb;
    let down = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, pixel.y), 0.0).rgb;

    let gx = luma(right) - luma(left);
    let gy = luma(up) - luma(down);
    let gradient = length(vec2<f32>(gx, gy));

    let velocity = lumaDiff + gradient * 0.5;

    // Motion is perpendicular to the luminance gradient; curl adds swirl.
    let gradDir = vec2<f32>(-gy, gx);
    let curl = curlNoise(uv * 6.0, t);
    var flow = gradDir * 0.5 + curl * (0.4 + velocity * 0.6);
    let fl = length(flow);
    flow = select(flow / max(fl, 0.0001), vec2<f32>(1.0, 0.0), fl < 0.0001);
    return vec3<f32>(velocity, flow);
}

// ── Multi-octave bloom sampling (original structure, kept) ─────────
fn multiOctaveBloom(uv: vec2<f32>, baseRadius: f32, velocity: f32) -> vec3<f32> {
    var bloom = vec3<f32>(0.0);
    var totalWeight = 0.0;

    let octaves = 4;
    for (var o: i32 = 0; o < octaves; o++) {
        let fo = f32(o);
        let radius = baseRadius * (1.0 + fo * 0.5) * (1.0 + velocity);
        let weight = 1.0 / (1.0 + fo * 0.5);

        let directions = 8;
        for (var i: i32 = 0; i < directions; i++) {
            let angle = f32(i) * TAU / f32(directions);
            let offset = vec2<f32>(cos(angle), sin(angle)) * radius;
            bloom += textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb * weight;
        }

        totalWeight += weight * f32(directions);
    }

    return bloom / totalWeight;
}

// ── Motion-aligned anamorphic bloom ────────────────────────────────
// Streak axis follows the flow direction instead of a fixed horizontal,
// so fast motion smears along its own path like a true motion bloom.
fn anamorphicBloom(uv: vec2<f32>, radius: f32, velocity: f32, flowDir: vec2<f32>) -> vec3<f32> {
    var bloom = vec3<f32>(0.0);
    let samples = 16;
    let stretch = 1.0 + velocity * 2.0;

    for (var i: i32 = 0; i < samples; i++) {
        let s = (f32(i) / f32(samples - 1) - 0.5) * 2.0;
        let offset = flowDir * s * radius * stretch;
        bloom += textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb;
    }

    return bloom / f32(samples);
}

// ── Velocity-based color tint (branchless smooth gradient) ─────────
fn velocityColor(velocity: f32) -> vec3<f32> {
    let c0 = vec3<f32>(1.0, 1.0, 1.0);
    let c1 = vec3<f32>(0.8, 0.9, 1.0);
    let c2 = vec3<f32>(0.4, 0.7, 1.0);
    let c3 = vec3<f32>(0.9, 0.4, 0.8);
    var tint = mix(c0, c1, smoothstep(0.0, 0.3, velocity));
    tint = mix(tint, c2, smoothstep(0.3, 0.6, velocity));
    tint = mix(tint, c3, smoothstep(0.6, 1.0, velocity));
    return tint;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    // Resolution bounds guard — mandatory
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }

    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let pixel = 1.0 / resolution;
    let t = u.config.x;

    // ── Click-pulse spring in persistent shader state [133..134] ────
    let nExtra = arrayLength(&extraBuffer);
    if (global_id.x == 0u && global_id.y == 0u && nExtra > 135u) {
        let down = u.zoom_config.w;
        let prevDown = extraBuffer[134];
        var energy = extraBuffer[133] * 0.93;
        if (down > 0.5 && prevDown <= 0.5) { energy = 1.0; }
        extraBuffer[133] = energy;
        extraBuffer[134] = down;
    }
    var clickPulse = 0.0;
    if (nExtra > 134u) { clickPulse = extraBuffer[133]; }

    // ── Audio: plasma bands + guarded low FFT bins (1–8 range) ──────
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    var fftLow = 0.0;
    if (nExtra > 13u) {
        fftLow = (extraBuffer[6] + extraBuffer[7] + extraBuffer[8]) / 3.0;
    }

    // ── Parameters - safe randomization (updatedParams order) ───────
    let threshold = mix(0.0, 0.3, u.zoom_params.x);
    let bloomIntensity = mix(0.3, 2.0, u.zoom_params.y) * (1.0 + bass * 0.5);
    let bloomRadius = mix(0.01, 0.05, u.zoom_params.z) * (1.0 + mids * 0.25);
    let decay = mix(0.7, 0.99, u.zoom_params.w);

    // ── Base color ──────────────────────────────────────────────────
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let baseLuma = luma(baseColor);

    // ── Velocity + flow direction ───────────────────────────────────
    let vf = velocityField(uv, pixel, coord, t);
    let velocity = vf.x;
    let flowDir = vf.yz;

    let velocityMask = smoothstep(threshold, threshold + 0.2, velocity);

    // ── Blooms ──────────────────────────────────────────────────────
    let bloom = multiOctaveBloom(uv, bloomRadius, velocity);
    let anamorphic = anamorphicBloom(uv, bloomRadius * 2.0, velocity, flowDir);

    var finalBloom = mix(bloom, anamorphic, velocityMask * 0.5);

    let tint = velocityColor(velocity);
    finalBloom = finalBloom * tint;

    // Treble / FFT-driven micro-shimmer sparkle (multi-scale detail)
    let shimmer = vnoise2(uv * resolution * 0.5 + vec2<f32>(t * 7.0, -t * 5.0));
    finalBloom += finalBloom * shimmer * treble * 0.6 * (1.0 + fftLow);

    // ── Feedback: curl-advected, diffused decay (Gray-Scott hint) ───
    // Advect the previous bloom along the flow field for organic trails.
    let advect = flowDir * bloomRadius * (0.5 + velocity) * 2.0;
    let prevCoord = vec2<i32>(vec2<f32>(coord) - advect * resolution);
    let prevCenter = textureLoad(dataTextureC, clamp(prevCoord, vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1)), 0).rgb;

    // 4-tap Laplacian of the feedback field → diffusion term
    let ipx = vec2<i32>(1, 0);
    let ipy = vec2<i32>(0, 1);
    let minC = vec2<i32>(0);
    let maxC = vec2<i32>(resolution) - vec2<i32>(1);
    let nR = textureLoad(dataTextureC, clamp(prevCoord + ipx, minC, maxC), 0).rgb;
    let nL = textureLoad(dataTextureC, clamp(prevCoord - ipx, minC, maxC), 0).rgb;
    let nU = textureLoad(dataTextureC, clamp(prevCoord + ipy, minC, maxC), 0).rgb;
    let nD = textureLoad(dataTextureC, clamp(prevCoord - ipy, minC, maxC), 0).rgb;
    let laplacian = (nR + nL + nU + nD) * 0.25 - prevCenter;

    // Reaction–diffusion-flavoured accumulation: diffuse, decay, then
    // feed from the thresholded bright-pass of the new frame.
    let diffused = prevCenter + laplacian * 0.6;
    let decayedBloom = diffused * decay;
    let feed = max(finalBloom * bloomIntensity - vec3<f32>(threshold * 0.5), vec3<f32>(0.0));
    let accumulatedBloom = max(feed, decayedBloom * 0.9);

    // ── Composite: base + bloom (original blend scheme, kept) ──────
    let screenBlend = 1.0 - (1.0 - baseColor) * (1.0 - accumulatedBloom);
    let addBlend = baseColor + accumulatedBloom * velocityMask;

    var finalColor = mix(screenBlend, addBlend, velocityMask * 0.5);
    finalColor = finalColor * (1.0 + velocity * 0.3);

    // Click pulse: finite, spatially local white-aether burst at cursor
    if (clickPulse > 0.01) {
        let dM = length((uv - u.zoom_config.yz) * vec2<f32>(resolution.x / resolution.y, 1.0));
        finalColor += vec3<f32>(0.9, 0.95, 1.0) * exp(-dM * dM * 18.0) * clickPulse * 0.8;
    }

    // ── Outputs ─────────────────────────────────────────────────────
    textureStore(dataTextureA, coord, vec4<f32>(accumulatedBloom, 1.0));

    let alpha = clamp(mix(0.8, 1.0, velocityMask) + clickPulse * 0.1, 0.0, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));

    // Generated relief depth: bloom mass rises toward the viewer
    let bloomLuma = luma(accumulatedBloom);
    let depth = clamp(baseLuma * 0.25 + bloomLuma * 0.75, 0.0, 1.0);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
