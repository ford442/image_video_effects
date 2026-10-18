// ═══════════════════════════════════════════════════════════════════
//  Superformula Spirograph Spiral
//  Category: generative
//  Features: mouse-driven, audio-reactive, audio-driven, temporal, chromatic,
//            depth-aware, spirograph, superformula, feedback-warp, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-27
//  Ideas: petal-tip pearls from outline curvature; pen-trace rosette (the real epicycle curve); nested outline ladder
//  A packing: raw hue-clamped colour history (pre-ACES) + presence alpha; ACES on display RGB only
//  Earlier (2026-07-26): per-bin FFT n2/n3, click petal bursts, IQ palette, hueClamp for the history loop
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

const TAU: f32 = 6.283185307179586;

// IQ cosine palette: cheaper and smoother than HSV, cycles hue continuously.
fn iqPalette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.50, 0.50, 0.50);
    let b = vec3<f32>(0.50, 0.50, 0.50);
    let c = vec3<f32>(1.00, 1.00, 1.00);
    let d = vec3<f32>(0.00, 0.33, 0.67);
    return a + b * cos(TAU * (c * t + d));
}

fn superformula(phi: f32, m: f32, n1: f32, n2: f32, n3: f32) -> f32 {
    let t1 = pow(abs(cos(m * phi * 0.25)), n2);
    let t2 = pow(abs(sin(m * phi * 0.25)), n3);
    return pow(max(t1 + t2, 0.0001), -1.0 / max(n1, 0.0001));
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Idea 2 helper: distance from point to segment a-b.
fn segDist(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let ab = b - a;
    let h = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-8), 0.0, 1.0);
    return length(p - a - ab * h);
}

fn spiroCenter(phi: f32, time: f32, speed: f32, intensity: f32, bass: f32) -> vec2<f32> {
    var center = vec2<f32>(0.0);
    var radius = mix(0.22, 0.36, intensity);
    for (var i: i32 = 0; i < 4; i = i + 1) {
        let harmonic = f32(i + 1);
        let a = phi * harmonic + time * speed * (0.9 + harmonic * 0.35) * (1.0 + bass * 0.25);
        center = center + vec2<f32>(cos(a), sin(a)) * radius;
        radius = radius * 0.52;
    }
    return center;
}

// Hue-preserving clamp: scale RGB down so max channel <= limit, keeping chroma.
fn hueClamp(color: vec3<f32>, limit: f32) -> vec3<f32> {
    let peak = max(color.r, max(color.g, color.b));
    let scale = select(1.0, limit / peak, peak > limit);
    return color * scale;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x * 5.0; // Fast motion upgrade
    let clock = u.config.x;      // raw time: ripple.z is stamped in raw time
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Band averages
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    // Individual FFT bins give the superformula its own spectral voices:
    // a low bin sharpens petal shoulders (n2), a high bin frills the tips (n3).
    let binLow = plasmaBuffer[1].x;
    let binMid = plasmaBuffer[2].x;
    let binHigh = plasmaBuffer[5].x;

    // ── Slider wiring (preset contract: ids/defaults unchanged) ──
    // x: Orbit Intensity -> epicycle radius + superformula shoulder + shape scale
    // y: Spin Speed      -> orbit angular rate + feedback rotation + hue drift
    // z: Petal Count     -> superformula symmetry m (petals) + spoke frequency
    // w: Feedback Warp   -> history zoom-out factor + chromatic blend amount
    let intensity = mix(0.2, 1.35, u.zoom_params.x);
    let spinSpeed = mix(0.2, 2.8, u.zoom_params.y);
    let petalCount = mix(3.0, 12.0, u.zoom_params.z);
    let feedback = u.zoom_params.w;

    let aspect = resolution.x / max(resolution.y, 1.0);
    var p = uv - 0.5;
    p.x = p.x * aspect;

    let mouseOffset = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0);
    p = p - mouseOffset * 0.55;

    // Nested epicycles: 4 harmonics chasing each other around the pointer.
    let orbit = spiroCenter(atan2(p.y, p.x) + length(p) * 6.0, time, spinSpeed, intensity, bass);
    let q = p - orbit * mix(0.08, 0.22, intensity);
    let dist = length(q);
    let angle = atan2(q.y, q.x);

    // Superformula exponents: n1 breathes slowly, n2/n3 follow individual bins.
    let n1 = mix(0.25, 1.4, 0.5 + 0.5 * sin(time * 0.2 + mids * 2.0));
    let n2 = 1.2 + intensity * 4.5 + binLow * 3.5;
    let n3 = 1.0 + treble * 4.0 + binHigh * 6.0;
    let superR = superformula(angle + time * spinSpeed * 0.18, petalCount + bass * 4.0 + binMid * 2.0, n1, n2, n3);
    var shapeRadius = superR * mix(0.12, 0.42, intensity);

    // Click petal bursts: each live ripple detonates a decaying radial impulse
    // that inflates the shape radius in a ring around the click point.
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rp = (ripple.xy - 0.5) * vec2<f32>(aspect, 1.0) - mouseOffset * 0.55;
        let age = clock - ripple.z; // fix: was fast-time minus raw stamp (window collapsed to ~0.3 s)
        if (age > 0.0 && age < 1.6) {
            let decay = max(0.0, 1.0 - age * 0.625);
            let ringDist = abs(length(q - rp + orbit * mix(0.08, 0.22, intensity)) - age * 0.55);
            let ring = smoothstep(0.12, 0.0, ringDist);
            shapeRadius = shapeRadius + ring * decay * decay * 0.16; // fix: ripple.w is always 0 (engine padding) -> clicks were dead
        }
    }

    // Idea 1 - petal-tip pearls: a Newton step on the outline's own radius
    // (slope / curvature from two angular neighbours) locates each petal apex
    // without any state. A bead of light sits on the outline exactly at the tips.
    let sfAng = angle + time * spinSpeed * 0.18;
    let sfM = petalCount + bass * 4.0 + binMid * 2.0;
    let dA = 0.1;
    let rL = superformula(sfAng - dA, sfM, n1, n2, n3);
    let rR = superformula(sfAng + dA, sfM, n1, n2, n3);
    let curvDen = 2.0 * superR - rL - rR;                      // > 0 on a convex cap
    let apexOff = (rR - rL) * dA / (2.0 * max(curvDen, 1e-4 * superR));
    let apex = select(0.0, exp(-(apexOff * apexOff) / 0.0064), curvDen > 1e-4 * superR);
    let beadR = (dist - shapeRadius) / 0.022;
    let pearl = apex * exp(-beadR * beadR);

    // Idea 2 - pen-trace rosette: the actual 4-harmonic epicycle curve
    // (closed over phi = 0..TAU) drawn as a glowing hairline inside the bloom.
    let penScale = 0.4;
    var penMin = 1e3;
    var penPrev = spiroCenter(0.0, time, spinSpeed, intensity, bass) * penScale;
    for (var k: i32 = 1; k <= 48; k = k + 1) {
        let penNext = spiroCenter(TAU * f32(k) / 48.0, time, spinSpeed, intensity, bass) * penScale;
        penMin = min(penMin, segDist(q, penPrev, penNext));
        penPrev = penNext;
    }
    let pen = smoothstep(0.007, 0.0, penMin) + 0.35 * smoothstep(0.03, 0.0, penMin);

    // Idea 3 - nested outline ladder: homothetic copies of the superformula
    // outline (dist / shapeRadius contours) drift inward like a topographic rosette.
    let rel = dist / max(shapeRadius, 0.03);
    let ladderF = fract(rel * 4.0 - time * 0.05 * spinSpeed);
    let ladderLine = smoothstep(0.09, 0.0, abs(ladderF - 0.5) * 0.5);
    let ladder = ladderLine * smoothstep(1.02, 0.85, rel) * smoothstep(0.08, 0.35, rel);

    // Counter-rotating ghost ring: a dim echo of the same superformula,
    // spun backwards and shrunk, gives the bloom interior some depth.
    let ghostR = superformula(-angle - time * spinSpeed * 0.11, petalCount + bass * 4.0 + binMid * 2.0, n1 * 1.6, n2, n3);
    let ghostRadius = ghostR * mix(0.06, 0.2, intensity);
    let ghostBand = smoothstep(0.05, 0.0, abs(dist - ghostRadius));

    // Inner core pulse: hot nucleus at the orbit centroid, breathing with bass.
    let core = smoothstep(0.09 + bass * 0.05, 0.0, dist) * (0.5 + 0.5 * binLow);

    let band = smoothstep(0.08, 0.0, abs(dist - shapeRadius));
    let spokes = 0.5 + 0.5 * cos(angle * (petalCount * 2.0) - dist * 28.0 + time * spinSpeed * 4.0);
    let swirl = 0.5 + 0.5 * sin(length(p) * 24.0 - angle * (petalCount * 1.5) - time * spinSpeed * 3.0);
    let halo = smoothstep(0.35, 0.0, abs(dist - shapeRadius * 1.18));
    let pattern = band * (0.6 + 0.4 * spokes) + pow(swirl, 3.0) * 0.25 + halo * 0.18
                + ghostBand * 0.22 + core * 0.45
                + pearl * 0.55 + pen * 0.4 + ladder * 0.16;

    // IQ cosine palette replaces HSV: t plays the hue role, gain plays value.
    let hueT = fract(angle / TAU + time * 0.12 * spinSpeed + spokes * 0.18 + length(p) * 0.2 + mids * 0.1);
    let gain = pattern * mix(0.85, 2.6, intensity) * mix(0.85, 1.0, treble * 0.5);
    var color = iqPalette(hueT) * gain;
    color = color + vec3<f32>(1.0, 0.94, 0.82) * pearl * 0.35              // pearls run hot
                  + iqPalette(fract(hueT + 0.33)) * pen * 0.25;             // pen hairline gets its own hue

    // ── Feedback history UV chain (warp signature - preserve verbatim) ──
    let rot = 0.015 + spinSpeed * 0.01;
    let c = cos(rot);
    let s = sin(rot);
    var historyP = vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);
    historyP = historyP * (0.985 - feedback * 0.08);
    var historyUV = historyP;
    historyUV.x = historyUV.x / aspect;
    historyUV = historyUV + 0.5 + mouseOffset * 0.15;

    // Chromatic temporal feedback: per-channel offset sampling
    let prevR = textureSampleLevel(dataTextureC, u_sampler, historyUV + vec2<f32>(bass * 0.008, 0.0), 0.0).r;
    let prevG = textureSampleLevel(dataTextureC, u_sampler, historyUV + vec2<f32>(0.0, mids * 0.006), 0.0).g;
    let prevB = textureSampleLevel(dataTextureC, u_sampler, historyUV - vec2<f32>(treble * 0.005, 0.0), 0.0).b;
    let chromaticPrev = vec3<f32>(prevR, prevG, prevB);
    let feedbackMix = mix(0.12, 0.78, feedback);
    color = mix(color, chromaticPrev, feedbackMix * (0.42 + band * 0.28));

    // Standard temporal feedback blend
    let prevStandard = textureLoad(dataTextureC, coord, 0);
    color = mix(color, prevStandard.rgb * 0.9, 0.03 + bass * 0.01);

    // Chromatic dispersion: per-channel audio boosts
    color.r *= 1.0 + bass * 0.1;
    color.g *= 1.0 + mids * 0.08;
    color.b *= 1.0 + treble * 0.1;

    // Hue-preserving clamp at ~1.2 before the feedback write: future-proofs
    // the history loop (gain can push value toward ~2.6 at high intensity).
    color = hueClamp(color, 1.2);

    let edgeFade = 1.0 - smoothstep(0.35, 0.82, length(p));
    let presence = clamp(pattern * edgeFade, 0.0, 1.0);
    let finalColor = mix(inputColor.rgb, acesFilm(color), presence * 0.9); // ACES on display only; A keeps raw history
    let finalAlpha = max(inputColor.a, presence * 0.9);
    let finalDepth = mix(inputDepth, clamp(shapeRadius + halo * 0.25, 0.0, 1.0), presence * 0.85);

    textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(color, presence));
}
