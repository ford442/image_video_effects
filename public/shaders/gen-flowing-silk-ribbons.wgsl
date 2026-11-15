// ═══════════════════════════════════════════════════════════════════
//  Flowing Silk Ribbons
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-10, 2026-11-15
//  Ideas: half-twist pinch; travelling satin glint; warp threads & selvage; shot-silk transverse weft weave & grazing dichroism; Z-billow drape shadows & Beer–Lambert sheer cross-dyeing (§12.2F)
//  A packing: raw HDR display RGBA (ACES on writeTexture)
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"
// zoom_params: x=Ribbon Count, y=Flow Speed, z=Silk Width, w=Iridescence

fn palette(t: f32) -> vec3<f32> {
    return vec3<f32>(0.52) + vec3<f32>(0.48) * cos(6.28318 * (vec3<f32>(t) + vec3<f32>(0.0, 0.22, 0.47)));
}

fn hash11(x: f32) -> f32 {
    return fract(sin(x * 91.17) * 43758.5453);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
    if (gid.x >= dims.x || gid.y >= dims.y) { return; }
    let coord = vec2<i32>(gid.xy);
    let res = vec2<f32>(dims);
    let uv = (vec2<f32>(gid.xy) + vec2<f32>(0.5)) / res;
    let aspect = res.x / max(res.y, 1.0);
    let p = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
    let time = u.config.x;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));

    let ribbonCount = i32(3.0 + clamp(u.zoom_params.x, 0.0, 1.0) * 9.0);
    let flowSpeed = mix(0.12, 1.7, clamp(u.zoom_params.y, 0.0, 1.0));
    let silkWidth = mix(0.018, 0.12, clamp(u.zoom_params.z, 0.0, 1.0));
    let iridescence = clamp(u.zoom_params.w, 0.0, 1.0);
    let mouse = (u.zoom_config.yz * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
    let held = clamp(u.zoom_config.w, 0.0, 1.0);

    var coverage = 0.0;
    var highlight = 0.0;
    var warpAcc = 0.0;
    var weftAcc = 0.0;
    var dichroicAcc = 0.0;
    var selvageAcc = 0.0;
    var hueAccum = 0.0;
    var backAcc = 0.0;
    var glintAcc = 0.0;
    var shadowAcc = 0.0;
    var overlapOptical = 0.0;
    var topZ = -2.0;
    var depth = 0.0;
    let rcFloat = max(f32(ribbonCount), 1.0);
    for (var i = 0; i < 12; i++) {
        if (i >= ribbonCount) { break; }
        let fi = f32(i);
        let lane = (fi - 0.5 * f32(ribbonCount - 1)) * (1.65 / rcFloat);
        let phase = time * flowSpeed * (0.45 + fi * 0.025) + hash11(fi) * 6.28318;
        let primary = sin(p.x * (1.8 + fi * 0.08) - phase) * (0.13 + audio.x * 0.035);
        let secondary = sin(p.x * 5.5 + phase * 0.63 + fi) * (0.025 + audio.y * 0.018);
        let comb = (mouse.y - lane) * exp(-abs(p.x - mouse.x) * 4.5) * held * 0.42;
        let center = lane + primary + secondary + comb;
        let slope = cos(p.x * (1.8 + fi * 0.08) - phase) * (0.24 + audio.x * 0.06);
        // Idea 1 - half-twist: cos(twist) is the visible face width; sign picks front/back face
        let twistPhase = p.x * (1.1 + fi * 0.05) - phase * 0.7 + fi * 1.3;
        let twist = cos(twistPhase);
        let width = silkWidth * (0.72 + 0.4 * sin(phase + fi)) * (0.3 + 0.7 * abs(twist));
        let signedD = p.y - center;
        let d = abs(signedD);
        let ribbon = smoothstep(width, width * 0.15, d);
        let sheen = pow(max(1.0 - d / max(width, 0.001), 0.0), 7.0) * (0.35 + abs(slope));
        let warp = ribbon * pow(abs(sin(p.x * (26.0 + fi * 2.2) - phase * 0.18)), 10.0);

        // ── Idea 3: shot-silk transverse weft weave & grazing warp/weft dichroism ──
        // Contrasting weft fibres run perpendicular to warp across signedD/width; grazing
        // twist/slope angles shift dominance from warp dye to complementary weft dye.
        let crossCoord = clamp(signedD / max(width, 0.001), -1.2, 1.2);
        let weft = ribbon * pow(abs(sin(crossCoord * (22.0 + fi * 1.4) + p.x * 2.5)), 8.0);
        let cosView = clamp(abs(twist) * inverseSqrt(1.0 + slope * slope * 2.5), 0.05, 1.0);
        let grazingShift = pow(1.0 - cosView, 2.2) * iridescence;

        // Idea 2 - satin glint travelling along the ribbon, strongest on slopes facing the light
        let glintPos = 0.5 + 0.5 * sin(p.x * 1.3 - time * flowSpeed * 0.9 + fi * 1.9);
        let glint = ribbon * pow(glintPos, 14.0) * (0.35 + abs(slope) * 1.4) * (1.0 - smoothstep(0.0, width, d) * 0.5);
        let selvage = exp(-abs(d - width * 0.88) * 90.0) * smoothstep(width * 1.15, width * 0.7, d);

        // ── Idea 4: Z-billow aerial drape shadows & Beer–Lambert sheer cross-dyeing (§12.2F) ─
        let ribbonZ = clamp((1.0 - fi / rcFloat) * 0.68 + 0.32 * (0.5 + 0.5 * sin(twistPhase)), 0.0, 1.0);
        let shadowSoft = smoothstep(width * 2.4, width * 0.25, d);
        let underPrev = clamp(topZ - ribbonZ, 0.0, 1.0);
        shadowAcc += ribbon * underPrev * 0.75 + shadowSoft * (1.0 - ribbon) * step(0.05, coverage) * 0.18;
        overlapOptical += coverage * ribbon;
        topZ = select(topZ, max(topZ, ribbonZ), ribbon > 0.08);

        coverage += ribbon * (1.0 - coverage * 0.18);
        highlight += sheen;
        warpAcc += warp;
        weftAcc += weft;
        dichroicAcc += ribbon * grazingShift;
        selvageAcc += selvage;
        glintAcc += glint;
        backAcc += ribbon * step(twist, 0.0);
        hueAccum += (ribbon + sheen) * (fi / rcFloat + slope * 0.15);
        depth = max(depth, ribbon * ribbonZ);
    }

    var clickWave = 0.0;
    let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
    for (var ri = 0u; ri < rippleCount; ri++) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        let liveMask = f32(age > 0.0 && age < 3.0);
        let safeAge = max(age, 0.0);
        let center = (ripple.xy * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
        clickWave += liveMask * exp(-abs(distance(p, center) - safeAge * 0.24) * 68.0) * exp(-safeAge * 1.4);
    }

    let hue = hueAccum / max(coverage + highlight, 0.001) + time * 0.018 + audio.y * 0.16;
    let dichroicRatio = clamp(dichroicAcc / max(coverage + 0.001, 0.001), 0.0, 1.0);
    let warpDye = palette(hue);
    let weftDye = palette(hue + 0.38);
    let shotSilk = mix(warpDye, weftDye, dichroicRatio * 0.78);
    let baseSilk = mix(vec3<f32>(0.16, 0.025, 0.08), shotSilk, 0.3 + iridescence * 0.7);
    // Beer–Lambert sheer organza cross-dye transmission where translucent ribbons overlap
    let dyeSigma = mix(vec3<f32>(0.55, 0.95, 1.35), vec3<f32>(1.25, 0.52, 0.85), clamp(iridescence, 0.0, 1.0));
    let sheerFilter = exp(-clamp(overlapOptical, 0.0, 2.5) * dyeSigma * 0.55);
    let drapeOcc = 1.0 - clamp(shadowAcc, 0.0, 0.52);

    var hdrColor = vec3<f32>(0.006, 0.008, 0.018) + baseSilk * sheerFilter * drapeOcc * coverage * (0.85 + audio.x * 0.5);
    hdrColor += palette(hue + 0.2) * highlight * drapeOcc * (0.18 + iridescence * 0.85 + audio.z * 0.35);
    hdrColor += warpDye * warpAcc * (0.22 + iridescence * 0.18);
    hdrColor += weftDye * weftAcc * (0.20 + iridescence * 0.34);
    // back face of the twisted ribbon: cooler, duller
    hdrColor = mix(hdrColor, hdrColor * vec3<f32>(0.62, 0.78, 1.1), clamp(backAcc / max(coverage + 0.001, 0.001), 0.0, 1.0) * 0.6);
    hdrColor += vec3<f32>(1.2, 1.1, 0.95) * glintAcc * (0.5 + iridescence * 0.4 + audio.z * 0.3);
    hdrColor += vec3<f32>(1.15, 1.05, 0.85) * selvageAcc * (0.28 + audio.z * 0.12);
    hdrColor += vec3<f32>(0.45, 0.7 + audio.y * 0.4, 1.15 + audio.z * 0.5) * clickWave * 0.32;
    let history = textureLoad(dataTextureC, coord, 0);
    hdrColor = clamp(mix(hdrColor, history.rgb, 0.06 + audio.x * 0.065), vec3<f32>(0.0), vec3<f32>(7.0));
    let mapped = acesToneMap(hdrColor * 1.08);
    let alpha = clamp(coverage * 0.7 + highlight * 0.12 + (warpAcc + weftAcc) * 0.06 + selvageAcc * 0.1 + glintAcc * 0.05 + clickWave * 0.1, 0.02, 0.98);

    textureStore(writeTexture, coord, vec4<f32>(mapped, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(clamp(depth, 0.0, 1.0), 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(hdrColor, alpha));
}
