// ═══════════════════════════════════════════════════════════════════
//  Radiating Haze
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-09, 2026-11-15
//  Ideas: neighbor-bleed corona; mouse-origin waves; source-hue halo gather (energy-conserving bloom, §12.2F); outward-advected persistence (native)
//  Rescue: ring frequency 15 -> 80 rad/uv (HEAD fitted 0.37 of a wavelength inside the aura disc, so no ring was ever resolved)
//  A packing: persist scalar in A.r, A.g aura (halo included), A.b strongMask, A.a hard 1.0. Display ACES RGB.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    var p = mix(vec4<f32>(c.bg, K.wz), vec4<f32>(c.gb, K.xy), step(c.b, c.g));
    let q = mix(vec4<f32>(p.xyw, c.r), vec4<f32>(c.r, p.yzx), step(p.x, c.r));
    let d = q.x - min(q.w, q.y);
    let e = 1.0e-10;
    return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s;
    let h6 = h * 6.0;
    let x = c * (1.0 - abs(fract(h6) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h6 < 1.0) { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(v - c);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn satOf(uv: vec2<f32>) -> f32 {
    let c = textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    return rgb2hsv(c).y;
}

// The same "strong colour" rule main() applies to the pixel itself (neutral = low sat, dark, or brown band),
// so the halo taps agree with the mask: browns, greys and blacks never emit. Hue is only needed for the
// brown band (0.08 < h < 0.15), which is reachable only with R the max channel and G >= B, where
// h = (g - b) / (6 d): so the band test is (g - b) / d in (0.48, 0.9), with no full rgb2hsv per tap.
fn strongOf(c: vec3<f32>, satThresh: f32) -> f32 {
    let mx = max(c.r, max(c.g, c.b));
    let d = mx - min(c.r, min(c.g, c.b));
    let sat = d / (mx + 1.0e-10);
    let gb = (c.g - c.b) / (d + 1.0e-10);
    let brown = (c.r >= mx) && (gb > 0.48) && (gb < 0.9) && (sat < 0.5);
    let neutral = (sat < satThresh) || (mx < 0.15) || brown;
    return select(1.0, 0.0, neutral);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    let pixel = vec2<i32>(gid.xy);
    if (pixel.x >= i32(resolution.x) || pixel.y >= i32(resolution.y)) { return; }

    let uv = (vec2<f32>(pixel) + 0.5) / resolution;
    let time = u.config.x;
    let texel = 1.0 / resolution;
    let dims = vec2<i32>(textureDimensions(dataTextureC));
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;

    let src4 = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let src = src4.rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let speed = u.zoom_params.x * 0.5 * (1.0 + bass * 0.25);
    let intensity = u.zoom_params.y;
    let satThresh = u.zoom_params.z * 0.4 + 0.2;
    let radius = u.zoom_params.w * 0.15;
    let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let hueBias = mids * 0.12;
    let pulseSpd = 0.35 + bass * 0.4;

    let hsv = rgb2hsv(src);
    let isNeutral = (hsv.y < satThresh) || (hsv.z < 0.15) ||
                    ((hsv.x > 0.08) && (hsv.x < 0.15) && (hsv.y < 0.5));

    var strongMask = select(0.0, 1.0, !isNeutral);
    // Idea 1 — neighbor-bleed corona
    let nSat = satOf(uv + vec2<f32>(texel.x, 0.0)) + satOf(uv - vec2<f32>(texel.x, 0.0))
             + satOf(uv + vec2<f32>(0.0, texel.y)) + satOf(uv - vec2<f32>(0.0, texel.y));
    let bleed = smoothstep(satThresh, satThresh + 0.25, nSat * 0.25);
    strongMask = max(strongMask, bleed * 0.65);

    // Idea 2 — waves from the cursor, not always screen center
    let origin = mix(vec2<f32>(0.5), mouse, 0.85);
    let dist = length(uv - origin);
    // ── Rescue 1: ring frequency ──────────────────────────────────────
    // HEAD used 15 rad/uv, but the aura is clipped to dist < radius + 0.08 (~0.155 uv at the saved
    // default): 0.37 of a wavelength fits, so the "waves" were one pulsing disc and no ring was ever
    // resolved. 80 rad/uv fits two rings in the default disc. Disc size, front speed (speed uv/s) and
    // the smoothstep mask are untouched.
    let wave = sin((dist - time * speed) * 80.0) * 0.5 + 0.5;
    let waveMask = smoothstep(0.2, 0.8, wave) * smoothstep(radius + 0.08, 0.0, dist);
    let depthGain = mix(1.0, depth, 0.45);
    let aura = strongMask * waveMask * depthGain * intensity;

    let auraHue = fract(hsv.x + hueBias + time * pulseSpd * 0.02);
    let auraCol = hsv2rgb(auraHue, 0.9, 1.0);

    // ── Idea 3 (batch-38 card idea 1): source-hue halo gather (energy-conserving bloom, §12.2F) ──
    // `strongMask` only ever lit the strong pixel itself (+ a 1-texel bleed), so a haze "radiating" from
    // coloured objects never left their footprint. An 8-tap golden-angle disc (radius 1.6 % of the height,
    // so it looks the same at every size) gathers the strong colours around each pixel: NEUTRAL pixels
    // beside a coloured object receive that object's hue as aura, and the object's rim gives up a little
    // light for it (energy moves rather than appears). Same neutral rule as the pixel itself via strongOf().
    // Both outputs are proportional to waveMask, which is exactly 0 outside the aura disc and in the gaps
    // between rings, so the gather is skipped there (same picture, ~13x fewer pixels pay for 8 taps).
    var haloAura = 0.0;
    var rimDonate = 0.0;
    var haloCol = vec3<f32>(0.0);
    if (waveMask > 0.002) {
        let haloR = 0.016 * resolution.y;
        var haloSum = 0.0;
        var haloFall = 0.0;
        var haloRgb = vec3<f32>(0.0);
        // golden-angle spiral by incremental rotation (first tap at 0.5 x 2.39996323 rad), no per-tap trig
        var dir = vec2<f32>(0.3623749, 0.9320324);
        let rot = vec2<f32>(-0.7373689, 0.6754903);
        for (var k = 0; k < 8; k = k + 1) {
            let fk = f32(k) + 0.5;
            let rn = sqrt(fk * 0.125);
            let tuv = clamp(uv + dir * (haloR * rn) / resolution, vec2<f32>(0.0), vec2<f32>(1.0));
            dir = vec2<f32>(dir.x * rot.x - dir.y * rot.y, dir.x * rot.y + dir.y * rot.x);
            let tc = textureSampleLevel(readTexture, u_sampler, tuv, 0.0).rgb;
            let fo = 1.0 - 0.45 * rn;
            let w = strongOf(tc, satThresh) * fo;
            haloSum += w;
            haloFall += fo;
            haloRgb += tc * w;
        }
        let haloW = haloSum / max(haloFall, 1e-4);
        haloCol = hsv2rgb(fract(rgb2hsv(haloRgb / max(haloSum, 1e-4)).x + hueBias + time * pulseSpd * 0.02), 0.9, 1.0);
        haloAura = (1.0 - strongMask) * haloW * waveMask * depthGain * intensity * 1.3;
        rimDonate = strongMask * (1.0 - haloW) * waveMask * intensity * 0.25;
    }
    let auraTot = aura + haloAura;

    // ── Idea 4 (batch-38 card idea 2): outward-advected persistence (native) ──
    // `prev` used to be read in place, so a fading ring faded where it was. Reading the history from the
    // pixel one step TOWARD the cursor makes the persisted trail drift away from it with the wave
    // (0.7x the ring front speed, assuming 60 fps). Exact textureLoads at texel centres, hand-lerped
    // (the drift is a fraction of a pixel per frame at small sizes); no filtering sampler on C.
    let toPix = uv - origin;
    let dirUV = toPix / max(length(toPix), 1e-4);
    let srcPos = vec2<f32>(pixel) - dirUV * (speed * 0.7 / 60.0) * resolution;
    let hiPx = dims - vec2<i32>(1);
    var prev = 0.0;
    // Most of the frame holds no trail: probe the nearest texel and only pay for the 4-tap lerp where
    // there is history to move.
    if (textureLoad(dataTextureC, clamp(vec2<i32>(round(srcPos)), vec2<i32>(0), hiPx), 0).r > 0.0005) {
        let base = floor(srcPos);
        let fr = srcPos - base;
        let p0 = vec2<i32>(base);
        let c00 = textureLoad(dataTextureC, clamp(p0, vec2<i32>(0), hiPx), 0).r;
        let c10 = textureLoad(dataTextureC, clamp(p0 + vec2<i32>(1, 0), vec2<i32>(0), hiPx), 0).r;
        let c01 = textureLoad(dataTextureC, clamp(p0 + vec2<i32>(0, 1), vec2<i32>(0), hiPx), 0).r;
        let c11 = textureLoad(dataTextureC, clamp(p0 + vec2<i32>(1, 1), vec2<i32>(0), hiPx), 0).r;
        prev = mix(mix(c00, c10, fr.x), mix(c01, c11, fr.x), fr.y);
    }
    let persist = max(prev * 0.92, auraTot);
    textureStore(dataTextureA, pixel, vec4<f32>(persist, auraTot, strongMask, 1.0));

    var hdr = src * (1.0 - rimDonate) + auraCol * aura + haloCol * haloAura;
    // Trail weight 0.3 -> 0.4: the drifting trail (Idea 4) was below visibility at HEAD's weight.
    hdr = 1.0 - (1.0 - hdr) * (1.0 - vec3<f32>(persist * 0.4));
    let mapped = aces(max(hdr, vec3<f32>(0.0)));
    let alpha = clamp(src4.a * 0.4 + auraTot * 0.45 + persist * 0.25, 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(mapped, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
