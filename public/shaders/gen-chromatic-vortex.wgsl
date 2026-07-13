// ═══════════════════════════════════════════════════════════════════════════════
//  Chromatic Vortex — Polar Distortion + Color-Space Warp + Temporal + Visualist
//  Category: generative
//  Features: mouse-driven, audio-reactive, temporal, chromatic, depth-aware,
//            ACES tone mapping, volumetric fog, iridescent Fresnel, bloom
//  Complexity: High
//  Upgraded: 2026-07-13
// ═══════════════════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash(i);
    let b = hash(i + vec2<f32>(1.0, 0.0));
    let c = hash(i + vec2<f32>(0.0, 1.0));
    let d = hash(i + vec2<f32>(1.0, 1.0));
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// ── Linear sRGB ↔ OkLab (simplified but perceptually uniform) ──
fn srgb_to_oklab(c: vec3<f32>) -> vec3<f32> {
    let lms = mat3x3<f32>(
        0.8189330101, 0.3618667424, -0.1288597137,
        0.0329845436, 0.9293118715, 0.0361456387,
        0.0482003018, 0.2643662691, 0.6338517070
    ) * c;
    let lms_ = pow(abs(lms), vec3<f32>(1.0 / 3.0)) * sign(lms);
    return mat3x3<f32>(
        0.2104542553, 0.7936177850, -0.0040720468,
        1.9779984951, -2.4285922050, 0.4505937099,
        0.0259040371, 0.7827717662, -0.8086757660
    ) * lms_;
}

fn oklab_to_srgb(c: vec3<f32>) -> vec3<f32> {
    let lms_ = mat3x3<f32>(
        1.0, 0.3963377774, 0.2158037573,
        1.0, -0.1055613458, -0.0638541728,
        1.0, -0.0894841775, -1.2914855480
    ) * c;
    let lms = lms_ * lms_ * lms_;
    return mat3x3<f32>(
        1.2270138510, -0.5577992887, 0.2812561490,
        -0.0405801784, 1.1122568696, -0.0716766787,
        -0.0763812845, -0.4214819784, 1.5861632204
    ) * lms;
}

// ── ACES Filmic tone mapping (approx) ──
fn aces_fitted(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c2 = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c2 * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ── Color temperature shift: warm/cool driven by audio ──
fn color_temp(c: vec3<f32>, temp: f32) -> vec3<f32> {
    let warm = vec3<f32>(1.14, 0.96, 0.78);
    let cool = vec3<f32>(0.78, 0.92, 1.14);
    let tint = mix(cool, warm, clamp(temp, 0.0, 1.0));
    return c * tint;
}

// ── Thin-film iridescent Fresnel on vortex rim ──
fn iridescent_fresnel(r: f32, time: f32, audio: f32) -> vec3<f32> {
    let rim = pow(1.0 - clamp(r * 1.4, 0.0, 1.0), 3.0);
    let phase = time * 0.5 + r * 12.0 + audio * 4.0;
    let irid = vec3<f32>(
        0.5 + 0.5 * cos(phase),
        0.5 + 0.5 * cos(phase + 2.094),
        0.5 + 0.5 * cos(phase + 4.189)
    );
    return irid * rim * (0.8 + audio * 0.6);
}

// ── Hex-bokeh-ish highlight bloom approximation ──
fn hex_bloom(uv: vec2<f32>, radius: f32) -> vec3<f32> {
    var acc = vec3<f32>(0.0);
    let hex = array<vec2<f32>, 6>(
        vec2<f32>(1.0, 0.0),
        vec2<f32>(0.5, 0.866),
        vec2<f32>(-0.5, 0.866),
        vec2<f32>(-1.0, 0.0),
        vec2<f32>(-0.5, -0.866),
        vec2<f32>(0.5, -0.866)
    );
    for (var i: i32 = 0; i < 6; i = i + 1) {
        let samp = uv + hex[i] * radius;
        let col = textureSampleLevel(readTexture, u_sampler, clamp(samp, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
        acc = acc + max(col - vec3<f32>(0.6), vec3<f32>(0.0));
    }
    return acc / 6.0;
}

// ── Volumetric fog / Mie scattering along tunnel ──
fn volumetric_fog(uv: vec2<f32>, center: vec2<f32>, r: f32, time: f32, bass: f32) -> vec3<f32> {
    var fog = vec3<f32>(0.0);
    let steps = 8.0;
    for (var t: f32 = 0.0; t < 1.0; t = t + 1.0 / steps) {
        let p = mix(center, uv, t);
        let d = length(p - center);
        let ray = sin(d * 20.0 - time * 2.0 + bass * 4.0) * 0.5 + 0.5;
        let density = exp(-d * 3.0) * ray * (0.5 + bass * 0.5);
        fog = fog + vec3<f32>(0.15, 0.12, 0.25) * density;
    }
    return fog / steps;
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

    let center = u.zoom_config.yz;

    let swirlStrength = u.zoom_params.x * 8.0 + bass * 2.0;
    let radiusScale = u.zoom_params.y * 3.0 + 0.5;
    let polarDistort = u.zoom_params.z * 2.0;
    let colorWarp = u.zoom_params.w;

    let delta = uv - center;
    let r = length(delta);
    let theta = atan2(delta.y, delta.x);

    // Temporal spiral drift: previous frame angle blends in
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let prevAngle = prev.z;
    let temporalDrift = mix(theta, prevAngle, 0.03 + bass * 0.01);

    let spiral = temporalDrift + swirlStrength * r * radiusScale + time * 0.3;
    let warpedR = r + polarDistort * sin(spiral * 3.0 + time) * 0.1;

    let sectors = 6.0 + floor(bass * 4.0);
    let foldedTheta = fract(spiral / 6.28318 * sectors) / sectors * 6.28318;

    // Chromatic sector dispersion: R/B sample at different sector offsets
    let rOffset = treble * 0.02 / sectors;
    let bOffset = -bass * 0.02 / sectors;
    let thetaR = fract((spiral + rOffset) / 6.28318 * sectors) / sectors * 6.28318;
    let thetaB = fract((spiral + bOffset) / 6.28318 * sectors) / sectors * 6.28318;

    let warpedUVR = center + vec2<f32>(cos(thetaR), sin(thetaR)) * warpedR;
    let warpedUVB = center + vec2<f32>(cos(thetaB), sin(thetaB)) * warpedR;
    let warpedUVG = center + vec2<f32>(cos(foldedTheta), sin(foldedTheta)) * warpedR;

    let sampleUVR = abs(fract(warpedUVR * 2.0) - 0.5) * 2.0;
    let sampleUVG = abs(fract(warpedUVG * 2.0) - 0.5) * 2.0;
    let sampleUVB = abs(fract(warpedUVB * 2.0) - 0.5) * 2.0;

    let colR = textureSampleLevel(readTexture, u_sampler, clamp(sampleUVR, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let colG = textureSampleLevel(readTexture, u_sampler, clamp(sampleUVG, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    let colB = textureSampleLevel(readTexture, u_sampler, clamp(sampleUVB, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    var col = vec3<f32>(colR, colG, colB);

    // OkLab color-space warp with smoother hue rotation
    var lab = srgb_to_oklab(max(col, vec3<f32>(0.0)));
    let hueShift = time * 0.2 + bass * 1.5 + colorWarp * 3.14159;
    let chroma = length(lab.yz);
    let luma = lab.x;
    let newHue = atan2(lab.z, lab.y) + hueShift;
    lab.y = chroma * cos(newHue) * (1.0 + mids * 0.25);
    lab.z = chroma * sin(newHue) * (1.0 + mids * 0.25);
    lab.x = luma * (1.0 + treble * 0.35);
    var outCol = oklab_to_srgb(lab);

    // Dynamic color temperature driven by bass (warm) / treble (cool)
    let tempDrive = clamp(bass * 0.7 - treble * 0.3 + 0.5, 0.0, 1.0);
    outCol = color_temp(outCol, tempDrive);

    // Iridescent Fresnel rim on swirling boundaries
    outCol = outCol + iridescent_fresnel(r, time, bass) * (0.5 + mids * 0.5);

    // Hex-bokeh bloom on highlights
    let bloom = hex_bloom(uv, 0.008 + treble * 0.012);
    outCol = outCol + bloom * (0.4 + bass * 0.4);

    // Volumetric fog / light rays along the vortex tunnel
    let fog = volumetric_fog(uv, center, r, time, bass);
    outCol = outCol + fog * (1.0 - depth * 0.5);

    // Vignette and radial streak accents
    let vig = 1.0 - smoothstep(0.3, 1.0, r);
    outCol = outCol * (0.7 + 0.3 * vig);

    let streak = pow(sin(spiral * sectors + time * 2.0) * 0.5 + 0.5, 4.0);
    outCol = outCol + vec3<f32>(streak * bass * 0.25);

    // Allow HDR headroom, then ACES tone map
    outCol = outCol * (1.0 + bass * 0.35);
    outCol = aces_fitted(outCol);

    // Temporal persistence blend
    let prevCol = prev.rgb;
    outCol = mix(outCol, prevCol * 0.92, 0.04 + mids * 0.02);

    let effectStrength = clamp(streak * bass + r * 0.5, 0.0, 1.0);
    let alpha = clamp(mix(0.5, 1.0, effectStrength) * (1.0 - depth * 0.2), 0.0, 1.0);

    textureStore(writeTexture, id.xy, vec4<f32>(outCol, alpha));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, id.xy, vec4<f32>(outCol, alpha));
}
