// ═══════════════════════════════════════════════════════════════════
//  frosted-glass-lens-iridescence
//  Category: advanced-hybrid
//  Features: frosted-glass, thin-film-interference, depth-aware, mouse-driven
//  Complexity: Very High
//  Chunks From: frosted-glass-lens.wgsl, spec-iridescence-engine.wgsl
//  Created: 2026-04-18
//  By: Agent CB-21 — Distortion & Material Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Physical frosted glass transmission with thin-film iridescence
//  on the glass surface. Film thickness varies with frost density
//  and viewing angle, producing soap-bubble color shifts at lens
//  edges. Beer-Lambert absorption blends with Fresnel interference.
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
    let t = clamp((lambda - 380.0) / (700.0 - 380.0), 0.0, 1.0);
    let r = smoothstep(0.5, 0.85, t) + smoothstep(0.0, 0.2, t) * 0.2;
    let g = 1.0 - abs(t - 0.45) * 2.5;
    let b = 1.0 - smoothstep(0.0, 0.45, t);
    return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

fn thinFilmColor(thicknessNm: f32, cosTheta: f32, filmIOR: f32) -> vec3<f32> {
    let sinTheta_t = sqrt(max(1.0 - cosTheta * cosTheta, 0.0)) / filmIOR;
    let cosTheta_t = sqrt(max(1.0 - sinTheta_t * sinTheta_t, 0.0));
    let opd = 2.0 * filmIOR * thicknessNm * cosTheta_t;
    var color = vec3<f32>(0.0);
    var sampleCount = 0.0;
    for (var lambda = 380.0; lambda <= 700.0; lambda = lambda + 40.0) {
        let phase = opd / lambda;
        let interference = cos(phase * 6.28318530718) * 0.5 + 0.5;
        color += wavelengthToRGB(lambda) * interference;
        sampleCount = sampleCount + 1.0;
    }
    return color / max(sampleCount, 1.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let frost_amt = u.zoom_params.x;
    let lens_radius = u.zoom_params.y * 0.4 + 0.05;
    let edge_softness = u.zoom_params.z * 0.2 + 0.01;
    let filmIOR = mix(1.2, 2.4, u.zoom_params.w);

    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dist_vec);

    // Lens mask
    let lens_mask = smoothstep(lens_radius, lens_radius + edge_softness, dist);
    let glassDensity = frost_amt * 1.5 + 0.5;

    // Frost noise
    let noise_val = hash12(uv * 100.0 + time * 0.1);
    let frost_offset = (noise_val - 0.5) * 0.05 * frost_amt * lens_mask;

    // Rough normal and Fresnel
    let roughNormal = normalize(vec3<f32>(frost_offset * 20.0, 0.0, 1.0 - frost_amt * 0.5));
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    let cos_theta = max(dot(viewDir, roughNormal), 0.0);
    let R0 = 0.04;
    let fresnel = R0 + (1.0 - R0) * pow(1.0 - cos_theta, 5.0);

    // Thin-film iridescence on glass surface
    let toCenter = uv - vec2<f32>(0.5);
    let viewDist = length(toCenter);
    let cosThetaView = sqrt(max(1.0 - viewDist * viewDist * 0.5, 0.01));
    let filmThicknessBase = 200.0 + frost_amt * 400.0;
    let noiseVal = hash12(uv * 12.0 + time * 0.1) * 0.5
                 + hash12(uv * 25.0 - time * 0.15) * 0.25;
    let thickness = filmThicknessBase * (0.7 + noiseVal * lens_mask);
    let iridescent = thinFilmColor(thickness, cosThetaView, filmIOR);

    // Beer-Lambert absorption
    let thicknessGlass = 0.03 + frost_amt * 0.1 * (1.0 + noise_val);
    let glassColor = vec3<f32>(0.92, 0.95, 0.98);
    let absorption = exp(-(1.0 - glassColor) * thicknessGlass * glassDensity);
    let baseTransmission = (1.0 - fresnel) * (absorption.r + absorption.g + absorption.b) / 3.0;
    let transmission = mix(baseTransmission, baseTransmission * 0.7, frost_amt * lens_mask);

    // Sample with frost offset
    var color: vec4<f32>;
    if (lens_mask > 0.001) {
        let sample_uv = uv + vec2<f32>(frost_offset);
        color = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0);
        let frostTint = mix(vec3<f32>(1.0), glassColor, 0.7);
        color = vec4<f32>(mix(color.rgb, frostTint, 0.2 * frost_amt * lens_mask), transmission);
    } else {
        color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
        color = vec4<f32>(color.rgb * glassColor, baseTransmission);
    }

    // Chromatic aberration at lens edge
    let ab_mask = smoothstep(lens_radius, lens_radius + edge_softness * 0.5, dist) *
                  (1.0 - smoothstep(lens_radius + edge_softness * 0.5, lens_radius + edge_softness, dist));
    let aberration = frost_amt * 0.02 * ab_mask;
    let uv_r = uv + vec2<f32>(frost_offset) + vec2<f32>(aberration, 0.0);
    let uv_g = uv + vec2<f32>(frost_offset);
    let uv_b = uv + vec2<f32>(frost_offset) - vec2<f32>(aberration, 0.0);
    let col_r = textureSampleLevel(readTexture, u_sampler, uv_r, 0.0).r;
    let col_g = textureSampleLevel(readTexture, u_sampler, uv_g, 0.0).g;
    let col_b = textureSampleLevel(readTexture, u_sampler, uv_b, 0.0).b;
    color = vec4<f32>(col_r, col_g, col_b, transmission);

    // Apply iridescence on top, stronger at edges
    let edgeIridescence = fresnel * lens_mask * (0.5 + frost_amt * 0.5);
    color = vec4<f32>(mix(color.rgb, iridescent, edgeIridescence * 0.6), color.a);

    // Frost tint
    let frostTint = vec3<f32>(0.9, 0.95, 1.0);
    color = vec4<f32>(mix(color.rgb, color.rgb * frostTint, 0.3 * frost_amt * lens_mask), color.a);

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(iridescent, thickness / 1000.0));
}
