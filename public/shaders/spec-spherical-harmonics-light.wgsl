// ═══════════════════════════════════════════════════════════════════
//  spec-spherical-harmonics-light
//  Category: advanced-hybrid
//  Features: spherical-harmonics, SH-lighting, depth-aware
//  Complexity: High
//  Chunks From: chunk-library (hash12)
//  Created: 2026-04-18
//  By: Agent 3C — Spectral Computation Pioneer
// ═══════════════════════════════════════════════════════════════════
//  Spherical Harmonics Lighting
//  Uses spherical harmonic coefficients derived from the input image
//  to represent the lighting environment. Applies SH lighting to a
//  normal-mapped surface derived from depth.
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
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Evaluate spherical harmonics bands 0-2
fn evaluateSH(normal: vec3<f32>, coeffs: array<vec3<f32>, 9>) -> vec3<f32> {
    // Band 0
    var result = coeffs[0] * 0.282095;
    // Band 1
    result += coeffs[1] * 0.488603 * normal.y;
    result += coeffs[2] * 0.488603 * normal.z;
    result += coeffs[3] * 0.488603 * normal.x;
    // Band 2
    result += coeffs[4] * 1.092548 * normal.x * normal.y;
    result += coeffs[5] * 1.092548 * normal.y * normal.z;
    result += coeffs[6] * 0.315392 * (3.0 * normal.z * normal.z - 1.0);
    result += coeffs[7] * 1.092548 * normal.x * normal.z;
    result += coeffs[8] * 0.546274 * (normal.x * normal.x - normal.y * normal.y);
    return result;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let texel = 1.0 / res;
    let time = u.config.x;

    let shStrength = mix(0.2, 2.0, u.zoom_params.x);
    let normalScale = mix(0.5, 3.0, u.zoom_params.y);
    let specPower = mix(4.0, 64.0, u.zoom_params.z);
    let ambientBoost = mix(0.1, 0.8, u.zoom_params.w);

    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    // Sample base color and depth
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Compute normal from depth using Sobel filter
    let dx = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).r - depth;
    let dy = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).r - depth;
    var normal = normalize(vec3<f32>(-dx * normalScale, -dy * normalScale, 1.0));

    // Mouse perturbs normal
    if (isMouseDown) {
        let toMouse = mousePos - uv;
        let mouseInfluence = exp(-dot(toMouse, toMouse) * 500.0);
        let mouseNormal = normalize(vec3<f32>(toMouse * 2.0, 1.0));
        normal = mix(normal, mouseNormal, mouseInfluence * 0.5);
    }

    // Derive SH coefficients from image content (simplified projection)
    // We approximate by sampling key directions and using the image color
    var coeffs = array<vec3<f32>, 9>();

    // L0 (ambient)
    coeffs[0] = baseColor * 0.5;

    // L1 (dominant light direction from image brightness gradient)
    let luma = dot(baseColor, vec3<f32>(0.299, 0.587, 0.114));
    let gradX = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel.x * 4.0, 0.0), 0.0).rgb - baseColor;
    let gradY = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texel.y * 4.0), 0.0).rgb - baseColor;

    coeffs[1] = gradY * 0.3; // Y
    coeffs[2] = vec3<f32>(luma) * 0.3; // Z (approximate sky/ground)
    coeffs[3] = gradX * 0.3; // X

    // L2 (color variation patterns)
    let chroma = baseColor - vec3<f32>(luma);
    coeffs[4] = chroma * 0.15; // XY
    coeffs[5] = gradY * 0.1;   // YZ
    coeffs[6] = vec3<f32>(depth * 0.2); // ZZ
    coeffs[7] = gradX * 0.1;   // XZ
    coeffs[8] = chroma * 0.1;  // XX-YY

    // Animated time-varying coefficient modulation
    for (var i = 0; i < 9; i = i + 1) {
        let phase = time * 0.2 + f32(i) * 0.7;
        coeffs[i] *= (1.0 + sin(phase) * 0.1);
    }

    // Evaluate SH lighting
    let shLight = evaluateSH(normal, coeffs) * shStrength;

    // Specular highlight
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    let lightDir = normalize(vec3<f32>(0.3, 0.5, 0.8));
    let halfDir = normalize(lightDir + viewDir);
    let spec = pow(max(dot(normal, halfDir), 0.0), specPower);

    // Combine
    let ambient = baseColor * ambientBoost;
    let litColor = ambient + baseColor * max(shLight, vec3<f32>(0.0)) + vec3<f32>(spec * 0.3);

    // Tone map
    let display = litColor / (1.0 + litColor * 0.3);

    textureStore(writeTexture, gid.xy, vec4<f32>(display, depth));
    textureStore(dataTextureA, gid.xy, vec4<f32>(shLight, spec));
}
