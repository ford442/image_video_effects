// ═══════════════════════════════════════════════════════════════════
//  Holographic Shatter
//  Category: image
//  Features: advanced-alpha, holographic, shatter, glass, mouse-driven, audio-reactive,
//            temporal-shard-persistence, audio-impact, chromatic-edge-refraction
//  Complexity: High
//  Upgraded: 2026-10-05
//  Ideas: diffraction grating per shard; two-beam interference ghost; scanline reconstruction sweep
//  A packing: pre-ACES display RGBA (C read back as shard colour history)
// ═══════════════════════════════════════════════════════════════════
//  Batch-19: wired the dead Depth Weight slider, near-focused impact
//            falloff (was inverted), click shatter detonations via ripples
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

fn depthLayeredAlpha(color: vec3<f32>, uv: vec2<f32>, depthWeight: f32) -> f32 {
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let depthAlpha = mix(0.4, 1.0, depth);
    let lumaAlpha = mix(0.5, 1.0, luma);
    return mix(lumaAlpha, depthAlpha, depthWeight);
}

fn rand(co: vec2<f32>) -> f32 {
    return fract(sin(dot(co, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Idea 1 helper: visible wavelength (nm) -> RGB, Gaussian lobe fit
fn spectralRGB(lambda: f32) -> vec3<f32> {
    let r1 = (lambda - 610.0) / 45.0;
    let r2 = (lambda - 430.0) / 25.0;
    let g1 = (lambda - 545.0) / 45.0;
    let b1 = (lambda - 455.0) / 35.0;
    return vec3<f32>(
        exp(-r1 * r1) + 0.35 * exp(-r2 * r2),
        exp(-g1 * g1),
        exp(-b1 * b1)
    );
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

    // ── Slider mapping (saved-preset contract: zoom_params x/y/z/w) ──
    //   x: Shatter Amount     -> shard flight distance (bass-boosted)
    //   y: Hologram Intensity -> foil / edge interference strength
    //   z: Depth Weight       -> depth- vs luma-tiered alpha blend
    //   w: Shard Count        -> fracture grid density (10..60 cells)
    let shatterAmount = clamp(u.zoom_params.x * (1.0 + bass * 0.4), 0.0, 1.0);
    let holographicIntensity = u.zoom_params.y;
    let depthWeight = u.zoom_params.z;
    let shardCount = u.zoom_params.w * 50.0 + 10.0;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let held = select(0.0, 1.0, mouseDown > 0.5);
    let aspect = resolution.x / max(resolution.y, 1.0);
    let dM = length((uv - mouse) * vec2<f32>(aspect, 1.0));

    // FIXED: impact falloff was inverted (grew with distance, so mouse-down
    // flung far shards while the cursor zone sat still). Now near-focused,
    // with a small global baseline so idle / far-field drift survives.
    let mouseGain = 0.4 + mouseDown * 0.6 + held * 0.15;
    let nearImpact = mouseGain * (1.0 - smoothstep(0.0, 0.6, dM));
    let impact = max(nearImpact, 0.25 * mouseGain);

    // Fracture grid + per-shard identity
    let gridUV = uv * shardCount;
    let shardId = floor(gridUV);
    let shardUv = fract(gridUV);

    let shardRand = rand(shardId);
    let shardCenter = (shardId + 0.5) / shardCount;
    let flightDir = normalize(shardCenter - mouse + vec2<f32>(1e-4));

    // Click shatter detonations: each live ripple acts as a decaying impact
    // center (same flight math, ripple position as origin, weight
    // exp(-age * 2.5) over a ~1.5s life) so individual clicks crack the
    // glass even with the mouse button up.
    let rippleCount = min(u32(u.config.y), 50u);
    var clickImpact: f32 = 0.0;
    var clickDir = vec2<f32>(0.0, 0.0);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age > 0.0 && age < 1.5) {
            let rDist = distance(shardCenter, ripple.xy);
            let rDir = normalize(shardCenter - ripple.xy + vec2<f32>(1e-4));
            let w = exp(-age * 2.5) * (1.0 - smoothstep(0.0, 0.5, rDist));
            clickImpact = clickImpact + w;
            clickDir = clickDir + rDir * w;
        }
    }
    clickImpact = min(clickImpact, 1.0);

    // Audio-driven impact force: mouse shockwave + click detonations
    let shardForce = shatterAmount * (0.4 + shardRand * 0.6) * (1.0 + treble * 0.3);
    let offset = flightDir * shardForce * impact + clickDir * shardForce * 0.8;

    let warpedUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
    let shardSample = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0);
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    let edgeDist = min(min(shardUv.x, 1.0 - shardUv.x), min(shardUv.y, 1.0 - shardUv.y));
    let edgeGlow = 1.0 - smoothstep(0.0, 0.1, edgeDist);

    // How far this shard has flown (0 = resting, 1 = well displaced)
    let offLen = length(offset);
    let flight = smoothstep(0.02, 0.12, offLen);

    // Chromatic edge refraction per shard (holographic sin math unchanged).
    // FIXED: the palette read plasmaBuffer[1..8], which is never written
    // (always 0). The tint is now the live bass/mids/treble triple, so
    // silence reproduces the old look exactly.
    let phase = time + shardRand * TAU + depth * PI;
    let holographic = 0.5 + 0.5 * sin(vec3<f32>(phase, phase + 2.094, phase + 4.188));
    let palette = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    var foil = mix(holographic, holographic * (0.6 + palette * 0.7), 0.4);
    let thinFilm = 0.5 + 0.5 * cos(vec3<f32>(phase * 1.3, phase * 1.3 + 2.1, phase * 1.3 + 4.2) + mids * 2.0);
    foil = mix(foil, foil * thinFilm, edgeGlow * 0.35);

    // Per-channel refraction along the flight direction: shard edges split
    // light like a prism; strength is mids-driven so edges shimmer with audio.
    let chromaMix = clamp(edgeGlow * (0.5 + mids * 0.5) + clickImpact * 0.3, 0.0, 1.0);
    let refr = flightDir * (edgeGlow * 0.012 + impact * shatterAmount * 0.01);
    let refrR = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV + refr, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let refrB = textureSampleLevel(readTexture, u_sampler, clamp(warpedUV - refr, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

    // Temporal shard persistence: previous frame offsets blend for settling glass
    // Clamped: right after a shader switch C holds the previous shader's A (raw fields, HDR, negatives).
    let prevShards = clamp(textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0).rgb, vec3<f32>(0.0), vec3<f32>(2.0));
    let settled = mix(shardSample.rgb, prevShards * 0.92, 0.06 + bass * 0.02);

    var finalColor = mix(settled, foil, edgeGlow * holographicIntensity);
    finalColor = vec3<f32>(
        mix(finalColor.r, refrR, chromaMix * 0.6),
        finalColor.g,
        mix(finalColor.b, refrB, chromaMix * 0.6)
    );

    // Idea 1: Diffraction grating per shard — each shard's embossed foil has its
    // own grating orientation; a wandering light makes first-order rainbow bands
    // sweep across it. Resting shards shimmer faintly, flying (tilted) shards
    // catch much more of the spectrum.
    let gAng = shardRand * PI;
    let gDir = vec2<f32>(cos(gAng), sin(gAng));
    let lightP = vec2<f32>(0.5 + 0.35 * cos(time * 0.21), 0.5 + 0.35 * sin(time * 0.17));
    let gS = dot((uv - lightP) * vec2<f32>(aspect, 1.0), gDir) * (3.0 + shardRand * 4.0)
           + time * 0.05 + shardRand + offLen * 12.0;
    let lambda = 400.0 + 300.0 * fract(gS);
    let rainbow = spectralRGB(lambda);
    let gratingW = holographicIntensity * (0.08 + 0.32 * flight) * (1.0 + treble * 0.5);
    finalColor = mix(finalColor, finalColor * 0.55 + rainbow * 0.55, clamp(gratingW, 0.0, 0.6));

    // Idea 2: Two-beam interference ghost — a displaced fragment still
    // reconstructs where it came from: the un-displaced image appears under
    // straight fringes perpendicular to the flight; more displacement = finer
    // fringes (object/reference beam angle grows).
    let offDir = offset / max(offLen, 1e-5);
    let fringeFreq = 1.5 + min(offLen * shardCount * 2.5, 7.0);
    let fringe = 0.5 + 0.5 * cos(TAU * dot(shardUv - 0.5, offDir) * fringeFreq - time * 1.3);
    let ghostW = holographicIntensity * 0.35 * flight;
    let ghost = baseColor.rgb * (0.4 + 1.2 * fringe) * vec3<f32>(0.85, 1.05, 1.0);
    finalColor = mix(finalColor, ghost, ghostW * 0.5);

    // Idea 3: Scanline reconstruction sweep — each shard is re-drawn by its own
    // horizontal scan beam; shards in flight lose signal on alternate rows.
    let sweep = fract(time * 0.35 + shardRand);
    let beamD = shardUv.y - sweep;
    let beam = exp(-beamD * beamD * 500.0);
    let rowOdd = f32(global_id.y % 2u);
    let signalLoss = holographicIntensity * flight * 0.22 * rowOdd;
    finalColor = finalColor * (1.0 - signalLoss)
               + vec3<f32>(0.55, 0.9, 1.0) * beam * holographicIntensity * 0.14 * (1.0 + treble);

    let effectIntensity = edgeGlow * holographicIntensity + shatterAmount * 0.5 + clickImpact * 0.3;

    // FIXED: Depth Weight slider was dead - depthLayeredAlpha() was never
    // called. zoom_params.z now blends source alpha against the
    // depth/luma-tiered alpha, scaled by how strongly the effect applies.
    let finalAlpha = mix(baseColor.a, depthLayeredAlpha(finalColor, uv, depthWeight), clamp(effectIntensity, 0.0, 1.0));

    let display = aces(clamp(finalColor, vec3<f32>(0.0), vec3<f32>(2.0)));
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(display, finalAlpha));
    // dataTextureA stays pre-ACES DISPLAY color (the C feedback expects color, not masks)
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(max(finalColor, vec3<f32>(0.0)), finalAlpha));
    // Depth passthrough (normalized: alpha lane 0.0 instead of the odd 1)
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
