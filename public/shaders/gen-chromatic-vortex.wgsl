// ═══════════════════════════════════════════════════════════════════════════════
//  Chromatic Vortex — Polar Distortion + Color-Space Warp + Temporal
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba, temporal, chromatic, depth-aware
//  Complexity: High
//  Upgraded: 2026-10-05
//  Ideas: 1) mirror-fold sectors with a glint on the fold line;
//         2) breathing radial dispersion (per-channel radius offset by d/dr of the warp);
//         3) hue-carrying arms (arm streak tinted by its sector's rotated YUV chroma)
//  A packing: ACES display RGBA (alpha = vortex arm/glint coverage)
// ═══════════════════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn rgb2yuv(c: vec3<f32>) -> vec3<f32> {
    let y = dot(c, vec3<f32>(0.299, 0.587, 0.114));
    let u_ = dot(c, vec3<f32>(-0.14713, -0.28886, 0.436));
    let v = dot(c, vec3<f32>(0.615, -0.51499, -0.10001));
    return vec3<f32>(y, u_, v);
}

fn yuv2rgb(c: vec3<f32>) -> vec3<f32> {
    let r = c.x + 1.13983 * c.z;
    let g = c.x - 0.39465 * c.y - 0.58060 * c.z;
    let b = c.x + 2.03211 * c.y;
    return vec3<f32>(r, g, b);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Idea 1: mirror fold — triangle wave over sector index, so neighbouring
// sectors are mirror images instead of a sawtooth seam. Returns [0,1].
fn mirrorFold(f: f32) -> f32 {
    let m = fract(f * 0.5) * 2.0;
    return 1.0 - abs(m - 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = u.config.zw;
    if (id.x >= u32(res.x) || id.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(id.xy) / res;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Mouse uv defaults to (0.5, 0.5) before the first move -> centred vortex.
    let center = u.zoom_config.yz;
    let aspect = res.x / max(res.y, 1.0);
    let aspectV = vec2<f32>(aspect, 1.0);

    let swirlStrength = u.zoom_params.x * 8.0 + bass * 2.0;
    let radiusScale = u.zoom_params.y * 3.0 + 0.5;
    let polarDistort = u.zoom_params.z * 2.0;
    let colorWarp = u.zoom_params.w;

    // Aspect-correct radius (circular vortex on non-square frames).
    let delta = (uv - center) * aspectV;
    let r = length(delta);
    let theta = atan2(delta.y, delta.x);

    let spiral = theta + swirlStrength * r * radiusScale + time * 0.3;
    let warpPhase = spiral * 3.0 + time;
    let warpedR = r + polarDistort * sin(warpPhase) * 0.1;

    // Even sector count keeps the mirror fold continuous across atan2's cut.
    let sectors = 6.0 + 2.0 * floor(clamp(bass, 0.0, 1.0) * 2.0);
    let sectorF = spiral / 6.28318 * sectors;
    let foldedTheta = mirrorFold(sectorF) / sectors * 6.28318;

    // Chromatic sector dispersion: R/B sample at different sector offsets
    let rOffset = treble * 0.02 / sectors;
    let bOffset = -bass * 0.02 / sectors;
    let thetaR = mirrorFold((spiral + rOffset) / 6.28318 * sectors) / sectors * 6.28318;
    let thetaB = mirrorFold((spiral + bOffset) / 6.28318 * sectors) / sectors * 6.28318;

    // Idea 2: breathing radial dispersion — d/dr of sin(spiral*3 + t) is
    // cos(..) * 3 * dSpiral/dr; R and B radii slide apart along the arms
    // with that slope, so the split pulses outward even with silent audio.
    let dSpiralDr = swirlStrength * radiusScale;
    let slope = cos(warpPhase) * min(3.0 * dSpiralDr, 6.0) / 6.0;
    let breathe = 0.0045 * (1.0 + polarDistort) * (1.0 + treble * 1.5 + bass * 0.5);
    let warpedRR = warpedR + slope * breathe;
    let warpedRB = warpedR - slope * breathe;

    let warpedUVR = center + vec2<f32>(cos(thetaR), sin(thetaR)) * warpedRR / aspectV;
    let warpedUVB = center + vec2<f32>(cos(thetaB), sin(thetaB)) * warpedRB / aspectV;
    let warpedUVG = center + vec2<f32>(cos(foldedTheta), sin(foldedTheta)) * warpedR / aspectV;

    let sampleUVR = abs(fract(warpedUVR * 2.0) - 0.5) * 2.0;
    let sampleUVG = abs(fract(warpedUVG * 2.0) - 0.5) * 2.0;
    let sampleUVB = abs(fract(warpedUVB * 2.0) - 0.5) * 2.0;

    let colR = textureSampleLevel(readTexture, u_sampler, clamp(sampleUVR, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let colG = textureSampleLevel(readTexture, u_sampler, clamp(sampleUVG, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    let colB = textureSampleLevel(readTexture, u_sampler, clamp(sampleUVB, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    let srcA = textureSampleLevel(readTexture, u_sampler, clamp(sampleUVG, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).a;
    var col = vec3<f32>(colR, colG, colB);

    // Color-space warp (true rotation: both chroma axes use the old values).
    var yuv = rgb2yuv(col);
    let hueShift = time * 0.2 + bass * 1.5 + colorWarp * 3.14159;
    let cosH = cos(hueShift);
    let sinH = sin(hueShift);
    let u0 = yuv.y;
    let v0 = yuv.z;
    yuv.y = u0 * cosH - v0 * sinH;
    yuv.z = u0 * sinH + v0 * cosH;

    yuv.x = yuv.x * (1.0 + treble * 0.5);
    yuv.y = yuv.y * (1.0 + mids * 0.3);
    yuv.z = yuv.z * (1.0 + mids * 0.3);

    var outCol = yuv2rgb(yuv);

    let vig = 1.0 - smoothstep(0.3, 1.0, r);
    outCol = outCol * (0.7 + 0.3 * vig);

    // Idea 3: hue-carrying arms — the arm streak takes the rotated YUV
    // chroma of its own sector (falls back to the sector's rotated hue
    // direction where the image is grey) instead of an additive white.
    let streakBase = sin(spiral * sectors + time * 2.0) * 0.5 + 0.5;
    let streak = streakBase * streakBase * streakBase * streakBase;
    let sectorIdx = floor(sectorF);
    let sectorHue = hueShift + sectorIdx * 6.28318 / sectors;
    let chromaLen = length(yuv.yz);
    let chromaDir = mix(vec2<f32>(cos(sectorHue), sin(sectorHue)),
                        yuv.yz / max(chromaLen, 1e-4),
                        smoothstep(0.02, 0.08, chromaLen));
    let armTint = max(yuv2rgb(vec3<f32>(0.55, chromaDir * 0.28)), vec3<f32>(0.0));
    let armAmt = streak * (0.08 + bass * 0.3);
    outCol = outCol + armTint * armAmt;

    // Idea 1: thin glint on the mirror line (arc distance to the fold).
    let tri = mirrorFold(sectorF);
    let foldArc = min(tri, 1.0 - tri) / sectors * 6.28318 * max(r, 0.02);
    let glint = smoothstep(0.006, 0.0, foldArc) * smoothstep(0.02, 0.12, r);
    outCol = outCol + glint * (0.12 + 0.35 * max(outCol, vec3<f32>(0.0)));

    // ACES on display RGB (negatives from YUV clamped first).
    var display = acesToneMap(max(outCol, vec3<f32>(0.0)));

    // Temporal persistence blend (display to display, exact texel load)
    let prev = textureLoad(dataTextureC, vec2<i32>(id.xy), 0);
    display = mix(display, prev.rgb * 0.92, 0.04 + mids * 0.02);

    // Semantic alpha: source coverage x how much arm/glint structure is here.
    let effectStrength = clamp(armAmt * 2.0 + glint + r * 0.5, 0.0, 1.0);
    let alpha = clamp(mix(0.5, 1.0, effectStrength) * (1.0 - depth * 0.2) * srcA, 0.0, 1.0);

    textureStore(writeTexture, id.xy, vec4<f32>(display, alpha));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, id.xy, vec4<f32>(display, alpha));
}
