// ═══ spec-distance-field-text ═══════════════════════════════════════════
//  Category: generative
//  Phase: B
//  Features: SDF, procedural-text, glyph, audio-reactive, depth-aware,
//            temporal-feedback, aces-tone-map, chromatic-aberration,
//            signed-distance-field, slot-chain, LOD, spectral-glyph-select,
//            click-ripples, phosphor-trails
//  Complexity: Medium

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const HASH_K: f32 = 43758.5453123;
// Phosphor trail feedback constants (dataTextureA -> dataTextureC chain).
const TRAIL_DECAY: f32 = 0.92;
const TRAIL_CLAMP: f32 = 1.2;
const TRAIL_MIX: f32 = 0.25;

// ── Core math ─────────────────────────────────────────────────────────
fn fast_exp(x: f32) -> f32 { return exp(clamp(x, -80.0, 0.0)); }

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * HASH_K);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0; var a = 0.5; var f = 1.0;
    for (var i = 0; i < oct; i++) { s += a * valueNoise(p * f); f *= 2.0; a *= 0.5; }
    return s;
}

// LOD-aware domain warp: fewer octaves far from the interest point.
fn domainWarpLOD(p: vec2<f32>, strength: f32, oct: i32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p, oct), fbm(p + vec2<f32>(5.2, 1.3), oct));
    return p + strength * q;
}

// ── SDF primitives ────────────────────────────────────────────────────
fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a; let ba = b - a;
    let h = clamp(dot(pa, ba) / (dot(ba, ba) + 1e-6), 0.0, 1.0);
    return length(pa - ba * h);
}

fn sdGlyph0(p: vec2<f32>) -> f32 {
    let s1 = sdSegment(p, vec2<f32>(-0.3, -0.3), vec2<f32>(0.3, -0.3));
    let s2 = sdSegment(p, vec2<f32>(0.3, -0.3), vec2<f32>(0.0, 0.4));
    let s3 = sdSegment(p, vec2<f32>(0.0, 0.4), vec2<f32>(-0.3, -0.3));
    let s4 = sdSegment(p, vec2<f32>(0.0, -0.3), vec2<f32>(0.0, 0.15));
    return min(min(s1, s2), min(s3, s4));
}

fn sdGlyph1(p: vec2<f32>) -> f32 {
    let c = abs(length(p) - 0.3);
    let h = sdSegment(p, vec2<f32>(-0.3, 0.0), vec2<f32>(0.3, 0.0));
    let v = sdSegment(p, vec2<f32>(0.0, -0.3), vec2<f32>(0.0, 0.3));
    return min(min(c, h), v);
}

fn sdGlyph2(p: vec2<f32>) -> f32 {
    let db = abs(p) - vec2<f32>(0.3);
    let box = min(max(db.x, db.y), 0.0) + length(max(db, vec2<f32>(0.0)));
    let diag = sdSegment(p, vec2<f32>(-0.3, -0.3), vec2<f32>(0.3, 0.3));
    return min(box, diag);
}

fn sdGlyph3(p: vec2<f32>) -> f32 {
    let d1 = sdSegment(p, vec2<f32>(0.0, 0.35), vec2<f32>(0.25, 0.0));
    let d2 = sdSegment(p, vec2<f32>(0.25, 0.0), vec2<f32>(0.0, -0.35));
    let d3 = sdSegment(p, vec2<f32>(0.0, -0.35), vec2<f32>(-0.25, 0.0));
    let d4 = sdSegment(p, vec2<f32>(-0.25, 0.0), vec2<f32>(0.0, 0.35));
    return min(min(min(d1, d2), min(d3, d4)), length(p) - 0.06);
}

// Branchless glyph selection via index weights.
fn sdGlyph(p: vec2<f32>, idx: i32, scale: f32) -> f32 {
    let sp = p / scale;
    let d0 = sdGlyph0(sp); let d1 = sdGlyph1(sp);
    let d2 = sdGlyph2(sp); let d3 = sdGlyph3(sp);
    let w0 = f32(idx == 0); let w1 = f32(idx == 1);
    let w2 = f32(idx == 2); let w3 = f32(idx == 3);
    return (d0 * w0 + d1 * w1 + d2 * w2 + d3 * w3) * scale;
}

// Dominant-band selector: one FFT bin per glyph (plasmaBuffer[1..4]).
// Branchless argmax over the four band energies — loudest band picks the rune.
fn spectralGlyphIndex(b0: f32, b1: f32, b2: f32, b3: f32) -> i32 {
    var idx = 0;
    var best = b0;
    if (b1 > best) { best = b1; idx = 1; }
    if (b2 > best) { best = b2; idx = 2; }
    if (b3 > best) { best = b3; idx = 3; }
    return idx;
}

fn sdGlyphGrid(p: vec2<f32>, gridScale: f32, time: f32,
               spectralIdx: i32, spectralGain: f32) -> f32 {
    let cell = floor(p * gridScale);
    let local = fract(p * gridScale) - 0.5;
    let h = hash21(cell);
    // Audio hijack: dominant band overrides the hash pick as energy rises.
    let hashIdx = i32(h * 4.0);
    let glyphIdx = select(hashIdx, spectralIdx, h < spectralGain);
    let pulse = 1.0 + sin(time * 2.0 + cell.x * 3.0 + cell.y * 2.0) * 0.1;
    return sdGlyph(local, glyphIdx, pulse / gridScale);
}

// Click ripples as expanding SDF displacement rings (uv01 space, guarded).
fn rippleDisplacement(uv01: vec2<f32>, time: f32) -> f32 {
    var disp = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age > 0.0 && age < 2.5) {
            let dist = length(uv01 - ripple.xy);
            let ring = dist - age * 0.45;
            let envelope = fast_exp(-ring * ring * 900.0) * fast_exp(-age * 1.6);
            disp += sin(ring * 60.0) * envelope;
        }
    }
    return disp;
}

// ── Color utilities ───────────────────────────────────────────────────
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// ── Entry point ───────────────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = vec2<f32>(pixel) / res;
    let uv = (uv01 - 0.5) * 2.0;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let p1 = u.zoom_params.x;
    let p2 = u.zoom_params.y;
    let p3 = u.zoom_params.z;
    let overlayMix = u.zoom_params.w;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    // Per-bin FFT energy, one bin per glyph slot.
    let bin0 = plasmaBuffer[1].x;
    let bin1 = plasmaBuffer[2].x;
    let bin2 = plasmaBuffer[3].x;
    let bin3 = plasmaBuffer[4].x;
    let depth = textureLoad(readDepthTexture, pixel, 0).r;

    // Parameter mapping — each slider drives a real constant of this shader.
    let glyphScale = mix(2.0, 12.0, p1);      // grid density of the rune field
    let glyphWidth = mix(0.003, 0.02, p2);    // SDF stroke half-width
    let glowRadius = mix(0.0, 0.05, p3);      // gaussian halo falloff radius

    // Base image from slot chain
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv01, 0.0).rgb;

    // Early exit when the overlay is disabled — keeps base image intact.
    if (overlayMix < 0.001) {
        let alpha = clamp(luma(baseColor) * 1.5, 0.2, 0.95) * (0.7 + depth * 0.3);
        let depth_in = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv01, 0.0).r;
        textureStore(writeTexture, pixel, vec4<f32>(baseColor, alpha));
        textureStore(dataTextureA, pixel, vec4<f32>(0.0));
        textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth_in, 0.0, 0.0, 0.0));
        return;
    }

    // LOD: fewer FBM octaves far from the mouse (or screen center when idle).
    let interestDist = length(uv01 - mix(vec2<f32>(0.5), mouse, step(0.5, u.zoom_config.w)));
    let lodOct = i32(clamp(3.0 - interestDist * 4.0, 1.0, 3.0));

    // Domain-warp the glyph coordinate for organic audio-reactive motion
    let warpStr = 0.02 + bass * 0.03;
    let warpedUV = domainWarpLOD(uv, warpStr, lodOct);

    // Spectral glyph selection: the loudest FFT band picks the symbol.
    let spectralIdx = spectralGlyphIndex(bin0, bin1, bin2, bin3);
    let spectralGain = clamp((bin0 + bin1 + bin2 + bin3) * 0.375, 0.0, 1.0);

    // Glyph SDF
    var d = sdGlyphGrid(warpedUV, glyphScale, time, spectralIdx, spectralGain);

    // Branchless mouse reveal
    let mouseDist = length(uv01 - mouse);
    let reveal = fast_exp(-mouseDist * mouseDist * 800.0) * step(0.5, u.zoom_config.w);
    d -= reveal * 0.02;

    // Click ripples displace the SDF field as expanding rings.
    d -= rippleDisplacement(uv01, time) * 0.04;

    // SDF masks
    let glyphMask = 1.0 - smoothstep(-glyphWidth, glyphWidth, d);
    let glowMask = fast_exp(-d * d / (glowRadius * glowRadius + 1e-4)) * (1.0 - glyphMask);
    let shadowMask = 1.0 - smoothstep(-glyphWidth * 2.0, glyphWidth * 2.0, d + 0.025);

    // Glyph color cycling with audio-driven hue shift
    let hue = time * 0.1 + uv.x * 0.2 + uv.y * 0.15 + mids * 0.3 + treble * 0.1;
    let glyphColor = vec3<f32>(
        0.5 + 0.5 * cos(TAU * (hue + 0.0)),
        0.5 + 0.5 * cos(TAU * (hue + 0.3333)),
        0.5 + 0.5 * cos(TAU * (hue + 0.6667))
    );
    let glowColor = glyphColor * (1.5 + bass) * (0.5 + p3);

    // Composite with depth-aware shadow
    let depthMod = 0.5 + depth * 0.5;
    var outColor = baseColor;
    outColor = mix(outColor, outColor * 0.7 + vec3<f32>(0.0, 0.0, 0.1) * 0.3,
                   shadowMask * 0.4 * overlayMix * depthMod);
    outColor = mix(outColor, outColor + glowColor * glowMask, glowMask * overlayMix);
    outColor = mix(outColor, glyphColor, glyphMask * overlayMix);

    // Temporal feedback: phosphor trails read back from last frame (dataTextureC).
    let prev = textureLoad(dataTextureC, pixel, 0);
    let trailAccum = min(prev.rgb * TRAIL_DECAY, vec3<f32>(TRAIL_CLAMP));
    let trailMix = TRAIL_MIX * overlayMix * (1.0 - glyphMask);
    outColor = mix(outColor, outColor + trailAccum, trailMix);
    // Persist (color, d): fresh glyph stroke wins, decayed trail accumulates.
    let trailStore = clamp(glyphColor * glyphMask + trailAccum * (1.0 - glyphMask),
                           vec3<f32>(0.0), vec3<f32>(TRAIL_CLAMP));

    // Generative chromatic aberration
    let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
    let dir = normalize(uv01 - vec2<f32>(0.5) + vec2<f32>(0.001));
    outColor = vec3<f32>(
        outColor.r + dir.x * caStr,
        outColor.g,
        outColor.b - dir.y * caStr * 0.5
    );

    // ACES tone map and semantic alpha
    outColor = acesToneMap(outColor * (0.9 + mids * 0.2));
    let alpha = clamp(luma(outColor) * 1.5, 0.2, 0.95) * (0.7 + depth * 0.3);

    textureStore(writeTexture, pixel, vec4<f32>(outColor, alpha));
    textureStore(dataTextureA, pixel, vec4<f32>(trailStore, d));
    let depth_in = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv01, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth_in, 0.0, 0.0, 0.0));
}
