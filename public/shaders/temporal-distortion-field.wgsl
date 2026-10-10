// ═══════════════════════════════════════════════════════════════════
//  Temporal Distortion Field
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba, temporal-ghosting,
//            fbm-warp, depth-field-modulation, chromatic-time-lag
//  Complexity: High
//  Upgraded: 2026-10-05
//  Ideas: 1) true stasis bubble (held field outputs the held C frame);
//         2) real ghost taps (Ghost Count = 1..5 decaying history taps along the warp);
//         3) past/present/future channels (R lags history, G live, B extrapolated);
//         4) horizon lensing (refractive ring from the gradient of the field edge)
//  A packing: ACES display RGBA (history reads decoded with acesInverse)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn acesInverse(yIn: vec3<f32>) -> vec3<f32> {
    let y = clamp(yIn, vec3<f32>(0.0), vec3<f32>(0.98));
    let qa = 2.43 * y - vec3<f32>(2.51);
    let qb = 0.59 * y - vec3<f32>(0.03);
    let disc = max(qb * qb - 4.0 * qa * (0.14 * y), vec3<f32>(0.0));
    return max((-qb - sqrt(disc)) / (2.0 * qa), vec3<f32>(0.0));
}

fn loadHistory(p: vec2<f32>, res: vec2<f32>) -> vec4<f32> {
    let ip = clamp(vec2<i32>(p * res), vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1));
    return textureLoad(dataTextureC, ip, 0);
}

fn fbmWarp(p_in: vec2<f32>, time: f32) -> vec2<f32> {
    var p = p_in;
    var v = vec2<f32>(0.0);
    var amp = 0.5;
    var freq = 1.0;
    for (var i: i32 = 0; i < 4; i = i + 1) {
        v += amp * vec2<f32>(
            sin(p.x * freq + time),
            cos(p.y * freq + time)
        );
        p = p * 1.8 + v * 0.3;
        amp *= 0.5;
        freq *= 2.0;
    }
    return v;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let pixel = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let aspectV = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);

    let freeze = f32(mouseDown > 0.5);
    let freezeAmount = u.zoom_params.x;
    let warpStrength = u.zoom_params.y;
    let ghostCount = u.zoom_params.z;
    let depthWeight = u.zoom_params.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Depth-aware field radius: closer objects are frozen closer to mouse
    // (aspect-correct distance so the bubble is round).
    let toMouse = (uv - mouse) * aspectV;
    let dM = length(toMouse);
    let fieldRadius = freezeAmount * (1.0 - depth * depthWeight * 0.6);
    let e0 = fieldRadius * 1.2;
    let e1 = fieldRadius * 0.8;
    let inField = smoothstep(e0, e1, dM);

    var warpUV = uv;
    var w = fbmWarp(uv * 3.0, time) * warpStrength * (1.0 + bass * 0.2);
    // Cap the peak warp (HEAD reached ~0.47 UV at default) without
    // touching the typical swing.
    let wLen = length(w);
    w = w * min(1.0, 0.3 / max(wLen, 1e-4));
    warpUV = warpUV + w * (1.0 - inField * freeze);

    // Idea 4: horizon lensing — the bubble edge refracts. d(inField)/d(dM)
    // of the smoothstep is 6t(1-t)/(e1-e0); push samples along the field
    // gradient so the horizon reads as a glass lip (faint while hovering).
    let tEdge = clamp((dM - e0) / min(e1 - e0, -1e-4), 0.0, 1.0);
    let edgeGrad = 6.0 * tEdge * (1.0 - tEdge);
    let radialDir = (toMouse / max(dM, 1e-4)) / aspectV;
    let lensAmt = edgeGrad * 0.016 * (0.35 + 0.65 * freeze) * step(0.001, fieldRadius);
    warpUV = warpUV - radialDir * lensAmt;

    // Chromatic time-lag splitting
    var rUV = warpUV;
    var gUV = warpUV;
    var bUV = warpUV;
    for (var i: i32 = 0; i < i32(ghostCount * 5.0 + 1.0); i = i + 1) {
        let lag = 0.02 * f32(i) * (1.0 + mids * 0.3);
        // R = past, G = present, B = future
        rUV = rUV - vec2<f32>(lag, 0.0);
        bUV = bUV + vec2<f32>(lag, 0.0);
    }

    rUV = clamp(rUV, vec2<f32>(0.0), vec2<f32>(1.0));
    gUV = clamp(gUV, vec2<f32>(0.0), vec2<f32>(1.0));
    bUV = clamp(bUV, vec2<f32>(0.0), vec2<f32>(1.0));

    var color = vec3<f32>(0.0);
    color.r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let gSample = textureSampleLevel(readTexture, u_sampler, gUV, 0.0);
    color.g = gSample.g;
    color.b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

    let prev = textureLoad(dataTextureC, pixel, 0);
    let prevLin = acesInverse(prev.rgb);

    // Idea 3: past / present / future channels. R leans on the history
    // (exponential lag), G stays live, B extrapolates live + k(live - past).
    // Both loops are contractive (gain 0.55 and -0.6), so they settle.
    let past = mix(color.r, prevLin.r, 0.55);
    let future = clamp(color.b + 0.6 * (color.b - prevLin.b), 0.0, 1.5);
    color = vec3<f32>(past, color.g, future);

    // Idea 2: real ghost taps — N = 1..5 history taps stepped back along
    // the warp vector, each fainter; Ghost Count picks N.
    let ghostN = 1 + i32(ghostCount * 4.0 + 0.5);
    let wDir = w / max(length(w), 1e-4);
    var ghostSum = vec3<f32>(0.0);
    var ghostW = 0.0;
    for (var k: i32 = 1; k <= 5; k = k + 1) {
        if (k > ghostN) { break; }
        let fk = f32(k);
        let tapW = pow(0.6, fk);
        let tapUV = uv - wDir * fk * (0.012 + 0.02 * warpStrength);
        ghostSum += acesInverse(loadHistory(tapUV, resolution).rgb) * tapW;
        ghostW += tapW;
    }
    let ghosts = ghostSum / max(ghostW, 1e-4);

    let freezeColor = textureSampleLevel(readTexture, u_sampler, clamp(warpUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    color = mix(color, freezeColor, inField * freeze);

    // Temporal memory: ghosts trail along the flow (stronger with bass).
    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let event = u.ripples[i];
        let age = time - event.z;
        if (event.z > 0.0 && age >= 0.0 && age < 2.5) {
            let dC = length((uv - event.xy) * aspectV);
            clickFront += exp(-age * 1.8) * exp(-abs(dC - age * 0.36) * 62.0);
        }
    }
    clickFront = min(clickFront, 1.0);
    let ghostMix = clamp(0.18 + ghostCount * 0.15 + bass * 0.05, 0.0, 0.45) * (1.0 - inField * freeze);
    var memory = mix(color, ghosts, ghostMix) + vec3<f32>(clickFront * 0.12);

    // ACES on display RGB (negatives clamped first).
    var display = acesToneMap(max(memory, vec3<f32>(0.0)));
    // Click fronts briefly show the previous frame (a ring where time lags).
    display = mix(display, prev.rgb, clickFront * 0.5);
    // Idea 1: true stasis bubble — inside the held field, time stops: the
    // output IS the held C frame (display-space, so it holds exactly).
    let stasis = inField * freeze;
    display = mix(display, prev.rgb, stasis);

    // Semantic alpha: source coverage x field (bubble / horizon opaque).
    let alpha = clamp(gSample.a * mix(0.75, 1.0, max(stasis, edgeGrad * 0.5) * 0.5 + min(length(w), 0.3) * 0.8), 0.0, 1.0);
    let finalA = mix(alpha, prev.a, stasis);

    textureStore(writeTexture, pixel, vec4<f32>(display, finalA));
    textureStore(dataTextureA, pixel, vec4<f32>(display, finalA));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
