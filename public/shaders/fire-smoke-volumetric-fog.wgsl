// ═══════════════════════════════════════════════════════════════════
//  fire-smoke-volumetric-fog
//  Category: advanced-hybrid
//  Features: fire, smoke, volumetric-fog, blackbody, depth-aware, atmospheric
//  Complexity: Very High
//  Chunks From: fire_smoke_volumetric.wgsl, alpha-depth-fog-volumetric.wgsl
//  Created: 2026-04-18
//  By: Agent CB-19 — Lighting & Energy Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Volumetric fire and smoke merged with physically-motivated depth fog.
//  Fire illuminates fog particles via blackbody radiation while smoke
//  density modulates fog optical depth through Beer-Lambert law.
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

// ═══ CHUNK: physicalTransmittance (from fire_smoke_volumetric.wgsl) ═══
fn physicalTransmittance(baseColor: vec3<f32>, opticalDepth: f32, absorptionCoeff: vec3<f32>) -> vec3<f32> {
    let transmittance = exp(-absorptionCoeff * opticalDepth);
    return baseColor * transmittance;
}

fn volumetricAlpha(density: f32, thickness: f32) -> f32 {
    return 1.0 - exp(-density * thickness);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x;

    // Parameters
    let fireIntensity = u.zoom_params.x * 2.0;
    let smokeDensity = u.zoom_params.y;
    let fogDensity = mix(0.2, 3.0, u.zoom_params.x);
    let fogHeight = u.zoom_params.y;
    let turbulence = u.zoom_params.z;
    let colorTemp = u.zoom_params.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // ═══ Fire / Smoke (from fire_smoke_volumetric) ═══
    let noiseUV = vec3<f32>(uv * 5.0, time * 0.5);
    let n = hash12(uv * 10.0 + time * 0.3);
    let fireShape = smoothstep(0.3, 0.7, 1.0 - uv.y + n * turbulence);
    let density = fireShape * smokeDensity;

    let fireColor = mix(
        vec3<f32>(1.0, 0.8, 0.1),
        vec3<f32>(0.8, 0.2, 0.05),
        uv.y * fireIntensity
    ) * fireShape;
    let smokeColor = vec3<f32>(0.3, 0.3, 0.35) * density;
    let fireSmokeColor = mix(smokeColor, fireColor, fireShape);

    let fireOpticalDepth = density * (1.0 + turbulence);
    let fireAbsorption = vec3<f32>(0.5, 0.6, 0.7);
    let transmittedFire = physicalTransmittance(fireSmokeColor, fireOpticalDepth, fireAbsorption);
    let fireAlpha = volumetricAlpha(density, 1.0);

    // ═══ Depth Fog (from alpha-depth-fog-volumetric) ═══
    let fogNoiseUV = uv * 3.0 + vec2<f32>(time * 0.02, time * 0.015);
    let fogNoise = fbm2(fogNoiseUV, 4) * turbulence + (1.0 - turbulence);

    let distFactor = (1.0 - depth);
    let heightFactor = 1.0 - uv.y * fogHeight;
    let fogOpticalDepth = fogDensity * distFactor * heightFactor * fogNoise * 3.0;
    let fogTransmittance = exp(-fogOpticalDepth);

    // Fire-warmed fog color
    let nearFog = mix(vec3<f32>(0.85, 0.75, 0.55), vec3<f32>(1.0, 0.6, 0.2), fireShape * fireIntensity);
    let farFog = mix(vec3<f32>(0.25, 0.35, 0.6), vec3<f32>(0.4, 0.2, 0.1), colorTemp);
    let fogColor = mix(nearFog, farFog, distFactor);

    // Mouse clears fog
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseClear = smoothstep(0.2, 0.0, mouseDist) * mouseDown;
    let modifiedFogTrans = mix(fogTransmittance, 1.0, mouseClear);

    // Ripple fog swirl
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
    let finalFogTrans = mix(modifiedFogTrans, modifiedFogTrans * 0.5, rippleDisturbance);

    // Scene composite with fire and fog
    let sceneColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let fireLayer = mix(sceneColor, transmittedFire, fireAlpha * 0.7);
    let foggedColor = fireLayer * finalFogTrans + fogColor * (1.0 - finalFogTrans);

    let finalAlpha = max(fireAlpha, 1.0 - finalFogTrans);

    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(foggedColor, finalAlpha));
    textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(foggedColor, finalAlpha));

    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
