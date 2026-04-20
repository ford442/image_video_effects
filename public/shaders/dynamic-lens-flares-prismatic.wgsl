// ═══════════════════════════════════════════════════════════════════
//  dynamic-lens-flares-prismatic
//  Category: advanced-hybrid
//  Features: lens-flares, prismatic-dispersion, spectral-rendering, mouse-driven
//  Complexity: Very High
//  Chunks From: dynamic-lens-flares.wgsl, spec-prismatic-dispersion.wgsl
//  Created: 2026-04-18
//  By: Agent CB-19 — Lighting & Energy Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Cinematic lens flares with physical prismatic dispersion.
//  Ghost elements refract through a virtual glass lens using
//  Cauchy's equation, creating chromatic splitting of flare colors.
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

// ═══ CHUNK: hash12 (from spec-prismatic-dispersion.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: cauchyIOR (from spec-prismatic-dispersion.wgsl) ═══
fn cauchyIOR(wavelengthNm: f32, A: f32, B: f32) -> f32 {
    let lambdaUm = wavelengthNm * 0.001;
    return A + B / (lambdaUm * lambdaUm);
}

// ═══ CHUNK: wavelengthToRGB (from spec-prismatic-dispersion.wgsl) ═══
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let aspect = res.x / res.y;
    let time = u.config.x;

    // Params
    let intensity = mix(0.1, 1.5, u.zoom_params.x);
    let threshold = mix(0.0, 0.9, u.zoom_params.y);
    let spread = mix(0.1, 2.0, u.zoom_params.z);
    let ghostCount = mix(2.0, 8.0, u.zoom_params.w);
    let cauchyB = mix(0.01, 0.08, u.zoom_params.z);
    let spectralSat = mix(0.3, 1.2, u.zoom_params.w);

    let mouse = u.zoom_config.yz;
    let center = vec2<f32>(0.5, 0.5);
    let axis = center - mouse;

    let lightColorFull = textureSampleLevel(readTexture, u_sampler, mouse, 0.0).rgb;
    let maxRGB = max(lightColorFull.r, max(lightColorFull.g, lightColorFull.b));
    var lightColor = vec3<f32>(0.0);
    if (maxRGB > threshold) {
        lightColor = lightColorFull * intensity;
    }
    lightColor = max(lightColor, vec3<f32>(0.05));

    // Render Ghosts with prismatic dispersion
    var flareAccum = vec3<f32>(0.0);
    let WAVELENGTHS = array<f32, 4>(450.0, 520.0, 600.0, 680.0);

    for (var i = 0.0; i < 8.0; i = i + 1.0) {
        if (i >= ghostCount) { break; }
        let scale = -1.0 + (i * 0.5);
        let offset = axis * (scale * spread);
        let ghostPos = center + offset;

        let uv_aspect = vec2<f32>((uv.x - 0.5) * aspect + 0.5, uv.y);
        let ghostPos_aspect = vec2<f32>((ghostPos.x - 0.5) * aspect + 0.5, ghostPos.y);
        let d = distance(uv_aspect, ghostPos_aspect);

        let size = 0.05 + 0.1 * sin(i * 123.4);
        let softness = 0.02;
        let weight = smoothstep(size + softness, size, d);

        // ═══ Prismatic dispersion per ghost ═══
        var prismaticGhost = vec3<f32>(0.0);
        for (var j: i32 = 0; j < 4; j = j + 1) {
            let ior = cauchyIOR(WAVELENGTHS[j], 1.5, cauchyB);
            let refractedUV = refractThroughSurface(uv, ghostPos, ior, 0.5);
            let wrappedUV = fract(refractedUV);
            let sample = textureSampleLevel(readTexture, u_sampler, wrappedUV, 0.0);
            let absorption = exp(-0.5 * (4.0 - f32(j)) * 0.15);
            let bandIntensity = dot(sample.rgb, wavelengthToRGB(WAVELENGTHS[j])) * absorption;
            prismaticGhost += wavelengthToRGB(WAVELENGTHS[j]) * bandIntensity * spectralSat;
        }

        let hueShift = i * 0.5;
        let r = cos(hueShift) * 0.5 + 0.5;
        let g = cos(hueShift + 2.0) * 0.5 + 0.5;
        let b = cos(hueShift + 4.0) * 0.5 + 0.5;
        let ghostColor = vec3<f32>(r, g, b) * lightColor;

        let dispersedColor = mix(ghostColor, prismaticGhost * lightColor, 0.4);
        flareAccum += dispersedColor * weight * 0.3;
    }

    // Halo / Ring
    let distToMouse = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(mouse.x * aspect, mouse.y));
    let ringRadius = 0.3 * spread;
    let ringWidth = 0.02;
    let ring = smoothstep(ringRadius + ringWidth, ringRadius, distToMouse) - smoothstep(ringRadius, ringRadius - ringWidth, distToMouse);
    flareAccum = flareAccum + lightColor * ring * 0.2;

    // Starburst / Rays
    let dirToMouse = normalize(uv - mouse);
    let angle = atan2(dirToMouse.y, dirToMouse.x);
    let ray = max(0.0, sin(angle * 12.0 + time) * sin(angle * 5.0 - time * 0.5));
    let rayFalloff = 1.0 / (distToMouse * 10.0 + 0.1);
    flareAccum = flareAccum + lightColor * ray * rayFalloff * 0.2;

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let finalColor = baseColor + flareAccum;

    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(flareAccum, 1.0));
}
