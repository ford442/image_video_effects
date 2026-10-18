// ═══════════════════════════════════════════════════════════════════
//  Anaglyph 3D — Cinematic Post-Processing Edition
//  Category: visual-effects
//  Features: depth-aware, upgraded-rgba, red-cyan, stereoscopic, audio-reactive,
//            temporal-ghosting, chromatic-separation, mouse-focal-depth,
//            film-grain, chromatic-aberration, vignette, scanlines, crt-barrel,
//            color-grading, anamorphic-streaks, lens-dirt, view-synthesis, ACES
//  Ideas:    1. occlusion-aware view synthesis — each eye forward-warps a strip of source
//               pixels, near pixels win, and disocclusions fill from the background
//            2. filter crosstalk — the glasses leak the other eye's image on high-contrast
//               edges, with a slow binocular-rivalry flicker
//            3. convergence-plane shimmer — a faint neutral contour marks the zero-parallax
//               depth set by the mouse
//  Complexity: High
//  Upgraded: 2026-06-28
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(hash21(p), hash21(p + vec2<f32>(1.0, 0.0)));
}

fn random(gid: vec2<f32>, time: f32) -> f32 {
    return hash21(gid + time * 0.01);
}

// Temporal grain: coherent over time, not static
fn temporalGrain(gid: vec2<f32>, time: f32, treble: f32) -> f32 {
    let t1 = hash21(gid + fract(time * 0.7) * 100.0);
    let t2 = hash21(gid + fract(time * 0.3) * 100.0 + 50.0);
    // Blend two time-offset samples for temporal coherence
    let grain = mix(t1, t2, 0.5) - 0.5;
    return grain * (1.0 + treble * 0.3);
}

// Radial chromatic aberration
fn radialChromatic(uv: vec2<f32>, center: vec2<f32>, strength: f32) -> vec2<f32> {
    let dir = uv - center;
    let r2 = dot(dir, dir);
    return dir * r2 * strength;
}

// Vignette: darkening at corners
fn vignette(uv: vec2<f32>, strength: f32) -> f32 {
    let center = uv - vec2<f32>(0.5);
    let r = length(center) * 1.4142;
    return pow(1.0 - r * strength, 2.0);
}

// Scanlines: horizontal lines with varying intensity
fn scanlines(y: f32, time: f32, intensity: f32) -> f32 {
    let freq = 800.0;
    let scan = sin(y * freq) * 0.5 + 0.5;
    let fade = sin(y * freq * 0.5 + time * 2.0) * 0.3 + 0.7;
    return 1.0 - scan * intensity * fade;
}

// CRT barrel distortion
fn crtDistort(uv: vec2<f32>, k: f32) -> vec2<f32> {
    let center = uv - vec2<f32>(0.5);
    let r2 = dot(center, center);
    let distort = 1.0 + k * r2 + k * k * r2 * r2;
    return center * distort + vec2<f32>(0.5);
}

// Color grading: lift/gamma/gain
fn colorGrade(color: vec3<f32>, lift: vec3<f32>, gamma: vec3<f32>, gain: vec3<f32>) -> vec3<f32> {
    var c = color;
    // Lift (shadows)
    c = c + lift * (1.0 - c);
    // Gamma (midtones)
    c = pow(max(c, vec3<f32>(0.0)), gamma);
    // Gain (highlights)
    c = c * gain;
    return c;
}

// Anamorphic streaks: horizontal light streaks from bright points along the
// row (HEAD centred one streak at x = 0.5, a fixed vertical stripe).
fn anamorphicStreaks(uv: vec2<f32>, strength: f32) -> vec3<f32> {
    var acc = 0.0;
    for (var i = 1; i <= 6; i = i + 1) {
        let o = f32(i) * 0.012;
        let w = exp(-f32(i) * 0.45);
        let lL = dot(textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(o, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
        let lR = dot(textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(o, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
        acc += (smoothstep(0.75, 1.0, lL) + smoothstep(0.75, 1.0, lR)) * w;
    }
    let streak = acc * 0.12 * strength;
    return vec3<f32>(streak * 1.0, streak * 0.9, streak * 0.7);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Idea 1: forward-warp view synthesis for one eye. A source pixel s lands at
// s − eyeSign·shift(d_s). Search a strip of candidates for ones whose landing
// point hits this pixel. Among the hits the nearest (largest depth) wins, so
// the foreground occludes. The winner's own shift is used, which keeps the
// warp continuous rather than tap-quantised. If nothing lands (a disocclusion),
// fill from the farthest candidate, because background is what was hidden.
// Returns the horizontal sample offset for this eye.
fn synthEye(uv: vec2<f32>, eyeSign: f32, sepCurve: f32, focal: f32) -> f32 {
    let maxS = abs(sepCurve) * 2.0 + 1e-4;
    let sigma = maxS / 4.0;
    var bestScore = -1.0;
    var bestLand = 0.0;
    var far = 2.0;
    var farO = 0.0;
    for (var k = -4; k <= 4; k = k + 1) {
        let o = f32(k) / 4.0 * maxS;
        let sUV = clamp(uv + vec2<f32>(o, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
        let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, sUV, 0.0).r;
        let land = eyeSign * sepCurve * (d - focal) * 2.0;
        let err = (o - land) / sigma;
        let hit = exp(-err * err);
        let score = hit * (0.25 + d);
        // hit > 0.55 accepts only taps within ~0.8σ of landing here; looser
        // thresholds let a weak foreground hit drag its shift onto background.
        if (hit > 0.55 && score > bestScore) { bestScore = score; bestLand = land; }
        // Hole fill takes the far candidate's own position (nearest one on ties).
        if (d < far - 1e-3 || (abs(d - far) <= 1e-3 && abs(o) < abs(farO))) { far = d; farO = o; }
    }
    return select(farO, bestLand, bestScore > 0.0);
}

// Lens dirt: subtle dust/grime overlay on bright areas
fn lensDirt(uv: vec2<f32>, time: f32, brightness: f32) -> f32 {
    let dirt1 = hash21(uv * 3.0 + time * 0.01);
    let dirt2 = hash21(uv * 7.0 - time * 0.015);
    let dirt = mix(dirt1, dirt2, 0.5);
    return smoothstep(0.6, 0.9, dirt) * brightness * 0.15;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let separation = u.zoom_params.x * 0.04 * (1.0 + bass * 0.15);
    let depthCurve = u.zoom_params.y;
    let ghostAmount = u.zoom_params.z;
    let grainAmount = u.zoom_params.w;

    // ── Cinematic post-processing params (derived from controls) ──
    let caStrength = 0.02 + treble * 0.03;       // chromatic aberration
    let vignetteStrength = 0.6 + bass * 0.2;    // vignette
    let scanlineIntensity = 0.08 + mids * 0.05;  // scanlines
    let crtK = -0.08;                             // CRT barrel (negative = pincushion)
    let anamorphicStrength = 0.3 + bass * 0.3;   // anamorphic streaks
    let lensDirtAmount = 0.2 + treble * 0.15;    // lens dirt

    // Apply CRT barrel distortion to UV
    let distortedUV = crtDistort(uv, crtK);
    let validUV = clamp(distortedUV, vec2<f32>(0.0), vec2<f32>(1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, validUV, 0.0).r;
    let mouse = u.zoom_config.yz;
    let mouseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, mouse, 0.0).r;

    // Mouse focal depth curve refinement
    let focalDepth = mix(mouseDepth, 0.5, 0.3);
    let depthOffset = depthCurve * (depth - focalDepth) * 2.0;

    // Radial chromatic aberration offset
    let caOffset = radialChromatic(validUV, vec2<f32>(0.5), caStrength * (1.0 + bass * 0.5));

    // Idea 1: per-eye forward-warp synthesis replaces the flat backward shift.
    // Where nothing lands (a disocclusion), the eye fills from the farthest
    // nearby pixel, as background is what was hidden.
    let sepCurve = separation * depthCurve;
    let eyeR = synthEye(validUV, 1.0, sepCurve, focalDepth);
    let eyeC = synthEye(validUV, -1.0, sepCurve, focalDepth);
    let rBase = validUV + vec2<f32>(eyeR, 0.0);
    let cBase = validUV + vec2<f32>(eyeC, 0.0);
    let rUV = clamp(rBase + caOffset, vec2<f32>(0.0), vec2<f32>(1.0));
    let cUV = clamp(cBase - caOffset, vec2<f32>(0.0), vec2<f32>(1.0));

    var color = vec3<f32>(0.0);
    color.r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    color.g = textureSampleLevel(readTexture, u_sampler, cUV, 0.0).g;
    color.b = textureSampleLevel(readTexture, u_sampler, cUV, 0.0).b;

    // Ghost fringing: R/C offset residual trails
    let ghostShift = separation * depthOffset * 0.5;
    let ghostR = textureSampleLevel(readTexture, u_sampler, clamp(rUV + vec2<f32>(ghostShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r * 0.5;
    let ghostC = textureSampleLevel(readTexture, u_sampler, clamp(cUV - vec2<f32>(ghostShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g * 0.5;
    color.r = color.r + ghostR * ghostAmount;
    color.g = color.g + ghostC * ghostAmount;

    // Idea 2: filter crosstalk. Real red/cyan gels leak a few percent of the
    // other eye's image. The leak is visible only where the two views differ
    // (high-contrast parallax edges), and it pulses slowly like binocular rivalry.
    let lumR = dot(textureSampleLevel(readTexture, u_sampler, rUV, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    let lumC = dot(textureSampleLevel(readTexture, u_sampler, cUV, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    let rivalry = 0.6 + 0.4 * sin(time * 1.7 + hash21(floor(validUV * 12.0)) * 6.2831853);
    let leak = abs(lumR - lumC) * ghostAmount * 0.35 * rivalry;
    color.r = color.r + lumC * leak;
    color.g = color.g + lumR * leak * 0.6;
    color.b = color.b + lumR * leak * 0.6;

    // Chromatic separation enhancement per depth
    let chromaBoost = smoothstep(0.0, 1.0, abs(depth - focalDepth)) * treble * 0.2;
    color.r = color.r * (1.0 + chromaBoost);
    color.g = color.g * (1.0 - chromaBoost * 0.3);
    color.b = color.b * (1.0 - chromaBoost * 0.1);

    // ── Temporal film grain ──
    let grain = temporalGrain(vec2<f32>(global_id.xy), time, treble);
    color = color + grain * grainAmount * 0.1;

    // ── Scanlines ──
    let scan = scanlines(uv.y, time, scanlineIntensity);
    color = color * scan;

    // ── Vignette ──
    let vig = vignette(validUV, vignetteStrength * 0.7);
    color = color * mix(0.4, 1.0, vig);

    // ── Color grading (lift/gamma/gain) ──
    let lift = vec3<f32>(0.02, 0.01, -0.01) * (1.0 + bass * 0.1);
    let gamma = vec3<f32>(0.95, 0.98, 1.05) - mids * 0.05;
    let gain = vec3<f32>(1.05, 1.0, 0.95) * (1.0 + treble * 0.05);
    color = colorGrade(color, lift, gamma, gain);

    // ── Anamorphic streaks from bright points ──
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let brightMask = smoothstep(0.6, 0.95, luma);
    let streaks = anamorphicStreaks(validUV, anamorphicStrength);
    color = color + streaks;

    // ── Lens dirt on bright areas ──
    let dirt = lensDirt(validUV, time, brightMask * lensDirtAmount);
    let dirtColor = vec3<f32>(0.9, 0.85, 0.7) * dirt;
    color = color + dirtColor;

    // Idea 3: convergence-plane shimmer. Pixels at the zero-parallax depth (the
    // mouse focal plane) are where both eyes agree. A faint neutral contour
    // traces that plane with a slow travelling sparkle.
    let zd = (depth - focalDepth) / 0.025;
    let zp = exp(-zd * zd);
    let shimmer = zp * (0.5 + 0.5 * sin(time * 5.0 + validUV.y * 90.0 + validUV.x * 40.0)) * 0.14 * (0.5 + depthCurve);
    color = color + vec3<f32>(shimmer);

    // ACES on display RGB, then temporal ghost persistence from the exact C
    // load in display space (HEAD filtered rgba32float history and fed back
    // premultiplied colour).
    let prev = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0).rgb;
    let toned = mix(aces(max(color, vec3<f32>(0.0))), prev * 0.9, 0.04 + mids * 0.01);

    let baseAlpha = textureSampleLevel(readTexture, u_sampler, validUV, 0.0).a;
    let finalAlpha = mix(baseAlpha, 1.0, separation * 0.3 + brightMask * 0.2 + zp * 0.1);

    // Straight (non-premultiplied) alpha, like the rest of the catalog.
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(toned, finalAlpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(toned, finalAlpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0, 0, 1));
}