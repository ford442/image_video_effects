// ═══════════════════════════════════════════════════════════════════
//  Glass Refraction Prismatic
//  Category: advanced-hybrid
//  Features: raymarched, spectral-dispersion, physical-refraction,
//            mouse-driven, audio-reactive, exact-feedback
//  Complexity: Very High
//  Upgraded: 2026-10-18
//  Ideas: back-face exit march & critical-angle total-internal-reflection (TIR) prismatic fire; dispersion-focused spectral caustic convergence & Brewster-angle polarized reflection
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
//  Raymarched optical glass prism with 4-band Cauchy spectral
//  dispersion. Physical Snell refraction rays split wavelengths
//  internally with Fresnel dielectric reflections and Beer-Lambert
//  spectral absorption.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Transparency, y=Dispersion, z=Thickness, w=Roughness

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn acesToneMap(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
    return length(p) - r;
}

fn smoothUnion(d1: f32, d2: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (d2 - d1) / k, 0.0, 1.0);
    return mix(d2, d1, h) - k * h * (1.0 - h);
}

fn map(p: vec3<f32>, time: f32, bass: f32, mid: f32, pointerSpring: f32) -> f32 {
    let t = time * 0.45;
    let baseScale = 1.0 + mid * 0.18 + pointerSpring * 0.25;
    let blob1 = sdSphere(p - vec3<f32>(sin(t) * 0.32, cos(t * 0.8) * 0.15, 0.0), 0.26 * baseScale);
    let blob2 = sdSphere(p - vec3<f32>(cos(t * 0.7) * 0.24, sin(t * 0.8) * 0.22, 0.1), 0.21 * baseScale);
    let blob3 = sdSphere(p - vec3<f32>(0.0, cos(t * 1.1) * 0.18, sin(t * 0.9) * 0.12), 0.18 * baseScale);
    let blobs = smoothUnion(smoothUnion(blob1, blob2, 0.15), blob3, 0.12);

    // Continuous geometry ribbon
    let torusD = vec2<f32>(length(p.xz) - 0.32 - bass * 0.08, p.y + sin(p.x * 3.5 + time) * 0.08);
    let torus = length(torusD) - 0.055;

    return smoothUnion(blobs, torus, 0.18);
}

fn calcNormal(p: vec3<f32>, time: f32, bass: f32, mid: f32, pointerSpring: f32) -> vec3<f32> {
    let eps = 0.0012;
    return normalize(vec3<f32>(
        map(p + vec3<f32>(eps, 0.0, 0.0), time, bass, mid, pointerSpring) - map(p - vec3<f32>(eps, 0.0, 0.0), time, bass, mid, pointerSpring),
        map(p + vec3<f32>(0.0, eps, 0.0), time, bass, mid, pointerSpring) - map(p - vec3<f32>(0.0, eps, 0.0), time, bass, mid, pointerSpring),
        map(p + vec3<f32>(0.0, 0.0, eps), time, bass, mid, pointerSpring) - map(p - vec3<f32>(0.0, 0.0, eps), time, bass, mid, pointerSpring)
    ));
}

fn fresnel(cosTheta: f32, eta: f32) -> f32 {
    let c = abs(cosTheta);
    let g = sqrt(max(eta * eta - 1.0 + c * c, 0.0001));
    let gmc = g - c;
    let gpc = g + c;
    let a = (gmc / gpc) * (gmc / gpc);
    let b = (c * gpc - 1.0) / max(c * gmc + 1.0, 0.0001);
    return clamp(0.5 * a * (1.0 + b * b), 0.0, 1.0);
}

fn refractRay(I: vec3<f32>, N: vec3<f32>, eta: f32) -> vec3<f32> {
    let NdotI = dot(N, I);
    let k = 1.0 - eta * eta * (1.0 - NdotI * NdotI);
    if (k < 0.0) {
        return reflect(I, N);
    }
    return eta * I - (eta * NdotI + sqrt(k)) * N;
}

fn cauchyIOR(wavelengthNm: f32, A: f32, B: f32) -> f32 {
    let lambdaUm = wavelengthNm * 0.001;
    return A + B / (lambdaUm * lambdaUm);
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
    let t = clamp((lambda - 440.0) / (680.0 - 440.0), 0.0, 1.0);
    let r = smoothstep(0.5, 0.8, t) + smoothstep(0.0, 0.15, t) * 0.3;
    let g = 1.0 - abs(t - 0.4) * 3.0;
    let b = 1.0 - smoothstep(0.0, 0.4, t);
    return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    let pixel = vec2<i32>(global_id.xy);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let time = u.config.x;
    let isMouseDown = u.zoom_config.w > 0.5;
    let mouseUV = u.zoom_config.yz;

    // Persistent single-writer state management
    if (global_id.x == 0u && global_id.y == 0u) {
        var targetPos = mouseUV;
        if (!isMouseDown && extraBuffer[137] < 0.5) {
            targetPos = vec2<f32>(0.5 + 0.2 * cos(time * 0.6), 0.5 + 0.2 * sin(time * 0.75));
        }

        var curP = vec2<f32>(extraBuffer[133], extraBuffer[134]);
        if (curP.x == 0.0 && curP.y == 0.0) { curP = mouseUV; }

        var pVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        let diff = targetPos - curP;
        pVel = pVel + diff * 0.18;
        pVel = pVel * 0.82;
        curP = curP + pVel;

        extraBuffer[133] = clamp(curP.x, 0.0, 1.0);
        extraBuffer[134] = clamp(curP.y, 0.0, 1.0);
        extraBuffer[135] = clamp(pVel.x, -0.05, 0.05);
        extraBuffer[136] = clamp(pVel.y, -0.05, 0.05);

        let prevDown = extraBuffer[137];
        var rippleImpulse = extraBuffer[138] * 0.94;
        if (isMouseDown && prevDown < 0.5) {
            rippleImpulse = 1.0;
        }
        extraBuffer[137] = select(0.0, 1.0, isMouseDown);
        extraBuffer[138] = rippleImpulse;
    }

    let smoothMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    let clickImpulse = extraBuffer[138];

    let uv = (vec2<f32>(pixel) + 0.5) / res;
    let aspect = res.x / res.y;
    let aspectVec = vec2<f32>(aspect, 1.0);

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Sliders
    let transparency = mix(0.2, 0.85, u.zoom_params.x);
    let cauchyB = mix(0.01, 0.09, u.zoom_params.y);
    let thicknessScale = mix(0.3, 1.6, u.zoom_params.z);
    let roughness = clamp(u.zoom_params.w, 0.0, 1.0) * 0.12;

    let mousePos = (smoothMouse - 0.5) * 2.0;
    let distToMouse = length((uv - smoothMouse) * aspectVec);
    let holdEffect = smoothstep(0.4, 0.0, distToMouse) * select(0.3, 1.0, isMouseDown);

    // Capped click ripple fronts
    var rippleDistortion = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let r = u.ripples[i];
        let rAge = time - r.z;
        if (r.z > 0.0 && rAge > 0.0 && rAge < 2.5) {
            let rDist = length((uv - r.xy) * aspectVec);
            let env = smoothstep(2.5, 0.0, rAge);
            let wave = sin(rDist * 36.0 - rAge * 11.0) * exp(-rDist * 6.5) * env;
            rippleDistortion = rippleDistortion + wave * 0.35;
        }
    }
    rippleDistortion = rippleDistortion + sin(distToMouse * 32.0 - time * 8.0) * exp(-distToMouse * 7.5) * clickImpulse * 0.5;

    let ro = vec3<f32>(mousePos.x * 0.45, mousePos.y * 0.45, -1.4);
    let rd = normalize(vec3<f32>((uv.x - 0.5) * aspect + rippleDistortion * 0.02, uv.y - 0.5 + rippleDistortion * 0.02, 1.0));

    var t = 0.0;
    var hit = false;
    var enterT = 0.0;
    var normal = vec3<f32>(0.0);

    for (var i: i32 = 0; i < 48; i = i + 1) {
        let p = ro + rd * t;
        let d = map(p, time, bass, mids, holdEffect);
        if (!hit && d < 0.0015) {
            hit = true;
            enterT = t;
            normal = calcNormal(p, time, bass, mids, holdEffect);
            break;
        }
        t = t + max(d * 0.55, 0.002);
        if (t > 2.8) { break; }
    }

    var bgColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    var finalRGB = bgColor;
    var finalAlpha = 0.0;

    if (hit) {
        let WAVELENGTHS = array<f32, 4>(450.0, 520.0, 600.0, 680.0);
        var spectralColor = vec3<f32>(0.0);
        var tirFire = vec3<f32>(0.0);
        let viewDotNormal = dot(-rd, normal);
        let baseEta = 1.0 / (1.52 + bass * 0.08);

        // Idea 1: Back-face exit march through glass interior for two-interface Snell refraction & TIR
        let pEnter = ro + rd * enterT;
        let innerDir = refractRay(rd, normal, baseEta);
        var exitStep = 0.08 * thicknessScale;
        for (var k: i32 = 0; k < 6; k = k + 1) {
            let pIn = pEnter + innerDir * exitStep;
            let dIn = map(pIn, time, bass, mids, holdEffect);
            exitStep = exitStep + max(-dIn * 0.65, 0.025);
        }
        let pExit = pEnter + innerDir * clamp(exitStep, 0.06, 0.65);
        let exitNormal = -calcNormal(pExit, time, bass, mids, holdEffect);
        let pathLen = clamp(length(pExit - pEnter) * thicknessScale * 2.2, 0.15, 1.8);

        // Idea 2: Dispersion-focused spectral caustic convergence from front/back curvature lens power
        let curvatureFocus = clamp(1.0 + length(normal.xy + exitNormal.xy) * 0.95, 0.75, 2.15);

        for (var w: i32 = 0; w < 4; w = w + 1) {
            let ior = cauchyIOR(WAVELENGTHS[w], 1.5, cauchyB);
            let eta = 1.0 / ior;
            let refracted1 = refractRay(rd, normal, eta);
            let exitCos = abs(dot(refracted1, exitNormal));
            let sinTheta2Sq = (ior * ior) * max(0.0, 1.0 - exitCos * exitCos);
            let tirWeight = smoothstep(0.78, 1.06, sinTheta2Sq);
            let refracted2 = refractRay(refracted1, exitNormal, ior);
            let combinedRay = mix(refracted1, refracted2, 0.55);
            let refractUV = clamp(uv + combinedRay.xy * 0.25 * pathLen, vec2<f32>(0.0), vec2<f32>(1.0));

            let sampleColor = textureSampleLevel(readTexture, u_sampler, refractUV, 0.0).rgb;
            let absorption = exp(-pathLen * (4.0 - f32(w)) * 0.14);
            let bandRGB = wavelengthToRGB(WAVELENGTHS[w]);
            let bandIntensity = dot(sampleColor, bandRGB) * absorption * curvatureFocus;
            spectralColor = spectralColor + bandRGB * bandIntensity;
            tirFire = tirFire + bandRGB * tirWeight * (0.45 + cauchyB * 4.5);
        }

        let fresnelFactor = fresnel(viewDotNormal, baseEta);
        // Brewster-angle s/p polarization highlight around cos(theta_B) ~ 0.55
        let brewsterGlint = exp(-pow((abs(viewDotNormal) - 0.55) * 6.5, 2.0)) * (1.0 - roughness);
        let glassTint = mix(vec3<f32>(0.94, 0.98, 1.0), vec3<f32>(1.0, 0.92, 0.97), treble);
        let absorption = exp(-vec3<f32>(0.1, 0.05, 0.15) * pathLen);

        finalRGB = mix(spectralColor * absorption * glassTint * 1.5, bgColor, fresnelFactor * (1.0 - transparency));
        finalRGB = finalRGB + tirFire * (0.55 + treble * 0.35);

        // Specular highlight
        let lightDir = normalize(vec3<f32>(0.5, 0.9, -0.6));
        let halfDir = normalize(lightDir - rd);
        let specAngle = max(dot(normal, halfDir), 0.0);
        let specular = pow(specAngle, 64.0) * (1.0 - roughness);
        finalRGB = finalRGB + vec3<f32>(1.0) * specular * 0.9 + vec3<f32>(0.3, 0.6, 1.0) * treble * 0.4 * fresnelFactor + vec3<f32>(0.85, 0.95, 1.0) * brewsterGlint * 0.22;

        finalAlpha = mix(0.3, 0.96, (1.0 - transparency) + fresnelFactor * 0.4 + holdEffect * 0.2);
    } else {
        finalAlpha = clamp(clickImpulse * 0.3 + holdEffect * 0.2 + depth * 0.2, 0.1, 0.6);
    }

    // Internal edge glow
    var edgeGlow = 0.0;
    if (hit) {
        edgeGlow = smoothstep(0.06, 0.0, map(ro + rd * enterT, time, bass, mids, holdEffect)) * (0.4 + mids * 0.4);
    }
    finalRGB = finalRGB + vec3<f32>(0.35, 0.75, 1.0) * edgeGlow * (1.0 + holdEffect);
    finalAlpha = max(finalAlpha, edgeGlow);

    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.25;
    finalRGB = finalRGB * vignette;

    // Exact temporal feedback from dataTextureC
    let prev = textureLoad(dataTextureC, pixel, 0).rgb;
    finalRGB = mix(finalRGB, prev, 0.1 + mids * 0.06);

    let tonemapped = acesToneMap(finalRGB * (1.0 + treble * 0.1));
    let outputRGBA = vec4<f32>(tonemapped, clamp(finalAlpha, 0.15, 0.98));

    textureStore(writeTexture, pixel, outputRGBA);
    textureStore(dataTextureA, pixel, outputRGBA);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
