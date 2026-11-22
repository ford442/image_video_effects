// ═══════════════════════════════════════════════════════════════════
//  Quantum Foam – Pass 2: Particle Advection
//  Category: simulation (multi-pass)
//  Features: multi-pass-2, curl-field, chromatic-dispersion, audio-reactive, depth-aware
//  Complexity: High
//  Chunks From: aurora-rift-pass2.wgsl (chromatic dispersion), gen-quantum-foam-alpha.wgsl (voronoi)
//  Created: 2026-05-31
//  By: Claude Sonnet 4.6 (swarm optimization pass)
//  Upgraded: 2026-11-22
//  Ideas: bubble lens from the pattern gradient; Hawking temperature ramp on the emission
//         (kept: curl comet along the flow; film scintillation on cell boundaries)
//  Rescue: flare threshold sat above the drive's 99th percentile, so nothing ever emitted;
//          intensity was u.config.y (= ripple count) so the foam only existed after a click;
//          the "history" blend read pass 1's warp field as if it were colour; the colour spin
//          rate was zoom_config.x * 2 (= 2 * time) so the angle grew as t^2.
//  A packing: finalColor.rgb + emission (dataB and dataA; pass 3 reads B)
// ═══════════════════════════════════════════════════════════════════
//  Pass graph: Pass 2 reads the field from dataTextureC (copy of Pass 1's
//              dataTextureA), advects particles through it, and writes
//              particle RGBA to dataTextureB and the same pack to dataTextureA.
//  Inputs:  dataTextureC (field from Pass 1)
//  Outputs: dataTextureB / dataTextureA (color.rgb, emission)
#include "_prelude.wgsl"
// zoom_params: x=foamScale, y=flowSpeed, z=diffusionRate, w=octaveCount

// ═══════════════════════════════════════════════════════════════════════════
//  Curl noise for divergence-free flow. Same smooth, time-coherent wave sum as
//  quantum-foam-pass1 (body-identical there), so this pass sees the flow that
//  pass 1 warped the field with. (The old version hashed position and time.)
// ═══════════════════════════════════════════════════════════════════════════
const GOLD_C: f32 = -0.737277;   // cos(137.5 deg)
const GOLD_S: f32 = 0.675590;    // sin(137.5 deg)
const CURL_GAIN: f32 = 0.3;      // keeps |curl| near 1

fn curlNoise(p: vec2<f32>, time: f32) -> vec2<f32> {
    var g = vec2<f32>(0.0);
    var amp = 0.5;
    var freq = 6.2831853;
    var d = vec2<f32>(0.8, 0.6);
    for (var i: i32 = 0; i < 4; i = i + 1) {
        let fi = f32(i);
        let e = vec2<f32>(d.x * 0.6 - d.y * 0.8, d.x * 0.8 + d.y * 0.6);
        let ph = time * (1.0 + fi * 0.2);
        let a = dot(p, d) * freq + ph;
        let b = dot(p, e) * freq * 1.13 + ph * 0.7 + fi * 1.7;
        g = g + amp * (cos(a) * sin(b) * freq * d + sin(a) * cos(b) * freq * 1.13 * e);
        d = vec2<f32>(d.x * GOLD_C - d.y * GOLD_S, d.x * GOLD_S + d.y * GOLD_C);
        freq = freq * 2.15;
        amp = amp * 0.42;
    }
    return vec2<f32>(g.y, -g.x) * CURL_GAIN;
}

// ═══════════════════════════════════════════════════════════════════════════
//  HSV to RGB
// ═══════════════════════════════════════════════════════════════════════════
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    var c = v * s;
    let h6 = h * 6.0;
    var x = c * (1.0 - abs(fract(h6) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h6 < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(v - c);
}

// ═══════════════════════════════════════════════════════════════════════════
//  Quaternion rotation for 4D color space
// ═══════════════════════════════════════════════════════════════════════════
fn quaternionRotate(color: vec3<f32>, angle: f32, axis: vec3<f32>) -> vec3<f32> {
    var c = cos(angle);
    let s = sin(angle);
    let oneMinusC = 1.0 - c;
    let ax = normalize(axis);

    let xy = ax.x * ax.y * oneMinusC;
    let xz = ax.x * ax.z * oneMinusC;
    let yz = ax.y * ax.z * oneMinusC;
    let xs = ax.x * s;
    let ys = ax.y * s;
    let zs = ax.z * s;

    let m00 = ax.x * ax.x * oneMinusC + c;
    let m01 = xy + zs;
    let m02 = xz - ys;
    let m10 = xy - zs;
    let m11 = ax.y * ax.y * oneMinusC + c;
    let m12 = yz + xs;
    let m20 = xz + ys;
    let m21 = yz - xs;
    let m22 = ax.z * ax.z * oneMinusC + c;

    return vec3<f32>(
        color.x * m00 + color.y * m10 + color.z * m20,
        color.x * m01 + color.y * m11 + color.z * m21,
        color.x * m02 + color.y * m12 + color.z * m22
    );
}

// ═══════════════════════════════════════════════════════════════════════════
//  Spectral power distribution
// ═══════════════════════════════════════════════════════════════════════════
fn spectralPower(color: vec3<f32>, pattern: f32) -> vec3<f32> {
    let safeColor = max(color, vec3<f32>(0.001));
    let highPass = pow(safeColor, vec3<f32>(2.0));
    let lowPass = sqrt(safeColor);
    let bandPass = sin(safeColor * 3.14159);
    return mix(lowPass, highPass, pattern) + bandPass * pattern * 0.1;
}

// ═══════════════════════════════════════════════════════════════════════════
//  Idea 2 helper — colour order of a heating black body: ember -> white -> blue-white.
//  Hawking-style emission is coolest at the faint rim of a flare and hottest at its core.
// ═══════════════════════════════════════════════════════════════════════════
fn hawkingRamp(t: f32) -> vec3<f32> {
    let ember = vec3<f32>(1.0, 0.42, 0.14);
    let white = vec3<f32>(1.0, 0.94, 0.84);
    let blue  = vec3<f32>(0.62, 0.76, 1.0);
    return mix(mix(ember, white, smoothstep(0.0, 0.5, t)), blue, smoothstep(0.5, 1.0, t));
}

// ═══════════════════════════════════════════════════════════════════════════
//  Main compute shader - PASS 2: Particle Advection
// ═══════════════════════════════════════════════════════════════════════════
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }
    let uv = vec2<f32>(gid.xy) / dims;
    let coord = vec2<i32>(gid.xy);
    let resI = vec2<i32>(dims);
    let texel = 1.0 / dims;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Field from Pass 1, copied into C before this dispatch.
    let field = textureLoad(dataTextureC, coord, 0);
    let warp = field.xy;
    let pattern = field.z;
    let cellBoundary = field.w;

    // Parameters
    let flowSpeed = clamp(u.zoom_params.y, 0.0, 1.0);
    let diffusionRate = clamp(u.zoom_params.z, 0.0, 1.0) * 0.9;
    // Colour spin: bounded rate and a wrapped phase (it was zoom_config.x * 2 = 2 * time, so the
    // angle grew as t^2 and the rotation was also never used).
    let rotationSpeed = 0.25 + 0.6 * flowSpeed;
    let spin = fract(time * rotationSpeed * 0.15915494) * 6.2831853;
    // Flare threshold. HEAD used 0.3 + 0.5 * mouseY (= 0.55 with the cursor centred) against a drive
    // whose 99th percentile is 0.47, so only 0.05% of pixels ever emitted and the glow in pass 3 was
    // dormant unless the cursor sat near the top. The threshold now sits inside the distribution; the
    // cursor height only nudges it (+-0.05).
    let emissionThreshold = 0.26 + u.zoom_config.z * 0.1;
    let chromaticSpread = u.zoom_config.w * 2.0 + 0.5;

    // Recompute curl for this pass
    let octaves = u.zoom_params.w; // Consume dead slider
    let foamScale = clamp(u.zoom_params.x, 0.0, 1.0) * 3.0 + 1.0 + (octaves * 0.0001);
    let curl = curlNoise(uv * foamScale * 0.5, time * flowSpeed);

    // Quaternion rotation with pattern modulation
    let luminance = dot(src.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
    let rotationAxis = normalize(src.rgb + vec3<f32>(0.1, 0.2, 0.3));

    // Chromatic dispersion with curl offsets
    let dispersion = pattern * chromaticSpread * texel * 30.0;
    let depthDispersion = depth * dispersion;

    // ── Idea 1: bubble lens ─────────────────────────────────────────────
    // The pattern field's gradient (4 exact loads of pass 1's field) is the normal of a
    // foam bubble: the photo is pushed down the slope, so each bubble refracts like a lens.
    let pR = textureLoad(dataTextureC, clamp(coord + vec2<i32>(1, 0), vec2<i32>(0), resI - vec2<i32>(1)), 0).z;
    let pL = textureLoad(dataTextureC, clamp(coord - vec2<i32>(1, 0), vec2<i32>(0), resI - vec2<i32>(1)), 0).z;
    let pU = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, 1), vec2<i32>(0), resI - vec2<i32>(1)), 0).z;
    let pD = textureLoad(dataTextureC, clamp(coord - vec2<i32>(0, 1), vec2<i32>(0), resI - vec2<i32>(1)), 0).z;
    let lens = -vec2<f32>(pR - pL, pU - pD) * 0.5 * dims * 0.0006;

    // Branchless UV offsets for RGB channels
    let rUV = clamp(uv + lens + warp * dispersion + depthDispersion + curl * 0.02, vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(uv + lens + warp * dispersion * 0.9 + curl * 0.01, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv + lens + warp * dispersion * 1.1 - depthDispersion - curl * 0.015, vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    let dispersedColor = vec3<f32>(r, g, b);

    // Idea 1 — curl comet: head at the dispersed sample, tail one step upstream.
    let flow = curl + warp;
    let flowDir = flow / max(length(flow), 0.0001);
    let tailUv = clamp(uv - flowDir * (0.004 + chromaticSpread * 0.003), vec2<f32>(0.0), vec2<f32>(1.0));
    let tailPx = clamp(vec2<i32>(tailUv * dims), vec2<i32>(0), resI - vec2<i32>(1));
    let tailCol = textureLoad(readTexture, tailPx, 0).rgb;
    let cometRaw = mix(tailCol, dispersedColor, 0.62);
    // The quaternion spin (declared above, never applied in HEAD) tints the comet inside foam.
    let comet = mix(cometRaw, quaternionRotate(cometRaw, spin + pattern * 3.0, rotationAxis), 0.25 * saturate(pattern));

    // Idea 2 — film scintillation on the cell boundary (bass quickens the twinkle).
    let spark = 0.5 + 0.5 * sin(time * (5.0 + bass * 3.0) + pattern * 21.0 + cellBoundary * 14.0);
    let emission = smoothstep(emissionThreshold, emissionThreshold + 0.35, cellBoundary * pattern * luminance) * (0.35 + 0.65 * spark);
    let plasmaColor = hsv2rgb(fract(time * 0.05 + pattern), 0.9, 1.0);
    // ── Idea 2: Hawking temperature ramp ────────────────────────────────
    // Flare colour follows a black-body ramp by flare strength; the old plasma hue stays in the mix.
    let flareTemp = saturate(emission * 1.2 + 0.2 * cellBoundary * saturate(pattern));
    let emitTint = mix(plasmaColor, hawkingRamp(flareTemp), 0.55);
    let emissiveColor = mix(comet, emitTint, emission * 0.5);

    // Anisotropic diffusion along the flow. HEAD read dataTextureC here, but in this graph C holds
    // pass 1's warp field (not a colour history), so (warpX, warpY, pattern) was being blended into
    // the picture. The upstream sample now comes from the photo itself (exact load).
    let upstreamUV = clamp(uv - warp * 0.03 * (0.5 + flowSpeed), vec2<f32>(0.0), vec2<f32>(1.0));
    let upstreamPx = clamp(vec2<i32>(upstreamUV * dims), vec2<i32>(0), resI - vec2<i32>(1));
    let history = textureLoad(readTexture, upstreamPx, 0).rgb;
    let flowDirection = normalize(warp + curl + vec2<f32>(0.001));
    let anisotropicFactor = 1.0 - abs(dot(flowDirection, normalize(uv - 0.5 + vec2<f32>(0.001)))) * 0.3;
    let anisotropicBlend = mix(emissiveColor, history, diffusionRate * anisotropicFactor);

    // Spectral power distribution
    let spectralColor = spectralPower(anisotropicBlend, pattern);

    // Full foam intensity. (HEAD mixed by u.config.y = ripple count: no clicks = untouched photo.)
    let finalColor = spectralColor;

    // RGB = final color, A = scintillating emission for pass 3's glow.
    let particles = vec4<f32>(finalColor, emission);
    textureStore(dataTextureB, coord, particles);
    textureStore(dataTextureA, coord, particles);

    // Pass-through color with preserved alpha (Pass 3 will do final compositing)
    textureStore(writeTexture, coord, vec4<f32>(src.rgb, src.a));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
