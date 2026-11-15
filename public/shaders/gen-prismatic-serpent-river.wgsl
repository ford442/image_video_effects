// ═══════════════════════════════════════════════════════════════════
//  Prismatic Serpent River — braided chromatic creatures flowing through space
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-21, 2026-11-15
//  Ideas: finite serpents; per-channel body dispersion; over/under braided strand crossings; cylindrical chevron scales & Fresnel flank sheen (§12.2F)
//  A packing: ACES display RGBA (read back as colour history)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const TAU: f32 = 6.28318530718;

fn palette(t: f32) -> vec3<f32> {
    return vec3<f32>(0.50, 0.52, 0.54) + vec3<f32>(0.50, 0.48, 0.46) *
        cos(TAU * (vec3<f32>(1.0, 0.66, 0.39) * t + vec3<f32>(0.01, 0.30, 0.64)));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn historyLoadUV(uv: vec2<f32>) -> vec4<f32> {
    let size = vec2<i32>(textureDimensions(dataTextureC));
    let pixel = vec2<i32>(floor(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * vec2<f32>(size)));
    return textureLoad(dataTextureC, clamp(pixel, vec2<i32>(0), size - vec2<i32>(1)), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let time = u.config.x;
    let audio = plasmaBuffer[0].xyz;
    let serpentCount = u.zoom_params.x;
    let flowSpeed = u.zoom_params.y;
    let bodyScale = u.zoom_params.z;
    let iridescence = u.zoom_params.w;
    let aspect = resolution.x / resolution.y;
    var p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
    let mouseP = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0);
    let mouseDelta = p - mouseP;
    let mouseDistance = max(length(mouseDelta), 0.001);
    let dragMask = exp(-mouseDistance * (4.5 + serpentCount * 3.5)) * u.zoom_config.w;
    let dragTangent = vec2<f32>(-mouseDelta.y, mouseDelta.x) / mouseDistance;
    p += dragTangent * dragMask * (0.06 + bodyScale * 0.18);

    let lanes = 3.0 + floor(serpentCount * 8.0);
    let speed = 0.6 + flowSpeed * 4.8 + audio.x * 0.5;
    let laneCoord = (p.y + 0.55) * lanes;
    let lane = floor(laneCoord);
    let laneY = fract(laneCoord) - 0.5;
    let slither = sin(p.x * (8.0 + bodyScale * 14.0) - time * speed + lane * 1.83) * (0.10 + bodyScale * 0.17);
    let signedCross = laneY - slither;
    let bodyDistance = abs(signedCross);

    // Idea 1 — finite serpents: each lane carries separate bodies travelling +x with the slither wave;
    // bodyU runs tail (0) -> head (serpentLen); the girth tapers to the tail and rounds off at the head.
    let serpentFreq = 0.55 + serpentCount * 0.35;
    let serpentLen = 0.62 + bodyScale * 0.2;
    let bodyU = fract(p.x * serpentFreq - time * speed * 0.07 + fract(sin(lane * 91.7) * 43758.5453));
    let bodyS = bodyU / serpentLen;
    let girth = select(0.0, sqrt(smoothstep(0.0, 0.6, bodyS)) * sqrt(1.0 - smoothstep(0.9, 1.0, bodyS)), bodyS < 1.0);
    let presence = smoothstep(0.0, 0.08, girth);
    let bodyK = (22.0 + bodyScale * 42.0) / max(girth, 0.08);

    // Idea 2 — prismatic dispersion: R and B bodies solved with the slither amplitude scaled apart,
    // so the flanks split into rainbow fringes; Iridescence sets the spread.
    let dispersion = 0.04 + iridescence * 0.14;
    let bodyRGB = vec3<f32>(
        exp(-abs(laneY - slither * (1.0 + dispersion)) * bodyK),
        exp(-bodyDistance * bodyK),
        exp(-abs(laneY - slither * (1.0 - dispersion)) * bodyK)) * presence;
    let body = bodyRGB.g;

    // ── Idea 3: over/under braided companion strand with contact shadow ───
    let braidPhase = p.x * (4.2 + bodyScale * 7.0) - time * speed * 0.52 + lane * 2.41;
    let braidSlither = -slither * 0.88 + cos(braidPhase) * (0.11 + bodyScale * 0.14);
    let braidCross = laneY - braidSlither;
    let braidDist = abs(braidCross);
    let braidU = fract(p.x * serpentFreq - time * speed * 0.061 + fract(sin((lane + 17.3) * 73.1) * 43758.5453));
    let braidS = braidU / serpentLen;
    let braidGirth = select(0.0, sqrt(smoothstep(0.0, 0.6, braidS)) * sqrt(1.0 - smoothstep(0.9, 1.0, braidS)), braidS < 1.0);
    let braidPresence = smoothstep(0.0, 0.08, braidGirth) * (0.45 + 0.55 * serpentCount);
    let braidK = (24.0 + bodyScale * 42.0) / max(braidGirth, 0.08);
    let braidRGB = vec3<f32>(
        exp(-abs(braidCross - braidSlither * dispersion) * braidK),
        exp(-braidDist * braidK),
        exp(-abs(braidCross + braidSlither * dispersion) * braidK)) * braidPresence;
    let braidBody = braidRGB.g;
    let primaryOver = smoothstep(-0.22, 0.22, sin(braidPhase));
    let primaryOcc = 1.0 - clamp(braidBody * (1.0 - primaryOver) * 0.78, 0.0, 0.78);
    let braidOcc = (1.0 - clamp(body * primaryOver * 0.82, 0.0, 0.82)) * (1.0 - body * primaryOver * 0.55);

    // ── Idea 4: cylindrical spine normal, chevron scales & Fresnel sheen (§12.2F) ──
    let vNorm = clamp(signedCross * bodyK * 0.42, -1.0, 1.0);
    let cylNz = sqrt(max(1.0 - vNorm * vNorm, 0.0));
    let spineRidge = pow(cylNz, 6.0) * body;
    let fresnelFlank = (0.04 + 0.96 * pow(1.0 - cylNz, 4.0)) * body;

    let headDx = (serpentLen * 0.95 - bodyU) / serpentFreq;
    let headEye = exp(-pow(headDx / 0.014, 2.0)) * exp(-bodyDistance * 70.0) * step(bodyU, serpentLen);
    let scalePhase = fract(p.x * (7.0 + bodyScale * 15.0) - time * speed * 0.42 + lane * 0.271);
    let chevronBend = abs(vNorm) * 0.42;
    let scales = pow(0.5 + 0.5 * cos((scalePhase + chevronBend) * TAU + signedCross * 18.0), 10.0) * body * (0.55 + 0.65 * cylNz);
    let braidScales = pow(0.5 + 0.5 * cos((scalePhase + abs(clamp(braidCross * braidK * 0.42, -1.0, 1.0)) * 0.42 + 0.35) * TAU), 10.0) * braidBody;
    let eyePhase = fract(p.x * (2.0 + serpentCount * 4.0) - time * speed * 0.20 + lane * 0.131);
    let eyes = exp(-pow((eyePhase - 0.5) / 0.045, 2.0)) * exp(-bodyDistance * 85.0) * presence * 0.4 + headEye;
    let wake = exp(-abs(laneY - slither * 1.35) * 10.0) * (0.5 + 0.5 * sin(p.x * 30.0 - time * speed * 2.0));
    let finPhase = fract(p.x * (4.0 + bodyScale * 8.0) - time * speed * 0.28 + lane * 0.37);
    let prismFins = exp(-pow((finPhase - 0.5) / 0.075, 2.0)) * exp(-abs(bodyDistance - 0.055) * 42.0) * presence;
    let riverCurrent = pow(0.5 + 0.5 * sin(p.x * 12.0 + p.y * 19.0 - time * speed * 1.3), 14.0) * exp(-abs(laneY) * 2.5);

    var clickShed = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 3.0) {
            let delta = (uv - ripple.xy) * vec2<f32>(aspect, 0.0 + 1.0);
            let ring = abs(length(delta) - age * (0.18 + flowSpeed * 0.15));
            clickShed += (1.0 - smoothstep(0.0, 0.027, ring)) * (0.5 + 0.5 * cos(atan2(delta.y, delta.x) * 11.0 - age * 7.0)) * (1.0 - age / 3.0);
        }
    }

    let hue = lane / max(lanes, 1.0) + scalePhase * iridescence + time * (0.04 + iridescence * 0.18);
    var hdr = palette(hue) * bodyRGB * primaryOcc * (0.75 + 0.45 * cylNz) * (0.8 + iridescence * 2.0 + audio.y);
    hdr += palette(hue + 0.19) * braidRGB * braidOcc * (0.75 + iridescence * 1.7 + audio.y * 0.8);
    hdr += palette(hue + 0.32) * (scales * primaryOcc + braidScales * braidOcc * 0.8) * (1.3 + audio.z);
    hdr += palette(hue + 0.55) * (fresnelFlank * (0.65 + iridescence * 1.35) + spineRidge * 0.35) * primaryOcc;
    hdr += vec3<f32>(1.0, 0.85, 0.35) * eyes * primaryOcc * (1.4 + audio.x);
    hdr += palette(hue + 0.65) * (wake * 0.35 + clickShed * 1.8 + dragMask * 0.8);
    hdr += palette(hue + 0.48) * (prismFins * 1.25 + riverCurrent * 0.18) * (0.5 + audio.z);
    let historyUV = clamp(uv - vec2<f32>((0.004 + flowSpeed * 0.010) / max(aspect, 0.001), sin(time + uv.x * 7.0) * 0.002), vec2<f32>(0.0), vec2<f32>(1.0));
    let history = historyLoadUV(historyUV);
    hdr = mix(hdr, history.rgb, clamp(0.10 + iridescence * 0.16 + dragMask * 0.14, 0.0, 0.42));
    let structure = clamp(body + braidBody * 0.85 + scales * 0.5 + prismFins * 0.4 + eyes + clickShed * 0.5, 0.0, 1.0);
    let output = vec4<f32>(acesToneMap(max(hdr, vec3<f32>(0.0))), clamp(0.10 + structure * 0.88, 0.0, 1.0));
    let braidZ = max(body * (0.45 + 0.35 * primaryOver + 0.15 * cylNz), braidBody * (0.45 + 0.35 * (1.0 - primaryOver)));
    textureStore(writeTexture, coord, output);
    textureStore(dataTextureA, coord, output);
    textureStore(writeDepthTexture, coord, vec4<f32>(clamp(0.12 + braidZ * 0.68 + scales * 0.12 + eyes * 0.10, 0.0, 0.95), 0.0, 0.0, 0.0));
}
