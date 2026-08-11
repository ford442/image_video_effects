// ═══════════════════════════════════════════════════════════════════
//  thermal-touch-blackbody
//  Category: advanced-hybrid
//  Features: stylized-blackbody-palette, mouse-heat-source, thermal-touch, temporal-streaks
//  Complexity: Medium
//  Chunks From: thermal-touch.wgsl, spec-blackbody-thermal.wgsl
//  Created: 2026-04-18
//  By: Agent CB-8 — Thermal & Atmospheric Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Mouse-driven thermal camera with a stylized blackbody-inspired
//  palette. The cursor acts as a localized heat source, and image
//  brightness maps to an artistic temperature range.
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
        b = clamp(0.54 * log(max(t - 1.0, 0.001)) - 1.0, 0.0, 1.0);
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
    let audio = plasmaBuffer[0].xyz;

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
    let mouseHeat = (1.0 - smoothstep(0.0, radius, dist)) * heatIntensity * (1.0 + audio.x * 0.25);

    var clickHeatFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.8) {
            let ringDist = abs(length((uv - ripple.xy) * vec2<f32>(aspect, 1.0)) - age * (0.18 + audio.y * 0.08));
            clickHeatFront += (1.0 - smoothstep(0.0, 0.025, ringDist)) * (1.0 - age / 2.8);
        }
    }

    // Sample texture and compute luminance
    let texColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let luminance = dot(texColor, vec3<f32>(0.299, 0.587, 0.114));

    // Map luminance to temperature (800K to 10000K range)
    let tempRangeLow = 800.0;
    let tempRangeHigh = 10000.0;
    var temperature = mix(tempRangeLow, tempRangeHigh, luminance);

    // Add mouse heat
    temperature += (mouseHeat + clickHeatFront * (0.35 + heatIntensity * 0.25)) * tempRangeHigh * 0.4;

    // Ambient temperature blending
    if (ambientTemp > 0.0) {
        let ambientTempK = mix(tempRangeLow, tempRangeHigh * 0.5, ambientTemp);
        temperature = mix(temperature, ambientTempK, 0.3);
    }

    // Stylized blackbody-inspired color plus bounded buoyant history streaks.
    var finalColor = blackbodyColor(temperature);

    let coord = vec2<i32>(gid.xy);
    let maxCoord = vec2<i32>(max(i32(res.x) - 1, 0), max(i32(res.y) - 1, 0));
    let buoyancy = 2 + i32(round(heatIntensity * 7.0 + audio.x * 3.0));
    let sway = i32(round(sin(time * 3.1 + uv.y * 21.0) * (1.0 + audio.z * 2.0)));
    let historyCoord = clamp(coord + vec2<i32>(sway, buoyancy), vec2<i32>(0), maxCoord);
    let history = textureLoad(dataTextureC, historyCoord, 0);
    let historyHeat = clamp(history.a, 0.0, 1.0);
    let streakPhase = fract(uv.y * 7.0 + time * (1.7 + audio.y));
    let streak = exp(-pow((streakPhase - 0.5) / 0.16, 2.0)) * historyHeat;
    finalColor = max(finalColor, clamp(history.rgb, vec3<f32>(0.0), vec3<f32>(4.0)) * (0.45 + streak * 0.35));

    // Tone map
    finalColor = toneMapACES(finalColor);

    // Original Blend is continuous over the full slider range.
    finalColor = mix(finalColor, texColor, clamp(colorMode, 0.0, 1.0));

    textureStore(writeTexture, gid.xy, vec4<f32>(finalColor, 1.0));
    textureStore(dataTextureA, gid.xy, vec4<f32>(finalColor, clamp(temperature / 15000.0, 0.0, 1.0)));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
