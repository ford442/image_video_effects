// ═══════════════════════════════════════════════════════════════════
//  aerogel-smoke-hdr
//  Category: advanced-hybrid
//  Features: volumetric-scattering, HDR-bloom, rayleigh-mie, alpha-data
//  Complexity: High
//  Chunks From: aerogel-smoke.wgsl, alpha-hdr-bloom-chain.wgsl
//  Created: 2026-04-18
//  By: Agent CB-8 — Thermal & Atmospheric Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Aerogel volumetric smoke with HDR bloom enhancement. The ethereal
//  silica nanoparticle scattering is augmented by an HDR bloom kernel
//  that extracts and amplifies overbright regions, creating a luminous
//  glow around dense scattering zones.
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

// Physical constants for aerogel
const SIGMA_T_AEROGEL: f32 = 1.5;
const SIGMA_S_RAYLEIGH: f32 = 0.6;
const SIGMA_S_MIE: f32 = 0.7;
const STEP_SIZE: f32 = 0.025;
const MIE_G: f32 = 0.75;

// ═══ CHUNK: hash & noise (from aerogel-smoke.wgsl) ═══
fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    var i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2<f32>(0.0, 0.0)), hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec2<f32>(100.0);
    let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    var pp = p;
    for (var i = 0; i < 5; i++) {
        v += a * noise(pp);
        pp = rot * pp * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

fn phaseHG(cosTheta: f32, g: f32) -> f32 {
    let g2 = g * g;
    return (1.0 - g2) / (4.0 * 3.14159265 * pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5));
}

// ═══ CHUNK: toneMapACES (from alpha-hdr-bloom-chain.wgsl) ═══
fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let time = u.config.x;
    let aspect = res.x / res.y;
    let mouse = u.zoom_config.yz;

    // Parameters
    let densityMult = u.zoom_params.x * 2.0;
    let scattering = u.zoom_params.y;
    let glow = u.zoom_params.z;
    let bloomAmount = u.zoom_params.w;

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Generate aerogel density
    var p = uv * 3.0 + vec2<f32>(time * 0.05, time * 0.02);
    var density = fbm(p);
    density += fbm(p * 4.0) * 0.5;
    density += fbm(p * 8.0) * 0.25;
    density = smoothstep(0.2, 0.8, density) * densityMult;

    // Optical depth and transmittance
    let optical_depth = density * STEP_SIZE * SIGMA_T_AEROGEL;
    let transmittance = exp(-optical_depth);
    let alpha = 1.0 - transmittance;

    // Lighting
    let dist = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));
    let lightFalloff = 1.0 / (1.0 + dist * dist * 10.0);

    let lightDir = normalize(vec3<f32>(mouse - uv, 0.5));
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    let cosTheta = dot(viewDir, lightDir);

    let phaseR = 0.75 * (1.0 + cosTheta * cosTheta);
    let phaseM = phaseHG(cosTheta, MIE_G);
    let combinedPhase = mix(phaseR, phaseM, 0.5);

    let lightColor = vec3<f32>(0.9, 0.95, 1.0) * glow * lightFalloff;
    let scatterCoeff = mix(SIGMA_S_RAYLEIGH, SIGMA_S_MIE, density);
    let inScattered = lightColor * scatterCoeff * combinedPhase * density;

    let rayleighTint = vec3<f32>(0.3, 0.6, 1.0) * scattering * lightFalloff * density * SIGMA_S_RAYLEIGH;
    let aerogelAlbedo = vec3<f32>(0.95, 0.97, 1.0);
    var scatteredColor = inScattered * aerogelAlbedo + rayleighTint;

    // ═══ HDR Bloom Kernel (from alpha-hdr-bloom-chain) ═══
    var bloom = vec3<f32>(0.0);
    var totalWeight = 0.0;
    let bloomRadius = 0.015 + density * 0.03;
    let bloomSamples = 16;

    for (var i = 0; i < bloomSamples; i = i + 1) {
        let angle = f32(i) * 6.283185307 / f32(bloomSamples);
        let radius = bloomRadius * (1.0 + f32(i % 4) * 0.5);
        let offset = vec2<f32>(cos(angle), sin(angle)) * radius;
        let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
        let neighbor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
        let neighborMax = max(neighbor.r, max(neighbor.g, neighbor.b));
        let neighborExposure = max(0.0, neighborMax - 1.0);
        let weight = exp(-f32(i % 4) * 0.5);
        bloom += neighbor * neighborExposure * weight;
        totalWeight += neighborExposure * weight;
    }

    if (totalWeight > 0.001) {
        bloom /= totalWeight;
    }
    bloom *= bloomAmount * 2.0;

    // Add bloom to scattered light
    let hdrScattered = scatteredColor + bloom;

    // Volumetric compositing
    var finalColor = hdrScattered + baseColor * transmittance;
    finalColor = pow(finalColor, vec3<f32>(1.0 / 1.2));

    // Tone map
    let toneMapExp = mix(0.5, 2.0, glow);
    finalColor = toneMapACES(finalColor * toneMapExp);

    // Exposure value for alpha channel
    let maxChannel = max(finalColor.r, max(finalColor.g, finalColor.b));
    let exposure = max(0.0, maxChannel - 1.0);

    textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(hdrScattered, exposure));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let volumetricDepth = mix(depth, 0.5, alpha * 0.5);
    textureStore(writeDepthTexture, coord, vec4<f32>(volumetricDepth, optical_depth, 0.0, alpha));
}
