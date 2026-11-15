// ═══════════════════════════════════════════════════════════════════
//  Fibonacci Spiral Garden
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-11, 2026-11-15
//  Ideas: √n disk packing; 8/13 parastichy ridges; floret age; involucre bracts; 3D cupped-corolla dome normals & anthesis anther rings; 21-fold Fibonacci ray-floret crown
//  A packing: raw HDR display RGBA (ACES on writeTexture)
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"
// zoom_params: x=Spiral Scale, y=Growth Cycle, z=Petal Size, w=Bloom

const GOLDEN_ANGLE: f32 = 2.39996323;
const TAU_GARDEN: f32 = 6.28318530718;

fn palette(t: f32) -> vec3<f32> {
    return vec3<f32>(0.52) + vec3<f32>(0.48) * cos(6.28318 * (vec3<f32>(t) + vec3<f32>(0.04, 0.28, 0.58)));
}

fn hash11(x: f32) -> f32 {
    return fract(sin(x * 127.1) * 43758.5453);
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
    var p = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
    let time = u.config.x;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));

    let spiralScale = mix(0.5, 1.55, clamp(u.zoom_params.x, 0.0, 1.0));
    let growthSpeed = mix(0.08, 0.7, clamp(u.zoom_params.y, 0.0, 1.0));
    let petalSize = mix(0.008, 0.045, clamp(u.zoom_params.z, 0.0, 1.0));
    let bloomStrength = mix(0.3, 2.4, clamp(u.zoom_params.w, 0.0, 1.0));

    let mouse = (u.zoom_config.yz * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
    let held = clamp(u.zoom_config.w, 0.0, 1.0);
    let mouseDelta = p - mouse;
    p += normalize(mouseDelta + vec2<f32>(0.0001)) * exp(-dot(mouseDelta, mouseDelta) * 7.0) * held * 0.15;

    let sunDir = normalize(vec3<f32>(-0.38, 0.44, 0.81));
    let headR = length(p) / max(spiralScale, 0.001);
    let domeHeight = sqrt(max(1.0 - min(headR * headR, 1.0), 0.0));

    var flower = 0.0;
    var leaf = 0.0;
    var paraRidge = 0.0;
    var hueSum = 0.0;
    var nearDepth = 0.0;
    var ageMass = 0.0;
    var cupLitSum = 0.0;
    var antherPollen = 0.0;
    for (var i = 0; i < 96; i++) {
        let fi = f32(i);
        let normalizedIndex = (fi + 0.5) / 96.0;
        let unfurl = smoothstep(normalizedIndex - 0.16, normalizedIndex + 0.05,
                                fract(time * growthSpeed * 0.08 + 0.82) + 0.18);
        let radius = sqrt(normalizedIndex) * spiralScale * unfurl;
        let angle = fi * GOLDEN_ANGLE + time * growthSpeed * (0.16 + audio.y * 0.14);
        let node = vec2<f32>(cos(angle), sin(angle)) * radius;
        let q = p - node;
        let localAngle = atan2(q.y, q.x) - angle;
        let lobes = 0.72 + 0.28 * cos(localAngle * 5.0 + time * 0.6 + fi);
        let pack = mix(1.18, 0.48, sqrt(normalizedIndex));
        let size = petalSize * pack * (0.82 + 0.28 * hash11(fi)) * (1.0 + audio.x * 0.35);
        let lobeRadius = max(size * lobes, 0.0005);
        let qLen = length(q);
        let petalDistance = qLen - lobeRadius;
        let petal = exp(-max(petalDistance, 0.0) * 115.0) * smoothstep(size * 1.8, -size * 0.2, petalDistance);
        let halo = exp(-abs(petalDistance) * 38.0) * 0.1;
        let para8 = exp(-abs(sin(fi * 3.14159265 / 8.0)) * 9.0);
        let para13 = exp(-abs(sin(fi * 3.14159265 / 13.0)) * 9.0);
        let para = max(para8, para13);

        // ── Idea 1: 3D cupped-corolla dome normals & anthesis anther rings ─
        // Each floret cup tilts outward along the convex capitulum dome while
        // mid-head florets in active anthesis open a golden tubular anther ring.
        let cupSlope = (q / lobeRadius) * 0.72 + (node / max(spiralScale, 0.001)) * 0.48;
        let floretN = normalize(vec3<f32>(cupSlope, 1.0));
        let cupLambert = clamp(dot(floretN, sunDir) * 0.55 + 0.55, 0.25, 1.35);
        let anthesisZone = smoothstep(0.16, 0.34, normalizedIndex) * (1.0 - smoothstep(0.58, 0.78, normalizedIndex));
        let antherTube = exp(-abs(qLen - size * 0.42) * 210.0) * anthesisZone * unfurl;

        flower += petal;
        leaf += halo;
        paraRidge += halo * para * 0.85 + petal * para * 0.22;
        hueSum += (petal + halo) * normalizedIndex;
        ageMass += petal * normalizedIndex;
        cupLitSum += petal * cupLambert;
        antherPollen += antherTube * (0.7 + 0.3 * cos(localAngle * 5.0));
        nearDepth = max(nearDepth, petal * (0.55 + domeHeight * 0.45 - normalizedIndex * 0.35));
    }

    // ── Idea 2: 21-fold Fibonacci ligulate ray-floret corolla crown ───────
    // Crowns the gap between the 96 central disk florets and the 13 outer green
    // involucre bracts with 21 ribbed, radially tapered golden ray petals.
    let rDist = length(p);
    let baseAng = atan2(p.y, p.x) - time * growthSpeed * 0.09;
    let rayStep = TAU_GARDEN / 21.0;
    let rayIdx = round(baseAng / rayStep);
    let rayCenterAng = rayIdx * rayStep;
    let raySway = sin(time * (0.85 + growthSpeed) + rayIdx * GOLDEN_ANGLE) * (0.012 + audio.y * 0.016);
    let dAng = baseAng - rayCenterAng + raySway;
    let rayInner = spiralScale * 0.78;
    let rayOuter = spiralScale * (1.13 + petalSize * 3.2 + audio.x * 0.05);
    let rayT = clamp((rDist - rayInner) / max(rayOuter - rayInner, 0.001), 0.0, 1.0);
    let liguleProfile = sin(rayT * 3.14159265) * (1.0 - rayT * 0.28);
    let halfAngularWidth = (0.045 + petalSize * 0.55) * max(liguleProfile, 0.0);
    let lateralDist = abs(dAng) * max(rDist, 0.05);
    let rayMask = smoothstep(halfAngularWidth, halfAngularWidth * 0.22, lateralDist)
                * smoothstep(0.0, 0.14, rayT) * smoothstep(1.0, 0.86, rayT);
    let rayRibs = 0.78 + 0.22 * cos((lateralDist / max(halfAngularWidth, 0.0005)) * 9.42477);
    let rayPetal = rayMask * rayRibs;

    var clickBloom = 0.0;
    let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
    for (var ri = 0u; ri < rippleCount; ri++) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        let liveMask = f32(age > 0.0 && age < 3.2);
        let center = (ripple.xy * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
        clickBloom += liveMask * exp(-abs(distance(p, center) - max(age, 0.0) * 0.2) * 74.0) * exp(-max(age, 0.0) * 1.4);
    }

    let hue = hueSum / max(flower + leaf, 0.001) + time * 0.018 + audio.y * 0.14;
    let cupShade = mix(1.0, cupLitSum / max(flower, 0.001), clamp(flower, 0.0, 1.0));
    let background = vec3<f32>(0.008, 0.018, 0.012) + palette(length(p) * 0.1) * 0.015;
    var hdrColor = background + palette(hue) * flower * cupShade * (0.65 + bloomStrength + audio.x * 0.7);
    hdrColor += palette(hue + 0.3) * leaf * bloomStrength * (0.5 + audio.z);
    hdrColor += palette(hue + 0.12) * paraRidge * (0.55 + bloomStrength * 0.25);
    // Floret age — outer disks leave the meristem and turn ochre.
    hdrColor = mix(hdrColor, vec3<f32>(0.86, 0.52, 0.12) * cupShade, clamp(ageMass, 0.0, 1.0) * 0.38);
    // Anthesis pollen rings on mid-zone florets
    hdrColor += vec3<f32>(1.25, 0.92, 0.24) * antherPollen * (0.55 + bloomStrength * 0.35 + audio.z * 0.4);
    // 21-fold ligulate ray florets nestled behind the disk head and inside the green bracts
    let rayUnderDisk = rayPetal * (1.0 - clamp(flower * 1.25, 0.0, 0.92));
    let rayTint = mix(vec3<f32>(1.05, 0.68, 0.14), palette(hue + 0.06), 0.38);
    hdrColor += rayTint * rayUnderDisk * (0.52 + bloomStrength * 0.42 + audio.y * 0.25);
    // Involucre bracts — a pointed ring outside the head.
    let bractAng = atan2(p.y, p.x);
    let bract = exp(-abs(rDist - spiralScale * 1.08) * 28.0) * pow(saturate(0.5 + 0.5 * cos(bractAng * 13.0)), 8.0);
    hdrColor += vec3<f32>(0.12, 0.32, 0.08) * bract * bloomStrength * (1.0 - rayUnderDisk * 0.45);
    hdrColor += vec3<f32>(0.45, 0.85 + audio.y * 0.3, 0.3 + audio.z * 0.5) * clickBloom * 0.42;
    let history = textureLoad(dataTextureC, coord, 0);
    hdrColor = clamp(mix(hdrColor, history.rgb, 0.045 + audio.x * 0.06), vec3<f32>(0.0), vec3<f32>(7.0));
    let mapped = acesToneMap(hdrColor * 1.06);
    let alpha = clamp(flower * 0.48 + rayUnderDisk * 0.38 + antherPollen * 0.14 + leaf * 0.15 + paraRidge * 0.08 + clickBloom * 0.12, 0.02, 0.98);
    let depth = clamp(max(nearDepth * 0.85 + flower * 0.05, rayUnderDisk * 0.42 + bract * 0.22), 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(mapped, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(hdrColor, alpha));
}
