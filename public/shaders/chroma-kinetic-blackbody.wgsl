// ═══════════════════════════════════════════════════════════════════
//  chroma-kinetic-blackbody
//  Category: advanced-hybrid
//  Features: chroma-kinetic, blackbody-thermal, physical-color
//  Complexity: High
//  Chunks From: chroma-kinetic, spec-blackbody-thermal
//  Created: 2026-04-18
//  By: Agent CB-12 — Chroma & Spectral Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Mouse-driven kinetic RGB split combined with physically-correct
//  blackbody thermal coloring. Luminance drives temperature; velocity
//  drives chromatic separation. Hotspots bloom with Stefan-Boltzmann
//  radiance and chromatic aberration.
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

fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3(0.0), vec3(1.0));
}

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
    let aspect = res.x / res.y;
    let time = u.config.x;

    let strength = u.zoom_params.x * 0.1;
    let radius = u.zoom_params.y;
    let luma_inf = u.zoom_params.z;
    let rotation = u.zoom_params.w * 6.28318;

    let tempRangeLow = mix(800.0, 2500.0, u.zoom_params.x);
    let tempRangeHigh = mix(4000.0, 15000.0, u.zoom_params.y);
    let thermalIntensity = mix(0.5, 3.0, u.zoom_params.z);
    let glowAmount = mix(0.0, 0.8, u.zoom_params.w);

    var mousePos = u.zoom_config.yz;
    let diff = uv - mousePos;
    let diffAspect = diff * vec2<f32>(aspect, 1.0);
    let dist = length(diffAspect);

    var dir = vec2<f32>(0.0);
    if (dist > 0.001) { dir = normalize(diffAspect); }

    let c = cos(rotation);
    let s = sin(rotation);
    let rotDir = vec2<f32>(dir.x * c - dir.y * s, dir.x * s + dir.y * c);
    let uvOffsetDir = vec2<f32>(rotDir.x / aspect, rotDir.y);

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(baseColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let falloff = smoothstep(radius, 0.0, dist);
    let modFactor = max(0.0, 1.0 + (luma - 0.5) * luma_inf * 2.0);
    let finalOffset = uvOffsetDir * strength * falloff * modFactor;

    let uvR = uv - finalOffset;
    let uvB = uv + finalOffset;

    let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let g = baseColor.g;
    let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;
    var color = vec3<f32>(r, g, b);

    // Blackbody thermal coloring
    var temperature = mix(tempRangeLow, tempRangeHigh, luma);
    let mouseDown = u.zoom_config.w > 0.5;
    if (mouseDown) {
        let mouseDist = length(uv - mousePos);
        let mouseHeat = exp(-mouseDist * mouseDist * 400.0);
        temperature += mouseHeat * tempRangeHigh * 0.5;
    }

    var thermalColor = blackbodyColor(temperature) * thermalIntensity;

    if (glowAmount > 0.01) {
        let glowRadius = 0.03;
        var glowAccum = vec3<f32>(0.0);
        let glowSamples = 16;
        for (var i: i32 = 0; i < glowSamples; i = i + 1) {
            let angle = f32(i) * 0.392699 + time * 0.3;
            let offset = vec2<f32>(cos(angle), sin(angle)) * glowRadius;
            let s = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb;
            let sLuma = dot(s, vec3<f32>(0.299, 0.587, 0.114));
            let sTemp = mix(tempRangeLow, tempRangeHigh, sLuma);
            glowAccum += blackbodyColor(sTemp) * thermalIntensity;
        }
        glowAccum /= f32(glowSamples);
        thermalColor = mix(thermalColor, glowAccum, glowAmount * 0.4);
    }

    let displayColor = toneMapACES(thermalColor);

    // Blend kinetic RGB split with thermal coloring
    let blend = mix(color, displayColor, 0.6);

    textureStore(writeTexture, gid.xy, vec4<f32>(blend, temperature / 15000.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
