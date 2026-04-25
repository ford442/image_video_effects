// ═══════════════════════════════════════════════════════════════════
//  thermal-touch-blackbody
//  Category: advanced-hybrid
//  Features: blackbody-radiation, mouse-heat-source, thermal-touch
//  Complexity: Medium
//  Chunks From: thermal-touch.wgsl, spec-blackbody-thermal.wgsl
//  Created: 2026-04-18
//  By: Agent CB-8 — Thermal & Atmospheric Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Mouse-driven thermal camera with physically-correct blackbody
//  coloring. The cursor acts as a localized heat source, and image
//  brightness maps to temperature via Planck's law.
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

// ═══ CHUNK: toneMapACES (from spec-blackbody-thermal.wgsl) ═══
fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3(0.0), vec3(1.0));
}

// ═══ CHUNK: blackbodyColor (from spec-blackbody-thermal.wgsl) ═══
fn blackbodyColor(temperatureK: f32) -> vec3<f32> {
    let t = clamp(temperatureK / 1000.0, 0.5, 30.0);
    var r: f32;
    var g: f32;
    var b: f32;
    if (t <= 6.5) {
        r = 1.0;
        g = clamp(0.39 * log(t) - 0.63, 0.0, 1.0);
        b = clamp(0.54 * log(t - 1.0) - 1.0, 0.0, 1.0);
    } else {
        r = clamp(1.29 * pow(t - 0.6, -0.133), 0.0, 1.0);
        g = clamp(1.29 * pow(t - 0.6, -0.076), 0.0, 1.0);
        b = 1.0;
    }
    let radiance = pow(t / 6.5, 4.0);
    return vec3<f32>(r, g, b) * radiance;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let time = u.config.x;

    // Parameters
    let heatIntensity = mix(0.1, 2.0, u.zoom_params.x);
    let radius = mix(0.05, 0.5, u.zoom_params.y);
    let ambientTemp = u.zoom_params.z;
    let colorMode = u.zoom_params.w;

    let mousePos = u.zoom_config.yz;

    // Aspect-corrected distance to mouse
    let aspect = res.x / res.y;
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Mouse heat influence
    let mouseHeat = (1.0 - smoothstep(0.0, radius, dist)) * heatIntensity;

    // Sample texture and compute luminance
    let texColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let luminance = dot(texColor, vec3<f32>(0.299, 0.587, 0.114));

    // Map luminance to temperature (800K to 10000K range)
    let tempRangeLow = 800.0;
    let tempRangeHigh = 10000.0;
    var temperature = mix(tempRangeLow, tempRangeHigh, luminance);

    // Add mouse heat
    temperature += mouseHeat * tempRangeHigh * 0.4;

    // Ambient temperature blending
    if (ambientTemp > 0.0) {
        let ambientTempK = mix(tempRangeLow, tempRangeHigh * 0.5, ambientTemp);
        temperature = mix(temperature, ambientTempK, 0.3);
    }

    // Blackbody color
    var finalColor = blackbodyColor(temperature);

    // Tone map
    finalColor = toneMapACES(finalColor);

    // Optional: mix original texture back in
    if (colorMode > 0.5) {
        finalColor = mix(finalColor, texColor, 0.4);
    }

    textureStore(writeTexture, gid.xy, vec4<f32>(finalColor, 1.0));
    textureStore(dataTextureA, gid.xy, vec4<f32>(finalColor, temperature / 15000.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
