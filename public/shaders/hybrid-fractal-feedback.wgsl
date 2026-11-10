// ═══════════════════════════════════════════════════════════════════
//  Hybrid Fractal Feedback
//  Category: hybrid
//  Features: advanced-alpha, fractal, feedback, hybrid
//  Complexity: High
//  Upgraded: 2026-05-23, 2026-11-10
//  upgraded-rgba
//  Ideas: smooth iteration count + orbit-trap veins (§12.2E); video-feedback zoom-rotate of the exact-C history about the Julia origin (native)
//  A packing: accumulated pre-ACES RGBA (read back as C colour/alpha accumulation); ACES only on the fractal term of writeTexture. Texels (0,0) = (sprung pointer.xy, velocity.xy) and (1,0) = (fract(lastTime), 0, 0, 0.7371 sentinel) are STATE, not pixels (top-left corner; their history read is masked).
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Zoom, y=Feedback, z=RGBDelay, w=ColorCycle

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;
const PHI: f32 = 1.61803398874989484820;
const SENT: f32 = 0.7371;

// Idea 1 tuning: orbit-trap circle (Julia-plane radius) and vein sharpness.
const TRAP_R: f32 = 0.55;
const VEIN_K: f32 = 6.0;
const VEIN_ON: f32 = 1.0;
// Idea 2 tuning. The drift per frame is proportional to the alpha the history sheds per frame
// (accumulationRate·0.08, the same term accumulativeAlpha uses), so a trail's total travel over its
// lifetime is constant: ~FB_ZOOM of radius and ~FB_SPIN radians at every Feedback Strength and at
// every frame rate, instead of a long-lived trail (Feedback 0) washing the whole frame.
const FB_ZOOM: f32 = 0.16;
const FB_SPIN: f32 = 0.25;
const FB_ON: f32 = 1.0;

// ═══ ADVANCED ALPHA FUNCTIONS ═══

// Mode 3: Accumulative Alpha
fn accumulativeAlpha(
    newColor: vec3<f32>,
    newAlpha: f32,
    prevColor: vec3<f32>,
    prevAlpha: f32,
    accumulationRate: f32
) -> vec4<f32> {
    let accumulatedAlpha = prevAlpha * (1.0 - accumulationRate * 0.08) + newAlpha * accumulationRate;
    let totalAlpha = min(accumulatedAlpha, 1.0);
    let blendFactor = select(newAlpha * accumulationRate / totalAlpha, 0.0, totalAlpha < 0.001);
    let color = mix(prevColor, newColor, blendFactor);
    return vec4<f32>(color, totalAlpha);
}

// Complex multiplication
fn complexMul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Exact history texel: clamped, and the two A state texels read as empty history.
fn histTexel(p: vec2<i32>, maxP: vec2<i32>) -> vec4<f32> {
    let q = clamp(p, vec2<i32>(0), maxP);
    let isState = q.y == 0 && q.x <= 1;
    return select(textureLoad(dataTextureC, q, 0), vec4<f32>(0.0), isState);
}

// Bilinear history at a fractional position in texel units (texel i has its centre at i + 0.5),
// built from four exact loads — C is rgba32float, no filtering sampler. At pos = pixel + 0.5 it is
// one exact texel. The red / blue delay taps sit a fraction of a texel either side of that centre
// (|delay| <= 0.006 uv), so instead of two more bilerps (8 more loads) they are read off the SAME
// four texels: a bilinear field is v + gx·dx + gy·dy + cross·dx·dy inside its cell, which is exact
// there, and clamped to the four texels' range if the delay reaches past the cell.
struct HistTaps {
    g: vec4<f32>,   // the bilerp at pos (RGBA)
    r: f32,         // red  channel at pos + dPx
    b: f32,         // blue channel at pos − dPx
}

fn histTaps(pos: vec2<f32>, maxP: vec2<i32>, dPx: vec2<f32>) -> HistTaps {
    let p0f = floor(pos - 0.5);
    let f = pos - 0.5 - p0f;
    let p0 = vec2<i32>(p0f);
    let s00 = histTexel(p0, maxP);
    let s10 = histTexel(p0 + vec2<i32>(1, 0), maxP);
    let s01 = histTexel(p0 + vec2<i32>(0, 1), maxP);
    let s11 = histTexel(p0 + vec2<i32>(1, 1), maxP);
    let v = mix(mix(s00, s10, f.x), mix(s01, s11, f.x), f.y);
    let gx = mix(s10 - s00, s11 - s01, f.y);
    let gy = mix(s01 - s00, s11 - s10, f.x);
    let cr = (s00 - s10 - s01 + s11) * (dPx.x * dPx.y);
    let lo = min(min(s00, s10), min(s01, s11));
    let hi = max(max(s00, s10), max(s01, s11));
    let r = v.r + gx.r * dPx.x + gy.r * dPx.y + cr.r;
    let b = v.b - gx.b * dPx.x - gy.b * dPx.y + cr.b;
    return HistTaps(v, clamp(r, lo.r, hi.r), clamp(b, lo.b, hi.b));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(i32(global_id.x), i32(global_id.y));
    let maxP = vec2<i32>(resolution) - vec2<i32>(1);
    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let rawMouse = u.zoom_config.yz;

    // Honor the JSON control contract. These mappings were previously shifted:
    // every label drove a different internal behavior.
    let zoomControl = u.zoom_params.x;
    let feedbackControl = u.zoom_params.y;
    let rgbDelay = u.zoom_params.z;
    let colorCycle = u.zoom_params.w;
    let accumulationRate = mix(0.15, 0.50, feedbackControl);
    let fractalIter = 45;
    let zoom = 1.0 + zoomControl * 1.5;
    let feedback = mix(0.15, 0.65, feedbackControl);

    // ── Sprung Julia parameter, persisted in two A texels ───────────
    // HEAD kept this critically damped spring (omega 6) in extraBuffer[133..138], which the renderer
    // re-uploads as zeros every frame, so it never persisted and the Julia c followed the raw pointer.
    // Texel (0,0) = (pos.xy, vel.xy), texel (1,0) = (fract(lastTime), 0, 0, SENT). Every thread
    // integrates the same step from the stored state; the sentinel guards the first frame / inherited C.
    let st0 = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
    let st1 = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
    let stateOk = abs(st1.w - SENT) < 0.001;
    var mouse = select(rawMouse, st0.xy, stateOk);
    var mouseVel = select(vec2<f32>(0.0), st0.zw, stateOk);
    let springDt = select(0.016, clamp(fract(time - st1.x), 0.001, 0.05), stateOk);
    let omega = 6.0;
    mouseVel += ((rawMouse - mouse) * (omega * omega) - mouseVel * (2.0 * omega)) * springDt;
    mouse += mouseVel * springDt;
    // rgba16float rest-snap: a spring stored at half precision stalls just short of the pointer.
    let settled = all(abs(rawMouse - mouse) < vec2<f32>(0.004)) && length(mouseVel) < 0.06;
    mouse = select(mouse, rawMouse, settled);
    mouseVel = select(mouseVel, vec2<f32>(0.0), settled);

    let current = textureLoad(readTexture, coord, 0);

    // ── Idea 2: video-feedback transform (native) ───────────────────
    // HEAD read the history at the SAME uv, so the accumulated trail never moved. A real
    // video-feedback loop re-films its own screen slightly zoomed and turned each frame: the
    // history is read at pivot + R(θ)·(uv − pivot)·s (s < 1 flows outward, θ spins), in aspect-
    // correct space, so old fractal copies stream out of the Julia origin as a spiral tunnel.
    // The pivot is the Julia origin, leaning a little toward the sprung pointer. Feedback Strength
    // keeps its role (how much history survives); the transform only moves it, by an amount that
    // follows how fast the history is shed (see FB_ZOOM).
    let aspect = resolution.x / max(resolution.y, 0.001);
    let aspectVec = vec2<f32>(aspect, 1.0);
    let pivot = vec2<f32>(0.5) + (mouse - vec2<f32>(0.5)) * 0.3;
    let histLoss = accumulationRate * 0.08;
    let fbScale = 1.0 - FB_ZOOM * histLoss * FB_ON;
    let fbAng = FB_SPIN * histLoss * FB_ON;
    let fbC = cos(fbAng);
    let fbS = sin(fbAng);
    let rel = (uv - pivot) * aspectVec;
    let relT = vec2<f32>(rel.x * fbC - rel.y * fbS, rel.x * fbS + rel.y * fbC) * fbScale;
    let uvHist = pivot + relT / aspectVec;

    // Clicks locally kick the complex Julia parameter at normalized ripple
    // positions rather than replacing the persistent feedback state.
    var clickC = vec2<f32>(0.0);
    var clickGlow = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri++) {
        let rp = u.ripples[ri];
        let age = time - rp.z;
        let safeAge = max(age, 0.0);
        let live = step(0.0, age) * (1.0 - step(1.8, age));
        let rd = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
        let local = (1.0 - smoothstep(0.0, 0.45 + safeAge * 0.08, rd)) * exp(-safeAge * 1.5) * live;
        clickC += (rp.xy - 0.5) * local * 0.35;
        clickGlow = max(clickGlow, local);
    }

    // Julia fractal — mouse steers c-parameter, bass adds breathing
    let cBase = vec2<f32>(cos(time * 0.2) * 0.7, sin(time * 0.3) * 0.3);
    let cMouse = (mouse - 0.5) * 1.4;
    let c = mix(cBase, cMouse, 0.5) * (1.0 + bass * 0.1) + clickC;
    // The Julia plane is square: widen x by the aspect so the set is not stretched on 16:9.
    let z = (uv - 0.5) * aspectVec * zoom * 2.0;

    // ── Idea 1: smooth iteration count + orbit-trap veins (§12.2E) ──
    // HEAD kept only the integer escape index (banded; every bounded point was the same flat 44/45).
    // The loop below is the same z² + c, 45 iterations; it now keeps running to |z| = 8 so the
    // escape can be smoothed — nu = n − log2(log|z| / log 2) is the continuous version of HEAD's
    // radius-2 index — and records an orbit trap, the closest approach of the orbit to a circle in
    // the Julia plane (|r² − R²| ≈ 2R·|r − R| near the ring: no sqrt per iteration). Bounded
    // points (HEAD's flat blob) get veins from the trap.
    var zCurrent = z;
    var trap = 1.0e9;
    var smoothN = f32(fractalIter - 1);
    for (var i: i32 = 0; i < fractalIter; i++) {
        zCurrent = complexMul(zCurrent, zCurrent) + c;
        let r2 = dot(zCurrent, zCurrent);
        trap = min(trap, abs(r2 - TRAP_R * TRAP_R));
        if (r2 > 64.0) {
            let lz = 0.5 * log(r2);
            smoothN = clamp(f32(i) - log2(max(lz / 0.6931472, 1.0e-3)), 0.0, f32(fractalIter - 1));
            break;
        }
    }

    let fractalValue = smoothN / f32(fractalIter);
    let trapD = trap * (0.5 / TRAP_R);
    let vein = exp(-trapD * VEIN_K);
    let veinShade = mix(1.0, 0.50 + 0.50 * vein, VEIN_ON);
    // Bounded palette with per-region audio shimmer. plasmaBuffer is a single vec4 (HEAD indexed
    // bins 1..8 out of range, which read as zero); each 4×4 region now listens to one of bass/mids/treble.
    let palettePhase = fract(fractalValue * PHI + trapD * 0.35 * VEIN_ON + time * mix(0.02, 0.18, colorCycle));
    let palette = 0.55 + 0.45 * cos(TAU * (palettePhase + vec3<f32>(0.00, 0.33, 0.67)));
    let regionIdx = (u32(floor(uv.x * 4.0)) + u32(floor(uv.y * 4.0)) * 3u) % 3u;
    let regionVoice = select(select(treble, mids, regionIdx == 1u), bass, regionIdx == 0u);
    let fractalColor = palette * fractalValue * veinShade * (0.7 + bass * 0.35 + mids * 0.15 + regionVoice * 0.2 + clickGlow * 0.2);

    // The RGB-delay slider now samples distinct temporal offsets for red/blue.
    let delayAngle = time * 0.25 + fractalValue * TAU;
    let delayVec = vec2<f32>(cos(delayAngle) / aspect, sin(delayAngle)) * rgbDelay * (0.002 + treble * 0.004);
    let taps = histTaps(uvHist * resolution, maxP, delayVec * resolution);
    let prev = taps.g;
    let delayedPrev = vec3<f32>(taps.r, prev.g, taps.b);
    let blended = mix(delayedPrev, fractalColor, feedback);
    let newAlpha = fractalValue;

    let accumulated = accumulativeAlpha(blended, newAlpha, prev.rgb, prev.a, accumulationRate);

    // A keeps the pre-ACES accumulation; texels (0,0)/(1,0) carry the spring state instead.
    var aOut = accumulated;
    if (global_id.y == 0u && global_id.x == 0u) { aOut = vec4<f32>(mouse, mouseVel); }
    if (global_id.y == 0u && global_id.x == 1u) { aOut = vec4<f32>(fract(time), 0.0, 0.0, SENT); }
    textureStore(dataTextureA, coord, aOut);

    // Blend feedback over current input, preserving base transparency. ACES tone-maps the fractal
    // term only; the photo underneath is already display-referred.
    let blend = accumulated.a;
    let finalColor = mix(current.rgb, acesToneMap(max(accumulated.rgb, vec3<f32>(0.0))), blend);
    let finalAlpha = mix(current.a, 1.0, blend * 0.7);
    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, finalAlpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthOut = clamp(depth - fractalValue * 0.035 - clickGlow * 0.02, 0.0, 1.0);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depthOut, 0, 0, 0.0));
}
