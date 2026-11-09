// ═══════════════════════════════════════════════════════════════════
//  Prismatic Feedback Loop
//  Category: interactive-mouse
//  Features: advanced-alpha, prismatic, feedback, chromatic, multi-pass,
//            mouse-driven, audio-reactive, depth-aware
//  Complexity: High
//  Upgraded: 2026-07-30, 2026-11-09 (Batch 18 - Algorithmist: honest slider rewiring,
//            click prism bursts, glow term, feedback blowout guard)
//  Batch 68: exact raw accumulation, sprung held deformation, ACES display
//  Ideas: prism echo (history re-read through the same prism, compounding
//         fringes); Cauchy-weighted taps (§12.2F: blue refracts harder than red)
//  Rescue: dead extraBuffer[133..138] spring -> first-order glide in A(0,0)
//  A packing: raw accumulated RGBA (C read as colour+alpha); texel (0,0) =
//             (glide.xy, 7, fract(time)), masked as zero when C is read
//
//  Slider contract (ids/defaults are the saved-preset contract - the WGSL
//  now honors the LABELS, not the legacy mislabeled roles):
//    x = "Feedback"         -> temporal feedback mix amount
//    y = "Blur Radius"      -> prism tap spread magnitude (soften/blur)
//    z = "Glow Intensity"   -> glow lift on the accumulated trails
//    w = "Chromatic Spread" -> r/b separation angle fan-out
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Feedback, y=BlurRadius, z=GlowIntensity, w=ChromaticSpread

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

// Ripple burst lifetime (seconds) - clicks shatter the prism locally.
const RIPPLE_LIFE: f32 = 1.5;

// Marker in A(0,0).z that says "this texel holds the cursor glide, not colour".
const GLIDE_MARK: f32 = 7.0;

// Fixed trail accumulation rate for accumulativeAlpha() (the x slider
// now honestly drives the feedback mix, per its "Feedback" label).
const ACCUM_RATE: f32 = 0.5;

// ═══ ADVANCED ALPHA FUNCTIONS ═══

// Mode 3: Accumulative Alpha
fn accumulativeAlpha(
    newColor: vec3<f32>,
    newAlpha: f32,
    prevColor: vec3<f32>,
    prevAlpha: f32,
    accumulationRate: f32
) -> vec4<f32> {
    let accumulatedAlpha = prevAlpha * (1.0 - accumulationRate * 0.1) + newAlpha * accumulationRate;
    let totalAlpha = min(accumulatedAlpha, 1.0);
    let blendFactor = select(newAlpha * accumulationRate / totalAlpha, 0.0, totalAlpha < 0.001);
    let color = mix(prevColor, newColor, blendFactor);
    return vec4<f32>(color, totalAlpha);
}

// Rotate a 2D vector by `angle` radians.
fn rot2(v: vec2<f32>, angle: f32) -> vec2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

// ── Rescue R1: cursor glide in A texel (0,0) ─────────────────────────
// extraBuffer[133..] is re-uploaded zeroed every frame, so HEAD's spring could never
// persist. State = A(0,0) = (glide.x, glide.y, GLIDE_MARK, fract(time)); every pixel
// reads the same C texel and integrates the same step, only pixel (0,0) stores it.
// First-order glide; the lag vector (raw - glide) is the velocity proxy.
fn glideStep(st: vec4<f32>, raw: vec2<f32>, time: f32, rate: f32) -> vec2<f32> {
    let ok = abs(st.z - GLIDE_MARK) < 0.01 && st.w >= 0.0 && st.w < 1.0;
    let dt = clamp(fract(time - st.w), 0.001, 0.05);
    let g = st.xy + (raw - st.xy) * (1.0 - exp(-rate * dt));
    let snapped = select(g, raw, length(raw - g) < 0.003);
    return select(raw, snapped, ok);
}

// History load, exact, with texel (0,0) masked (it holds the glide state, not colour).
fn loadHist(c: vec2<i32>, hi: vec2<i32>) -> vec4<f32> {
    let cc = clamp(c, vec2<i32>(0), hi);
    let v = textureLoad(dataTextureC, cc, 0);
    return select(vec4<f32>(0.0), v, any(cc != vec2<i32>(0)));
}

// Exact 4-tap bilinear over the history (no filtering sampler on rgba32float).
fn histBilinear(uvp: vec2<f32>, res: vec2<f32>, hi: vec2<i32>) -> vec4<f32> {
    let pp = clamp(uvp, vec2<f32>(0.0), vec2<f32>(1.0)) * res - vec2<f32>(0.5);
    let b = floor(pp);
    let f = pp - b;
    let c0 = vec2<i32>(b);
    let a = loadHist(c0, hi);
    let bb = loadHist(c0 + vec2<i32>(1, 0), hi);
    let c = loadHist(c0 + vec2<i32>(0, 1), hi);
    let d = loadHist(c0 + vec2<i32>(1, 1), hi);
    return mix(mix(a, bb, f.x), mix(c, d, f.x), f.y);
}

// Cauchy n(lambda) = 1 + B/lambda^2 at 650/550/450 nm, relative to green: (<1, 1, >1).
fn cauchyScale(bCoef: f32) -> vec3<f32> {
    let lam = vec3<f32>(0.650, 0.550, 0.450);
    let n = vec3<f32>(1.0) + vec3<f32>(bCoef) / (lam * lam);
    return n / n.y;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(i32(global_id.x), i32(global_id.y));
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let aspectVec = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);

    // ── Honest slider wiring (labels now match behavior) ─────────────
    // x "Feedback": temporal mix toward the previous frame. Guarded to
    // [0,1] so the feedback loop can never blow out.
    let feedbackMix = clamp(u.zoom_params.x, 0.0, 1.0);
    // y "Blur Radius": prism tap spread magnitude. Default 1 reproduces
    // the legacy ~0.1 offset scale; reads as a chromatic soften/blur.
    let prismSpread = u.zoom_params.y * 0.1 * (1.0 + bass * 0.4 + treble * 0.3);
    // z "Glow Intensity": brightness lift applied to the accumulated
    // trails on output. Exactly 0 when the slider is 0.
    let glowIntensity = max(u.zoom_params.z, 0.0) * (1.0 + mids * 0.3);
    // w "Chromatic Spread": angular fan-out between the r and b taps.
    // Tiny default (0.02) = subtle fringe, matching its default.
    let chromaFan = clamp(u.zoom_params.w, 0.0, 0.2) * PI;

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let historyDims = vec2<i32>(textureDimensions(dataTextureC));
    let hi = historyDims - vec2<i32>(1);
    let prev = loadHist(coord, hi);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // ── Rescue R1: glide (HEAD omega 10) + lag vector as the velocity proxy ──
    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let omega = 10.0;
    let glideState = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
    let prismFocus = glideStep(glideState, rawMouse, time, omega);
    let springVel = (rawMouse - prismFocus) * omega;

    // ── Prismatic chromatic separation ───────────────────────────────
    // The legacy z-slider rotation is now a slow constant drift so the
    // prism keeps breathing without stealing a slider.
    let focusDelta = (uv - prismFocus) * aspectVec;
    let heldWarp = smoothstep(0.65, 0.0, length(focusDelta)) * u.zoom_config.w;
    let centered = uv - 0.5 + (uv - prismFocus) * heldWarp * 0.18 + springVel * heldWarp * 0.08;
    let drift = rot2(centered, time * 0.1);

    // Chromatic fan-out: r and b taps rotate apart by ±chromaFan.
    let rDir = rot2(drift, chromaFan);
    let bDir = rot2(drift, -chromaFan);

    // Depth-aware attenuation: distant pixels smear less.
    let depthScale = mix(1.0, 0.35, clamp(depth, 0.0, 1.0));

    var rOffset = rDir * prismSpread * depthScale;
    var bOffset = bDir * prismSpread * depthScale;

    // ── Click prism bursts ───────────────────────────────────────────
    // Each live ripple adds a decaying radial chromatic kick centered on
    // its click point, fading over ~RIPPLE_LIFE seconds.
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < RIPPLE_LIFE) {
            let toPixel = (uv - ripple.xy) * aspectVec;
            let dist = length(toPixel);
            // Radial falloff around the click, exponential time decay.
            let falloff = exp(-dist * 9.0) * exp(-age * (3.0 / RIPPLE_LIFE));
            // Kick direction points radially outward from the click.
            let kickDir = toPixel / max(dist, 1e-4);
            let kick = kickDir / aspectVec * falloff * 0.06;
            rOffset = rOffset + kick;
            bOffset = bOffset - kick;
        }
    }

    // ── Idea 2: Cauchy-weighted taps (§12.2F) ───────────────────────────
    // Blue refracts harder than red (n = A + B/lambda^2); G stays undeviated. Applies to the
    // live taps, click kicks and the echo below.
    let cz = cauchyScale(0.2);
    rOffset = rOffset * cz.x;
    bOffset = bOffset * cz.z;

    let rUV = clamp(uv + rOffset, vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv - bOffset, vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

    let prismColor = vec3<f32>(r, g, b);

    // ── Guarded temporal feedback ────────────────────────────────────
    // x slider mixes toward the previous frame; result clamped to [0,1]
    // so runaway feedback blowout is impossible.
    // ── Idea 1: prism echo ────────────────────────────────────────────
    // The history goes back through the same prism: R from C displaced with the red
    // tap, B from C displaced against the blue tap, G in place. Fringes compound frame
    // by frame; k scales with the Feedback slider so Feedback 0 is still HEAD's exact
    // freeze. The blend below is convex, so values stay in [0,1].
    let echoK = 0.3 * feedbackMix;
    let echoR = histBilinear(uv + rOffset * echoK, resolution, hi).r;
    let echoB = histBilinear(uv - bOffset * echoK, resolution, hi).b;
    let echo = vec3<f32>(echoR, prev.g, echoB);
    let blended = clamp(
        mix(echo, prismColor, feedbackMix),
        vec3<f32>(0.0), vec3<f32>(1.0)
    );

    let brightness = dot(blended, vec3<f32>(0.299, 0.587, 0.114));
    let effectEnergy = clamp(brightness * feedbackMix + heldWarp * 0.35, 0.0, 1.0);
    let newAlpha = clamp(baseColor.a + (1.0 - baseColor.a) * effectEnergy, 0.0, 1.0);

    // dataTextureA is accumulation state: store the raw accumulated
    // value (capped only by accumulativeAlpha itself) - no tonemap, no
    // glow baked in - so the A-write / C-read loop stays symmetric and
    // stable across frames.
    let accumulated = accumulativeAlpha(blended, newAlpha, prev.rgb, prev.a, ACCUM_RATE);
    // Texel (0,0) stores the glide state (the display pixel below is still real).
    let isOrigin = all(coord == vec2<i32>(0));
    textureStore(dataTextureA, coord,
        select(accumulated, vec4<f32>(prismFocus, GLIDE_MARK, fract(time)), isOrigin));

    // ── Glow term (output only) ──────────────────────────────────────
    // Brightness lift of the accumulated trails: soft-knee luminance of
    // the trail feeds back as an additive halo. Exactly 0 at glow 0.
    let trailLum = max(dot(accumulated.rgb, vec3<f32>(0.299, 0.587, 0.114)) - 0.25, 0.0);
    let glow = trailLum * trailLum * glowIntensity * 0.6;
    let outColor = acesToneMap(max(accumulated.rgb + accumulated.rgb * glow, vec3<f32>(0.0)));

    textureStore(writeTexture, global_id.xy, vec4<f32>(outColor, accumulated.a));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
