// ═══════════════════════════════════════════════════════════════════
//  Heat Haze Volumetric
//  Category: advanced-hybrid
//  Features: heat-diffusion, volumetric-fog, refraction, depth-aware,
//            mouse-driven, temporal
//  Complexity: Very High
//  Chunks From: heat-haze, alpha-depth-fog-volumetric
//  Created: 2026-04-18
//  By: Agent CB-26
// ═══════════════════════════════════════════════════════════════════
//  Thermal heat fields interact with volumetric fog. Hot regions
//  evaporate fog and create refractive distortion; cold regions
//  accumulate dense mist. Depth-aware Beer-Lambert with thermal
//  modulation creates living atmospheric pockets.
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

// ═══ CHUNK: hash12 (from alpha-depth-fog-volumetric) ═══
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
        value += amplitude * valueNoise(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    return value;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let texel = 1.0 / res;
    let time = u.config.x;

    // Parameters
    let heatGain = u.zoom_params.x;
    let decayRate = u.zoom_params.y;
    let fogDensity = mix(0.2, 3.0, u.zoom_params.z);
    let refraction = u.zoom_params.w;
    let turbulence = 0.5;

    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let aspect = res.x / res.y;

    // === READ PREVIOUS HEAT ===
    let c = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let l = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).r;
    let r_heat = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).r;
    let t_heat = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).r;
    let b_heat = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).r;

    let avg = (l + r_heat + t_heat + b_heat) * 0.25;
    var diffusedHeat = mix(c, avg, 0.3);

    // Mouse heat injection
    let dist = distance(uv * vec2<f32>(aspect, 1.0), mousePos * vec2<f32>(aspect, 1.0));
    var mouseHeat = 0.0;
    if (mouseDown > 0.5 && dist < 0.05) {
        mouseHeat = heatGain * (1.0 - dist / 0.05);
    }

    let newHeat = (diffusedHeat + mouseHeat) * decayRate;
    let finalHeat = clamp(newHeat, 0.0, 1.0);

    // Write heat to depth for next frame
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(finalHeat, 0.0, 0.0, 0.0));

    // === REFRACTION FROM HEAT GRADIENT ===
    let heatGradX = r_heat - l;
    let heatGradY = b_heat - t_heat;
    let warp = vec2<f32>(heatGradX, heatGradY) * refraction;
    let finalUV = uv - warp;

    // === VOLUMETRIC FOG MODULATED BY HEAT ===
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let distFactor = (1.0 - depth);
    let heightFactor = 1.0 - uv.y * 0.5;

    let noiseUV = uv * 3.0 + vec2<f32>(time * 0.02, time * 0.015);
    let fogNoise = fbm2(noiseUV, 4) * turbulence + (1.0 - turbulence);

    // Heat reduces fog (evaporation)
    let heatFogMod = 1.0 - finalHeat * 0.9;
    let opticalDepth = fogDensity * distFactor * heightFactor * fogNoise * heatFogMod * 3.0;
    let transmittance = exp(-opticalDepth);

    // Fog colors: warm near, cool far, hot = clear
    let nearFog = vec3<f32>(0.85, 0.75, 0.55);
    let farFog = vec3<f32>(0.25, 0.35, 0.6);
    let hotFog = vec3<f32>(0.9, 0.4, 0.2);
    let fogColor = mix(mix(nearFog, farFog, distFactor), hotFog, finalHeat * 0.3);

    // Mouse clears fog
    let mouseDist = length(uv - mousePos);
    let mouseClear = smoothstep(0.2, 0.0, mouseDist) * mouseDown;
    let modifiedTransmittance = mix(transmittance, 1.0, mouseClear);

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
    let finalTransmittance = mix(modifiedTransmittance, modifiedTransmittance * 0.5, rippleDisturbance);

    // === SCENE COMPOSITE ===
    let sceneColor = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).rgb;
    let foggedColor = sceneColor * finalTransmittance + fogColor * (1.0 - finalTransmittance);

    // Thermal tint overlay
    let thermalTint = vec3<f32>(1.0, 0.3, 0.1) * finalHeat * 0.5;
    let outColor = foggedColor + thermalTint;

    textureStore(dataTextureA, coord, vec4<f32>(outColor, finalTransmittance));
    textureStore(writeTexture, coord, vec4<f32>(outColor, finalTransmittance));
}
