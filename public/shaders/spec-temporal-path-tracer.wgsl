// ═══════════════════════════════════════════════════════════════════
//  spec-temporal-path-tracer
//  Category: advanced-hybrid
//  Features: temporal-accumulation, path-tracing, Monte-Carlo, upgraded-rgba
//  Complexity: Very High
//  Chunks From: chunk-library (hash22)
//  Created: 2026-04-18
//  By: Agent 3C — Spectral Computation Pioneer
//  Upgraded: 2026-11-20
//  Ideas: stratified (jittered) march lattice that removes the 2 px quantisation rings; hit-distance falloff (§12.2F soft inverse-square, 2D); source-fingerprint history rejection with a bounded horizon (TAA)
//  A packing: raw accumulation (rgb = mean radiance, a = n + 0.9 * source-luma fingerprint)
// ═══════════════════════════════════════════════════════════════════
//  2D Path Tracer with Temporal Accumulation
//  Casts light rays from each pixel that bounce off surfaces defined
//  by image edges/depth. Accumulates samples over time.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// zoom_params: x=Max Bounces, y=Edge Threshold, z=Radiance Scale, w=Surface Roughness

// History horizon (HEAD's 300, now a bounded exponential horizon instead of a hard
// reset), the shortened horizon while the pointer light is held, and the scale that
// keeps the luma fingerprint inside the fraction of A.a (n + 0.9*fp never carries).
const MAX_HISTORY: f32 = 300.0;
const HELD_HISTORY: f32 = 32.0;
const FP_SCALE: f32 = 0.9;
// Hit-distance falloff: core radius and the mean hit distance it is normalised to (px).
const FALL_R0: f32 = 12.0;
const FALL_REF: f32 = 26.0;

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn hash11(n: f32) -> f32 {
    return fract(sin(n * 127.1) * 43758.5453);
}

fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3(0.0), vec3(1.0));
}

// Sample luminance at position
fn sampleLuma(uv: vec2<f32>) -> f32 {
    let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

// Compute gradient magnitude as edge strength
fn edgeStrength(uv: vec2<f32>, texel: vec2<f32>) -> f32 {
    let c = sampleLuma(uv);
    let cx = sampleLuma(uv + vec2<f32>(texel.x, 0.0));
    let cy = sampleLuma(uv + vec2<f32>(0.0, texel.y));
    return abs(cx - c) + abs(cy - c);
}

// Approximate normal from edge gradient
fn edgeNormal(uv: vec2<f32>, texel: vec2<f32>) -> vec2<f32> {
    let c = sampleLuma(uv);
    let cx = sampleLuma(uv + vec2<f32>(texel.x, 0.0));
    let cy = sampleLuma(uv + vec2<f32>(0.0, texel.y));
    return normalize(vec2<f32>(c - cx, c - cy) + 1e-6);
}

// ── Idea 3 helper: source fingerprint (centre + 4 diagonals at 5 px) ──
// A cheap local-luma signature of what the rays can see nearby. Stored in the
// fraction of A.a and compared next frame to decide how much history to keep.
fn sourceFingerprint(uv: vec2<f32>, texel: vec2<f32>, centerLuma: f32) -> f32 {
    let r = texel * 5.0;
    let s = sampleLuma(uv + vec2<f32>(r.x, r.y)) + sampleLuma(uv + vec2<f32>(-r.x, r.y))
          + sampleLuma(uv + vec2<f32>(r.x, -r.y)) + sampleLuma(uv - r);
    return clamp((centerLuma + s) * 0.2, 0.0, 1.0);
}

struct HitResult {
    hit: bool,
    pos: vec2<f32>,
    normal: vec2<f32>,
};

fn marchToEdge(startUV: vec2<f32>, dir: vec2<f32>, texel: vec2<f32>, maxSteps: i32, threshold: f32, lattice: f32) -> HitResult {
    // Idea 1: the 2-px step lattice is offset by lattice in [0,1) so the quantised
    // hit distance averages out instead of printing concentric rings in the converged
    // image. lattice = 0 reproduces HEAD's march exactly.
    var pos = startUV - dir * texel * 2.0 * lattice;
    for (var i: i32 = 0; i < maxSteps; i = i + 1) {
        pos = pos + dir * texel * 2.0;
        if (pos.x < 0.0 || pos.x > 1.0 || pos.y < 0.0 || pos.y > 1.0) {
            return HitResult(false, pos, vec2<f32>(0.0));
        }
        if (edgeStrength(pos, texel) > threshold) {
            return HitResult(true, pos, edgeNormal(pos, texel));
        }
    }
    return HitResult(false, pos, vec2<f32>(0.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let texel = 1.0 / res;
    let time = u.config.x;

    let maxBounces = i32(mix(2.0, 5.0, u.zoom_params.x));
    let edgeThreshold = mix(0.05, 0.3, u.zoom_params.y);
    let radianceScale = mix(0.5, 2.0, u.zoom_params.z);
    let roughness = mix(0.0, 1.0, u.zoom_params.w);

    // Read previous accumulation (exact load: C is a raw field, not a filtered image)
    let prev = textureLoad(dataTextureC, vec2<i32>(gid.xy), 0);
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // ── Idea 3: source-fingerprint history rejection + bounded horizon (TAA) ──
    // A.a = n + FP_SCALE * fingerprint. If the local source luma moved since the
    // history was written, the kept sample count shrinks smoothly (disocclusion /
    // history rejection) so a changing video re-converges instead of ghosting for
    // 300 frames. HEAD hard-reset to 1 spp every 300 frames; the horizon is now a
    // bounded exponential average (no pop), and it shortens while the pointer
    // light is held so the moving light is visible within about half a second.
    let nPrev = floor(max(prev.a, 0.0));
    let fpPrev = clamp(fract(max(prev.a, 0.0)) / FP_SCALE, 0.0, 1.0);
    let fpNow = sourceFingerprint(uv, texel, dot(src.rgb, vec3<f32>(0.299, 0.587, 0.114)));
    let changed = smoothstep(0.025, 0.10, abs(fpNow - fpPrev));
    let horizon = select(MAX_HISTORY, HELD_HISTORY, u.zoom_config.w > 0.5);
    let sampleCount = min(floor(nPrev * (1.0 - changed)), horizon - 1.0);

    // Ray angle: white noise as at HEAD (a low-discrepancy angle sequence was tried and
    // measured: no convergence gain, the integrand is too rough). The seed also advances
    // with time because sampleCount is clamped at the horizon once history saturates.
    let seq = sampleCount + floor(max(time, 0.0) * 60.0);
    let jitter = hash22(vec2<f32>(gid.xy) + vec2<f32>(seq * 1.618, seq * 2.618));
    let angle = jitter.x * 6.28318530718;
    // ── Idea 1: stratified march lattice (jittered step start) ──
    // The marcher quantises the hit distance to its 2 px step. At HEAD the converged
    // picture therefore prints concentric rings on every disc/edge (white-noise speckle
    // hides them for the first seconds). jitter.y offsets the step lattice per sample
    // (see marchToEdge) so the quantisation averages out.
    let latticeSeed = jitter.y;
    var rayDir = vec2<f32>(cos(angle), sin(angle));

    // Mouse attracts light sources
    let mousePos = u.zoom_config.yz;
    if (u.zoom_config.w > 0.5) {
        let toMouse = mousePos - uv;
        rayDir = mix(rayDir, normalize(toMouse + 1e-6), 0.3);
    }

    var radiance = vec3<f32>(0.0);
    var throughput = vec3<f32>(1.0);
    var pos = uv;

    for (var bounce: i32 = 0; bounce < maxBounces; bounce = bounce + 1) {
        let hit = marchToEdge(pos, rayDir, texel, 32, edgeThreshold, fract(latticeSeed + f32(bounce) * 0.381966));

        if (!hit.hit) {
            // Sky / background contribution
            let bgColor = textureSampleLevel(readTexture, u_sampler, pos + rayDir * 0.1, 0.0).rgb;
            radiance += throughput * bgColor * 0.3;
            break;
        }

        // ── Idea 2: hit-distance falloff (§12.2F soft inverse-square, 2D law) ──
        // marchToEdge already found how far the hit is; HEAD weighted a hit 2 px
        // away and 64 px away identically. 1/d with a core radius R0, normalised
        // at the mean hit distance (exposure kept) and clamped (no contact blow-out).
        let hitPx = length((hit.pos - pos) * res);
        let falloff = clamp((FALL_REF + FALL_R0) / (hitPx + FALL_R0), 0.45, 1.25);

        // Sample color at hit point
        let hitColor = textureSampleLevel(readTexture, u_sampler, hit.pos, 0.0).rgb;
        radiance += throughput * hitColor * 0.4 * radianceScale * falloff;
        throughput *= hitColor * 0.6;

        // Russian roulette termination
        let rrProb = max(throughput.r, max(throughput.g, throughput.b));
        if (rrProb < 0.01) { break; }
        let rrRand = hash11(sampleCount + f32(bounce) * 7.31 + time);
        if (rrRand > rrProb) { break; }
        throughput /= rrProb;

        // Bounce with roughness perturbation
        let reflected = reflect(rayDir, hit.normal);
        let roughJitter = hash22(hit.pos * 100.0 + vec2<f32>(f32(bounce))) - 0.5;
        rayDir = normalize(reflected + roughJitter * roughness * 2.0);
        pos = hit.pos + hit.normal * texel * 2.0;
    }

    // Temporal accumulation: running mean over the kept samples. A kept count of 0
    // (first frame / full rejection) takes the new sample outright.
    let newCount = sampleCount + 1.0;
    let newAccum = select(mix(prev.rgb, radiance, 1.0 / newCount), radiance, sampleCount < 0.5);

    // A = raw accumulation (HDR, never ACES'd); the fraction of a carries the fingerprint.
    textureStore(dataTextureA, gid.xy, vec4<f32>(newAccum, newCount + fpNow * FP_SCALE));

    // Tone-map for display; alpha = source coverage united with convergence.
    let display = toneMapACES(max(newAccum, vec3<f32>(0.0)));
    let alpha = clamp(src.a + (1.0 - src.a) * (newCount / MAX_HISTORY), 0.0, 1.0);
    textureStore(writeTexture, gid.xy, vec4<f32>(display, alpha));
    let depth_in = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth_in, 0.0, 0.0, 0.0));
}
