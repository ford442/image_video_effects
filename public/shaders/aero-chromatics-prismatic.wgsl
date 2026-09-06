// ═══════════════════════════════════════════════════════════════════
//  Aero Chromatics Prismatic
//  Category: advanced-hybrid
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-06
//  Ideas: aerodynamic vortex shedding plumes; Schlieren velocity gradient refraction; wavelength-differential feedback trails
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ Cauchy IOR ═══
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

fn refractThroughSurface(uv: vec2<f32>, center: vec2<f32>, ior: f32, curvature: f32) -> vec2<f32> {
    let toCenter = uv - center;
    let dist = length(toCenter);
    let lensStrength = curvature * 0.4;
    let offset = toCenter * (1.0 - 1.0 / ior) * lensStrength * (1.0 + dist * 2.0);
    return uv + offset;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
    let pixel = vec2<i32>(gid.xy);

    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let aspect = res.x / max(res.y, 1.0);
    let time = u.config.x;
    let mouse = u.zoom_config.yz;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Parameters
    let windStrength = mix(0.5, 5.0, u.zoom_params.x);
    let decay = mix(0.8, 0.995, u.zoom_params.y);
    let chromaSplit = u.zoom_params.z * 0.03;
    let sourceMix = mix(0.01, 0.2, u.zoom_params.w);

    // Glass curvature from wind strength
    let glassCurvature = mix(0.1, 0.8, u.zoom_params.x) * (1.0 + bass * 0.25);
    let cauchyB = mix(0.01, 0.06, u.zoom_params.z) * (1.0 + treble * 0.2);
    let spectralSat = mix(0.3, 1.2, u.zoom_params.w) * (1.0 + mids * 0.2);

    let currentFrame = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(currentFrame.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Wind vector
    let dVec = uv - mouse;
    let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));
    let mouseInfluence = smoothstep(0.5, 0.0, dist);
    let baseWind = vec2<f32>(0.0, -0.001);
    let mouseWind = normalize(dVec + vec2<f32>(1e-4, 0.0)) * 0.01 * mouseInfluence * windStrength;

    // ─── Native Idea 1: Aerodynamic Vortex Shedding ───
    // Curl-noise rotational eddies in the wind slipstream
    let vortexPhase = time * (1.5 + windStrength * 0.5);
    let curlX = sin(uv.y * 16.0 + vortexPhase) - cos(uv.x * 14.0);
    let curlY = cos(uv.x * 16.0 - vortexPhase) + sin(uv.y * 14.0);
    let vortexShedding = vec2<f32>(curlX, curlY) * (0.0025 + bass * 0.004) * mouseInfluence;

    let velocity = (baseWind + mouseWind + vortexShedding) * (luma * 2.0);

    // ─── Native Idea 3: Wavelength-Differential Feedback Decay ───
    // Chromatic advection pixel coordinates
    let offsetR = velocity * (1.0 + chromaSplit);
    let offsetG = velocity;
    let offsetB = velocity * (1.0 - chromaSplit);

    let resI = vec2<i32>(res);
    let coordR = clamp(vec2<i32>(floor((uv - offsetR) * res)), vec2<i32>(0), resI - 1);
    let coordG = clamp(vec2<i32>(floor((uv - offsetG) * res)), vec2<i32>(0), resI - 1);
    let coordB = clamp(vec2<i32>(floor((uv - offsetB) * res)), vec2<i32>(0), resI - 1);

    let prevR = textureLoad(dataTextureC, coordR, 0).r;
    let prevG = textureLoad(dataTextureC, coordG, 0).g;
    let prevB = textureLoad(dataTextureC, coordB, 0).b;

    // Differential decay: red lingers slightly longer than violet in aerodynamic wake
    let decayR = clamp(decay * (1.0 + chromaSplit * 0.4), 0.0, 0.998);
    let decayG = decay;
    let decayB = clamp(decay * (1.0 - chromaSplit * 0.4), 0.0, 0.998);

    let historyColor = vec3<f32>(prevR * decayR, prevG * decayG, prevB * decayB);
    let injectAmount = sourceMix * luma;
    var advectedColor = mix(historyColor, currentFrame.rgb, injectAmount);
    advectedColor = max(vec3<f32>(0.0), advectedColor);

    // ═══ Prismatic Dispersion ═══
    let lensCenter = mouse;
    let WAVELENGTHS = array<f32, 4>(450.0, 520.0, 600.0, 680.0);
    var prismaticColor = vec3<f32>(0.0);

    for (var i: i32 = 0; i < 4; i = i + 1) {
        let ior = cauchyIOR(WAVELENGTHS[i], 1.5, cauchyB);
        let refractedUV = refractThroughSurface(uv, lensCenter, ior, glassCurvature);
        let wrappedUV = clamp(refractedUV, vec2<f32>(0.001), vec2<f32>(0.999));
        let sample = textureSampleLevel(readTexture, u_sampler, wrappedUV, 0.0);
        let absorption = exp(-glassCurvature * (4.0 - f32(i)) * 0.15);
        let bandIntensity = dot(sample.rgb, wavelengthToRGB(WAVELENGTHS[i])) * absorption;
        prismaticColor += wavelengthToRGB(WAVELENGTHS[i]) * bandIntensity * spectralSat;
    }

    // ─── Native Idea 2: Schlieren Velocity Gradient Refraction ───
    // Physical optical bending caused by air density / speed gradients
    let speedMag = length(velocity);
    let schlierenDir = normalize(velocity + vec2<f32>(1e-4, 0.0));
    let schlierenOffset = schlierenDir * speedMag * 6.0;
    let schlierenSample = textureSampleLevel(readTexture, u_sampler, clamp(uv + schlierenOffset, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).rgb;
    let schlierenMix = smoothstep(0.002, 0.02, speedMag) * 0.45;
    advectedColor = mix(advectedColor, schlierenSample, schlierenMix);

    // Blend advected smoke with prismatic tint
    let lumaFinal = dot(advectedColor, vec3<f32>(0.299, 0.587, 0.114));
    let prismaticBlend = smoothstep(0.1, 0.5, lumaFinal) * mouseInfluence;
    var finalColor = mix(advectedColor, prismaticColor, prismaticBlend * 0.6);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let alpha = clamp(mix(0.65, 0.98, lumaFinal) + length(prismaticColor) * 0.2, 0.1, 1.0);
    let finalAlpha = mix(alpha * 0.8, alpha, depth);

    let outRGB = acesToneMap(finalColor);
    let outRGBA = vec4<f32>(outRGB, finalAlpha);

    textureStore(dataTextureA, pixel, outRGBA);
    textureStore(writeTexture, pixel, outRGBA);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
