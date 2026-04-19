// ═══════════════════════════════════════════════════════════════════
//  atmos-fog-volumetric
//  Category: advanced-hybrid
//  Features: volumetric-fog, depth-aware, mouse-clear, ripple-swirl
//  Complexity: High
//  Chunks From: atmos_volumetric_fog.wgsl, alpha-depth-fog-volumetric.wgsl
//  Created: 2026-04-18
//  By: Agent CB-8 — Thermal & Atmospheric Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Enhanced volumetric fog combining physical transmittance with
//  interactive depth-layered alpha. Mouse clears fog locally, ripples
//  create swirling disturbances, and height-based density mixes with
//  Beer's Law for atmospheric realism.
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

// ═══ CHUNK: hash12 (from alpha-depth-fog-volumetric.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let a = hash12(i + vec2<f32>(0.0, 0.0));
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value = value + amplitude * valueNoise(p * frequency);
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.0;
    }
    return value;
}

// ═══ CHUNK: physical transmittance (from atmos_volumetric_fog.wgsl) ═══
fn physicalTransmittance(baseColor: vec3<f32>, opticalDepth: f32, absorptionCoeff: vec3<f32>) -> vec3<f32> {
    let transmittance = exp(-absorptionCoeff * opticalDepth);
    return baseColor * transmittance;
}

fn volumetricAlpha(density: f32, thickness: f32) -> f32 {
    return 1.0 - exp(-density * thickness);
}

fn depthLayeredAlpha(uv: vec2<f32>, depthWeight: f32) -> f32 {
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthAlpha = mix(0.2, 1.0, depth);
    return mix(1.0, depthAlpha, depthWeight);
}

fn calculateFogAlpha(uv: vec2<f32>, opticalDepth: f32, density: f32, params: vec4<f32>) -> f32 {
    let volAlpha = volumetricAlpha(density, opticalDepth);
    let depthAlpha = depthLayeredAlpha(uv, params.z);
    return clamp(volAlpha * depthAlpha, 0.0, 1.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let time = u.config.x;

    // Parameters
    let fogDensity = mix(0.2, 3.0, u.zoom_params.x);
    let fogHeight = u.zoom_params.y;
    let depthWeight = u.zoom_params.z;
    let turbulence = u.zoom_params.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // ═══ Volumetric noise ═══
    let noiseUV = uv * 3.0 + vec2<f32>(time * 0.02, time * 0.015);
    let fogNoise = fbm2(noiseUV, 4) * turbulence + (1.0 - turbulence);

    // ═══ Height-based density (from atmos_volumetric_fog) ═══
    let heightFog = exp(-uv.y / max(fogHeight, 0.01));
    let density = fogDensity * heightFog * (0.5 + fogNoise * 0.5);

    // ═══ Optical depth with Beer's Law ═══
    let distFactor = (1.0 - depth);
    let heightFactor = 1.0 - uv.y * fogHeight;
    let opticalDepth = density * distFactor * heightFactor * fogNoise * 3.0;
    let transmittance = exp(-opticalDepth);

    // ═══ Fog color: warm near, cool far ═══
    let nearFog = vec3<f32>(0.85, 0.75, 0.55);
    let farFog = vec3<f32>(0.25, 0.35, 0.6);
    let fogColor = mix(nearFog, farFog, distFactor);

    // ═══ Atmospheric scattering color shift ═══
    let atmosColor = vec3<f32>(
        0.7 + depthWeight * 0.2,
        0.75 + depthWeight * 0.1,
        0.85
    );
    let combinedFogColor = mix(atmosColor, fogColor, 0.5);

    // ═══ Mouse clears fog (from alpha-depth-fog-volumetric) ═══
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseClear = smoothstep(0.2, 0.0, mouseDist) * mouseDown;
    let modifiedTransmittance = mix(transmittance, 1.0, mouseClear);

    // ═══ Ripple fog swirl ═══
    let rippleCount = min(u32(u.config.y), 50u);
    var rippleDisturbance = 0.0;
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age < 2.0 && rDist < 0.2) {
            rippleDisturbance += smoothstep(0.2, 0.0, rDist) * max(0.0, 1.0 - age * 0.5) * 0.3;
        }
    }
    let finalTransmittance = mix(modifiedTransmittance, modifiedTransmittance * 0.5, rippleDisturbance);

    // ═══ Scene composite ═══
    let sceneColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let transmitted = physicalTransmittance(sceneColor, opticalDepth, vec3<f32>(0.3, 0.4, 0.5));
    let foggedColor = transmitted * finalTransmittance + combinedFogColor * (1.0 - finalTransmittance);

    // Final alpha
    let alpha = calculateFogAlpha(uv, opticalDepth, density, u.zoom_params);

    textureStore(dataTextureA, coord, vec4<f32>(foggedColor, finalTransmittance));
    textureStore(writeTexture, coord, vec4<f32>(foggedColor, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
