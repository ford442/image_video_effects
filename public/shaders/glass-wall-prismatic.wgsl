// ═══════════════════════════════════════════════════════════════════
//  Glass Wall Prismatic
//  Category: advanced-hybrid
//  Features: mouse-driven, spectral-rendering, physical-dispersion,
//            refraction, audio-reactive, exact-feedback, temporal-state, upgraded-rgba
//  Complexity: Very High
//  Upgraded: 2026-11-09
//  Ideas: cast-glass wedge per tile (every flat tile is a slightly different prism); Fresnel-Schlick bevel sheen with a soft-box reflection (§12.2F, the HEAD Fresnel term only ever reached alpha); prismatic lamp lobe split per channel by the Cauchy index
//  Rescued: pointer state lived in extraBuffer[133..138] (re-uploaded zeroed every frame, written by thread (0,0) and read by all others: racy, tilt point ~(0,0) in the app) -> A texels; the 4-band spectral basis was not white-balanced (flat tile = red filter, neutral photo mean (0.43,0.40,0.39) -> (0.65,0.36,0.35)); history now mixed in display space after ACES
//  A packing: display RGBA (ACES) in A and writeTexture. Texels (0,0) = (pointer pos.xy, vel.xy) and (1,0) = (fract(lastTime), click impulse, prevDown, 0.7371 sentinel) are STATE in A only (top-left corner; writeTexture is unaffected), masked when C is read as colour history.
// ═══════════════════════════════════════════════════════════════════
//  A grid of glass tiles where each tile acts as a prismatic lens
//  with 4-band spectral dispersion via Cauchy's equation. Mouse
//  interaction tilts tiles with spring physics, refracting light
//  into rainbow spectra with mortar grooves and Fresnel highlights.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=GridSize, y=Curvature, z=Dispersion, w=Thickness

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

const SENT: f32 = 0.7371;
// Pointer spring (per-second form of HEAD's per-frame 0.18 / 0.82 spring: omega ~24 rad/s, zeta ~0.24 at 60 fps)
const SPRING_K: f32 = 600.0;
const SPRING_C: f32 = 12.0;
const IMPULSE_RATE: f32 = 3.7;    // exp(-3.7 dt) == HEAD's 0.94 per frame at 60 fps
const THICK_REF: f32 = 0.85;      // glassThickness at the default slider (mix(0.3, 1.4, 0.5))
const WEDGE_TILT: f32 = 0.6;      // Idea 1: peak-to-peak wedge tilt of a tile (normal units)
const LAMP_FRINGE: f32 = 2.4;     // Idea 3: how strongly the relative Cauchy index scales the facet slope per channel

fn acesToneMap(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
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

    // ── Pointer state in two A texels (R1) ──────────────────────────────
    // HEAD kept this in extraBuffer[133..138] written by thread (0,0): extraBuffer is re-uploaded zeroed every
    // frame and the other threads read it in the same dispatch, so the tilt point was ~(0,0)/racy in the app.
    // Texel (0,0) = (pos.xy, vel.xy); texel (1,0) = (fract(lastTime), click impulse, prevDown, SENT).
    // Every thread integrates the same step from the stored state; the sentinel guards the first frame / inherited C.
    // HEAD behaviour kept: the tilt point orbits a Lissajous unless the pointer is pressed (one frame past release
    // it still follows the cursor); the press edge fires a decaying impulse.
    let st0 = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
    let st1 = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
    let stateOk = abs(st1.w - SENT) < 0.001;
    let prevDown = select(0.0, st1.z, stateOk);
    let orbitPos = vec2<f32>(0.5 + 0.22 * sin(time * 0.7), 0.5 + 0.22 * cos(time * 0.85));
    let targetPos = select(clamp(mouseUV, vec2<f32>(0.0), vec2<f32>(1.0)), orbitPos, !isMouseDown && prevDown < 0.5);
    var sPos = select(targetPos, st0.xy, stateOk);
    var sVel = select(vec2<f32>(0.0), st0.zw, stateOk);
    let springDt = select(0.016, clamp(fract(time - st1.x), 0.001, 0.05), stateOk);
    sVel = sVel + ((targetPos - sPos) * SPRING_K - sVel * SPRING_C) * springDt;
    sVel = clamp(sVel, vec2<f32>(-3.0), vec2<f32>(3.0));
    sPos = clamp(sPos + sVel * springDt, vec2<f32>(0.0), vec2<f32>(1.0));
    // f16 rest-snap: a spring stored in rgba16float stalls ~2e-3 short with a residual velocity that never decays
    let settled = all(abs(targetPos - sPos) < vec2<f32>(0.004)) && length(sVel) < 0.06;
    sPos = select(sPos, targetPos, settled);
    sVel = select(sVel, vec2<f32>(0.0), settled);
    var impulse = select(0.0, st1.y, stateOk) * exp(-IMPULSE_RATE * springDt);
    if (isMouseDown && prevDown < 0.5) { impulse = 1.0; }

    let smoothMouse = sPos;
    let clickImpulse = impulse;

    let uv = (vec2<f32>(pixel) + 0.5) / res;
    let aspect = res.x / res.y;
    let aspectVec = vec2<f32>(aspect, 1.0);

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Sliders
    let gridSize = mix(6.0, 26.0, u.zoom_params.x);
    let glassCurvature = mix(0.15, 1.1, u.zoom_params.y);
    let cauchyB = mix(0.01, 0.08, u.zoom_params.z);
    let glassThickness = mix(0.3, 1.4, u.zoom_params.w);

    let distMouse = length((uv - smoothMouse) * aspectVec);
    let holdEffect = smoothstep(0.45, 0.0, distMouse) * select(0.35, 1.0, isMouseDown);

    // Capped click ripple fronts
    var rippleOffset = vec2<f32>(0.0);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let r = u.ripples[i];
        let rAge = time - r.z;
        if (r.z > 0.0 && rAge > 0.0 && rAge < 2.5) {
            let toRip = (uv - r.xy) * aspectVec;
            let rDist = length(toRip);
            let env = smoothstep(2.5, 0.0, rAge);
            let phase = rDist * 38.0 - rAge * 12.0;
            let wave = sin(phase) * exp(-rDist * 5.5) * env;
            rippleOffset = rippleOffset + normalize(toRip + vec2<f32>(0.001)) * wave * 0.04;
        }
    }
    rippleOffset = rippleOffset + normalize((uv - smoothMouse) * aspectVec + vec2<f32>(0.001)) * sin(distMouse * 32.0 - time * 8.0) * exp(-distMouse * 6.5) * clickImpulse * 0.03;

    let scale = vec2<f32>(gridSize * aspect, gridSize);
    let scaledUV = uv * scale + rippleOffset * scale * 0.25;
    let cellID = floor(scaledUV);
    let cellUV = fract(scaledUV);
    let cellCenter = (cellID + vec2<f32>(0.5)) / scale;

    let vecToMouse = (smoothMouse - cellCenter) * aspectVec;
    let distToCell = length(vecToMouse);
    let influence = smoothstep(0.85, 0.0, distToCell);

    var tilt = vec2<f32>(0.0);
    if (distToCell > 0.001) {
        tilt = normalize(vecToMouse) * influence * (0.45 + mids * 0.4 + holdEffect * 0.35);
    }

    // Bevel normal profile
    let bevelX = smoothstep(0.0, 0.12, cellUV.x) * (1.0 - smoothstep(0.88, 1.0, cellUV.x));
    let bevelY = smoothstep(0.0, 0.12, cellUV.y) * (1.0 - smoothstep(0.88, 1.0, cellUV.y));
    let bevel = bevelX * bevelY;

    let nx = -(smoothstep(0.0, 0.12, cellUV.x) - smoothstep(0.88, 1.0, cellUV.x)) * bevelY;
    let ny = -(smoothstep(0.0, 0.12, cellUV.y) - smoothstep(0.88, 1.0, cellUV.y)) * bevelX;
    var normal = normalize(vec3<f32>(nx, ny, 2.0));
    normal = normalize(normal + vec3<f32>(tilt * 2.2, 0.0) + vec3<f32>(rippleOffset * 8.0, 0.0));

    // ── Idea 1: cast-glass wedge ─────────────────────────────────────────
    // A cast tile is never perfectly flat: each one carries a slight, stable wedge, so every flat tile interior
    // throws its own refraction and spectrum (at HEAD only the bevel and the pointer tilt ever bent the light).
    // The amplitude rides the existing curvature / dispersion sliders through the offset pipeline below.
    let wedge = vec2<f32>(hash12(cellID + vec2<f32>(3.7, 11.1)), hash12(cellID.yx + vec2<f32>(19.3, 5.9))) - vec2<f32>(0.5);
    normal = normalize(normal + vec3<f32>(wedge * WEDGE_TILT, 0.0));

    let WAVELENGTHS = array<f32, 4>(450.0, 520.0, 600.0, 680.0);
    let cauchyBAudio = cauchyB + bass * 0.04;
    var dispersedNum = vec3<f32>(0.0);
    var whiteRef = vec3<f32>(0.0);

    for (var i: i32 = 0; i < 4; i = i + 1) {
        let ior = cauchyIOR(WAVELENGTHS[i], 1.5, cauchyBAudio);
        let refractDir = refract(vec3<f32>(0.0, 0.0, -1.0), normal, 1.0 / ior);
        let refractOffset = refractDir.xy * glassCurvature * 0.35;
        let refractedUV = clamp(uv + refractOffset, vec2<f32>(0.0), vec2<f32>(1.0));

        let tapCol = textureSampleLevel(readTexture, u_sampler, refractedUV, 0.0).rgb;
        let absorption = exp(-glassThickness * (4.0 - f32(i)) * 0.14);
        let absRef = exp(-THICK_REF * (4.0 - f32(i)) * 0.14);
        let wCol = wavelengthToRGB(WAVELENGTHS[i]);

        dispersedNum = dispersedNum + wCol * absorption * tapCol;
        whiteRef = whiteRef + wCol * absRef;
    }
    // R2: white-balanced spectral basis. HEAD summed the four band weights (~2.5, 1.0, 1.0 in R,G,B) and only
    // divided by the scalar absorption, so a tile that refracts nothing returned ~(1.5, 0.5, 0.5)·scene.
    // Dividing by the per-channel basis sum at the DEFAULT thickness makes zero refraction return the scene
    // colour exactly; the Thickness slider keeps its role as absorption relative to that default.
    let dispersedColor = dispersedNum / max(whiteRef, vec3<f32>(0.001));

    let glassColor = mix(vec3<f32>(0.93, 0.96, 1.0), vec3<f32>(1.0, 0.91, 0.96), treble);
    let thickness = 0.05 + (1.0 - bevel) * 0.1 + length(tilt) * 0.06;
    let absorptionGlass = exp(-(vec3<f32>(1.0) - glassColor) * thickness * 2.5);
    let transmission = (absorptionGlass.r + absorptionGlass.g + absorptionGlass.b) * 0.3333;

    var finalColor = dispersedColor * glassColor;

    // Fresnel reflection
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    let cosTheta = max(dot(viewDir, normal), 0.0);
    let R0 = 0.04;
    let fresnel = R0 + (1.0 - R0) * pow(1.0 - cosTheta, 4.5);

    // ── Idea 3: prismatic lamp ───────────────────────────────────────────
    // The lamp lobe is evaluated per channel with the facet slope scaled by that channel's relative Cauchy
    // index, (n(λ) − n(540)) / (n(540) − 1): the mirror condition is met at a different tilt for red and blue,
    // so the highlight carries a coloured rim ("fire") instead of one white blob. Same B slider as the loop.
    let lightDir = normalize(vec3<f32>(vecToMouse, 0.6));
    let iorRGB = vec3<f32>(cauchyIOR(620.0, 1.5, cauchyBAudio), cauchyIOR(540.0, 1.5, cauchyBAudio), cauchyIOR(460.0, 1.5, cauchyBAudio));
    let relDisp = (iorRGB - vec3<f32>(iorRGB.y)) / max(iorRGB.y - 1.0, 0.1);
    let slopeScale = vec3<f32>(1.0) + relDisp * LAMP_FRINGE;
    let nR = normalize(vec3<f32>(normal.xy * slopeScale.x, normal.z));
    let nG = normalize(vec3<f32>(normal.xy * slopeScale.y, normal.z));
    let nB = normalize(vec3<f32>(normal.xy * slopeScale.z, normal.z));
    let specRGB = vec3<f32>(
        pow(max(dot(nR, lightDir), 0.0), 36.0),
        pow(max(dot(nG, lightDir), 0.0), 36.0),
        pow(max(dot(nB, lightDir), 0.0), 36.0)) * influence * (1.0 + treble);
    finalColor = finalColor + specRGB * 0.85;

    // Mortar groove lines
    let mortar = smoothstep(0.0, 0.06, cellUV.x) * smoothstep(1.0, 0.94, cellUV.x) *
                 smoothstep(0.0, 0.06, cellUV.y) * smoothstep(1.0, 0.94, cellUV.y);
    let blendedTransmission = mix(transmission * 0.25, transmission, mortar);
    finalColor = mix(finalColor * 0.35, finalColor, mortar);

    // ── Idea 2: Fresnel-Schlick bevel sheen (§12.2F) ─────────────────────
    // HEAD computed `fresnel` and used it only for alpha. Promote it: the view ray bounces off the wedged,
    // tilted facet into a soft-box + sky environment; the reflected share F is taken from the transmitted light
    // (energy moved, not added) and vanishes in the mortar. Bevel facets facing the window glint, and the glint
    // slides as the pointer tilts the tiles.
    let reflDir = reflect(-viewDir, normal);
    let softBox = smoothstep(0.80, 0.97, dot(reflDir, normalize(vec3<f32>(-0.55, 0.60, 0.58))));
    let skyGrad = mix(vec3<f32>(0.10, 0.11, 0.14), vec3<f32>(0.38, 0.46, 0.58), clamp(reflDir.y * 0.5 + 0.5, 0.0, 1.0));
    let envRefl = skyGrad + vec3<f32>(1.0, 0.96, 0.88) * softBox * 7.0;
    finalColor = finalColor * (1.0 - fresnel * mortar) + envRefl * fresnel * mortar;

    let tonemapped = acesToneMap(max(finalColor, vec3<f32>(0.0)) * (1.0 + treble * 0.1));

    // Exact temporal feedback from dataTextureC. A (and so C) is display RGBA: the history is mixed in display
    // space after ACES (R3; HEAD blended it into the pre-ACES radiance = tone-mapped twice). The two state
    // texels hold pointer state, not colour, and are masked.
    let isStateTexel = pixel.y == 0 && pixel.x < 2;
    let prevData = textureLoad(dataTextureC, pixel, 0).rgb;
    let histW = select(0.1 + mids * 0.06, 0.0, isStateTexel);
    let shown = mix(tonemapped, prevData, histW);

    let alpha = clamp(blendedTransmission + fresnel * 0.4 + holdEffect * 0.2 + clickImpulse * 0.15, 0.2, 0.98);
    let outputRGBA = vec4<f32>(shown, alpha);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    var aOut = outputRGBA;
    if (pixel.y == 0 && pixel.x == 0) { aOut = vec4<f32>(sPos, sVel); }
    if (pixel.y == 0 && pixel.x == 1) { aOut = vec4<f32>(fract(time), impulse, select(0.0, 1.0, isMouseDown), SENT); }

    textureStore(writeTexture, pixel, outputRGBA);
    textureStore(dataTextureA, pixel, aOut);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
