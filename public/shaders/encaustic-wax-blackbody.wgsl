// ═══════════════════════════════════════════════════════════════════
//  Encaustic Wax Blackbody
//  Category: advanced-hybrid
//  Features: encaustic-wax, blackbody-radiation, HDR, mouse-driven
//  Complexity: High
//  Chunks From: encaustic-wax.wgsl, spec-blackbody-thermal.wgsl
//  Created: 2026-04-18
//  By: Agent CB-22 — Artistic & Texture Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Combines physical encaustic wax simulation with blackbody thermal
//  radiation coloring. Wax thickness maps to temperature — thick
//  pooled wax glows like cooling magma, thin glaze shows underlying
//  image through amber-tinted translucency. Mouse melts wax creating
//  localized hotspots that radiate physically-correct color.
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

// ═══ CHUNK: hash (from encaustic-wax.wgsl) ═══
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

fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3(0.0), vec3(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    var mouse = u.zoom_config.yz;
    let time = u.config.x;

    // Parameters
    let waxThickness = u.zoom_params.x * 10.0;
    let textureStrength = u.zoom_params.y;
    let meltRadius = u.zoom_params.z;
    let thermalIntensity = mix(0.5, 3.0, u.zoom_params.w);

    // Calculate Melting from Mouse
    let dist = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));
    let meltFactor = smoothstep(meltRadius + 0.1, meltRadius, dist) * 1.0;

    let currentBlur = waxThickness + meltFactor * 10.0;
    let currentTexture = textureStrength * (1.0 - meltFactor * 0.5);

    // Generate Wax Texture
    let waxHeight = fbm(uv * 10.0);
    let waxDetail = fbm(uv * 25.0 + 100.0) * 0.5;
    let totalWaxHeight = waxHeight + waxDetail * 0.3;

    let distortUV = uv + vec2<f32>(waxHeight - 0.5) * 0.01 * currentTexture;

    // Blur Loop
    var colorSum = vec3<f32>(0.0);
    var totalWeight = 0.0;
    let texel = 1.0 / resolution;

    for (var x = -2.0; x <= 2.0; x += 1.0) {
        for (var y = -2.0; y <= 2.0; y += 1.0) {
            let offset = vec2<f32>(x, y) * currentBlur * texel;
            let weight = 1.0 / (1.0 + length(vec2<f32>(x, y)));
            colorSum += textureSampleLevel(readTexture, u_sampler, distortUV + offset, 0.0).rgb * weight;
            totalWeight += weight;
        }
    }

    var finalColor = colorSum / totalWeight;

    // Specular highlights for wax surface
    let h1 = fbm((uv + vec2<f32>(texel.x, 0.0)) * 10.0);
    let h2 = fbm((uv + vec2<f32>(0.0, texel.y)) * 10.0);
    let normal = normalize(vec3<f32>(h1 - waxHeight, h2 - waxHeight, 0.1));
    let lightDir = normalize(vec3<f32>(mouse.x - uv.x, mouse.y - uv.y, 0.5));
    let spec = pow(max(dot(normal, lightDir), 0.0), 10.0) * currentTexture * 0.5;
    finalColor += spec;

    // Wax thickness calculation
    let base_thickness = 0.3 + totalWaxHeight * 0.7;
    let melt_thickness = base_thickness + meltFactor * 0.4;
    var wax_alpha = mix(0.35, 0.92, melt_thickness * (0.5 + textureStrength * 0.5));
    let surface_relief = smoothstep(0.3, 0.7, waxHeight);
    wax_alpha *= mix(0.9, 1.0, surface_relief);
    let valley_depth = 1.0 - waxDetail;
    let translucency = mix(0.6, 1.0, valley_depth);
    wax_alpha *= translucency;
    let edge_mask = smoothstep(0.0, 0.15, melt_thickness);
    wax_alpha *= edge_mask;

    // ═══ BLACKBODY THERMAL COLORING ═══
    // Map wax thickness to temperature: thick = hotter
    let luma = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
    let tempRangeLow = 800.0;
    let tempRangeHigh = 6000.0;
    var temperature = mix(tempRangeLow, tempRangeHigh, melt_thickness * 0.7 + luma * 0.3);

    // Mouse creates local hotspots
    let isMouseDown = u.zoom_config.w > 0.5;
    if (isMouseDown) {
        let mouseDist = length(uv - mouse);
        let mouseHeat = exp(-mouseDist * mouseDist * 400.0);
        temperature += mouseHeat * tempRangeHigh * 0.5;
    }

    var thermalColor = blackbodyColor(temperature) * thermalIntensity;

    // Ember glow around thick wax regions
    let glowRadius = 0.03;
    var glowAccum = vec3<f32>(0.0);
    let glowSamples = 8;
    for (var i: i32 = 0; i < glowSamples; i = i + 1) {
        let angle = f32(i) * 0.785398 + time * 0.3;
        let offset = vec2<f32>(cos(angle), sin(angle)) * glowRadius;
        let s = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb;
        let sLuma = dot(s, vec3<f32>(0.299, 0.587, 0.114));
        let sTemp = mix(tempRangeLow, tempRangeHigh, sLuma);
        glowAccum += blackbodyColor(sTemp) * thermalIntensity;
    }
    glowAccum /= f32(glowSamples);

    // Blend thermal glow with wax color based on thickness
    let thermalBlend = smoothstep(0.4, 0.8, melt_thickness) * 0.6;
    finalColor = mix(finalColor, toneMapACES(thermalColor), thermalBlend);
    finalColor = mix(finalColor, toneMapACES(glowAccum), thermalBlend * 0.3);

    // Warm amber tint for wax medium
    let wax_tint = vec3<f32>(1.02, 0.98, 0.92);
    finalColor *= mix(vec3<f32>(1.0), wax_tint, melt_thickness * 0.5);
    let depth_darken = mix(1.0, 0.85, melt_thickness * textureStrength);
    finalColor *= depth_darken;

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, wax_alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(melt_thickness, 0.0, 0.0, wax_alpha));
}
