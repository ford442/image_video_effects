// ═══════════════════════════════════════════════════════════════════
//  Glass Wall Prismatic
//  Category: advanced-hybrid
//  Features: mouse-driven, spectral-rendering, physical-dispersion, refraction
//  Complexity: Very High
//  Chunks From: glass-wall, spec-prismatic-dispersion
//  Created: 2026-04-18
//  By: Agent CB-24 — Glass & Reflection Enhancer
// ═══════════════════════════════════════════════════════════════════
//  A grid of glass tiles where each tile acts as a prismatic lens.
//  Mouse interaction tilts tiles, and 4-band spectral dispersion
//  refracts each wavelength through the tile at a different angle
//  via Cauchy's equation. Bevel edges and mortar lines preserved.
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

fn cauchyIOR(wavelengthNm: f32, A: f32, B: f32) -> f32 {
    let lambdaUm = wavelengthNm * 0.001;
    return A + B / (lambdaUm * lambdaUm);
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
    let t = clamp((lambda - 440.0) / (680.0 - 440.0), 0.0, 1.0);
    let r = smoothstep(0.5, 0.8, t) + smoothstep(0.0, 0.15, t) * 0.3;
    let g = 1.0 - abs(t - 0.4) * 3.0;
    let b = 1.0 - smoothstep(0.0, 0.4, t);
    return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    let uv = vec2<f32>(gid.xy) / dims;
    let aspect = dims.x / dims.y;
    var mouse = u.zoom_config.yz;
    let time = u.config.x;

    // Parameters
    let gridSize = mix(5.0, 30.0, u.zoom_params.x);
    let glassCurvature = mix(0.1, 1.2, u.zoom_params.y);
    let cauchyB = mix(0.01, 0.08, u.zoom_params.z);
    let glassThickness = mix(0.3, 1.5, u.zoom_params.w);

    let scale = vec2<f32>(gridSize * aspect, gridSize);
    let cellID = floor(uv * scale);
    let cellUV = fract(uv * scale);
    let cellCenter = (cellID + 0.5) / scale;

    // Interaction Vector
    let aspectVec = vec2<f32>(aspect, 1.0);
    let vecToMouse = (mouse - cellCenter) * aspectVec;
    let dist = length(vecToMouse);

    // Interaction Strength
    let radius = 0.5;
    let influence = smoothstep(radius, 0.0, dist);

    // Calculate tilt based on mouse interaction
    var tilt = vec2<f32>(0.0);
    if (dist > 0.001) {
        tilt = normalize(vecToMouse) * influence;
    }

    // Bevel edges for 3D look
    let bevelX = smoothstep(0.0, 0.1, cellUV.x) * (1.0 - smoothstep(0.9, 1.0, cellUV.x));
    let bevelY = smoothstep(0.0, 0.1, cellUV.y) * (1.0 - smoothstep(0.9, 1.0, cellUV.y));
    let bevel = bevelX * bevelY;

    // Refraction displacement
    let refractionStrength = 0.05;
    let offset = tilt * refractionStrength;
    let bevelDistort = (vec2<f32>(0.5) - cellUV) * 0.02 * (1.0 - bevel);
    let finalUV = uv + offset + bevelDistort;

    // Normal for fresnel
    let normal = normalize(vec3<f32>(tilt * 2.0 + (vec2<f32>(0.5)-cellUV)*0.5, 1.0));
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    let cos_theta = max(dot(viewDir, normal), 0.0);
    let R0 = 0.04;
    let fresnel = R0 + (1.0 - R0) * pow(1.0 - cos_theta, 5.0);

    // ═══ Prismatic spectral dispersion per tile ═══
    let tileCenter = cellCenter + offset * 0.3;
    let WAVELENGTHS = array<f32, 4>(450.0, 520.0, 600.0, 680.0);
    var finalColor = vec3<f32>(0.0);
    var spectralResponse = vec4<f32>(0.0);

    for (var i: i32 = 0; i < 4; i = i + 1) {
        let ior = cauchyIOR(WAVELENGTHS[i], 1.5, cauchyB);
        let toCenter = uv - tileCenter;
        let d = length(toCenter);
        let lensStrength = glassCurvature * 0.4;
        let refractOffset = toCenter * (1.0 - 1.0 / ior) * lensStrength * (1.0 + d * 2.0);
        let refractedUV = fract(finalUV + refractOffset);

        let sample = textureSampleLevel(readTexture, u_sampler, refractedUV, 0.0);
        let absorption = exp(-glassThickness * (4.0 - f32(i)) * 0.15);
        let bandIntensity = dot(sample.rgb, wavelengthToRGB(WAVELENGTHS[i])) * absorption;

        spectralResponse[i] = bandIntensity;
        finalColor += wavelengthToRGB(WAVELENGTHS[i]) * bandIntensity * 0.8;
    }

    // Apply glass tint and transmission
    let glassColor = vec3<f32>(0.93, 0.96, 1.0);
    let thickness = 0.05 + (1.0 - bevel) * 0.1 + length(tilt) * 0.05;
    let absorptionGlass = exp(-(1.0 - glassColor) * thickness * 2.0);
    let transmission = (1.0 - fresnel) * (absorptionGlass.r + absorptionGlass.g + absorptionGlass.b) / 3.0;

    finalColor = finalColor * glassColor;

    // Specular Highlight
    let lightDir = normalize(vec3<f32>(vecToMouse, 0.5));
    let spec = pow(max(dot(normal, lightDir), 0.0), 16.0) * influence;
    finalColor = finalColor + spec * 0.8;

    // Mortar lines
    let mortar = smoothstep(0.0, 0.05, cellUV.x) * smoothstep(1.0, 0.95, cellUV.x) *
                 smoothstep(0.0, 0.05, cellUV.y) * smoothstep(1.0, 0.95, cellUV.y);
    let mortarTransmission = transmission * 0.3;
    var outColor = mix(vec4<f32>(finalColor * 0.2, mortarTransmission), vec4<f32>(finalColor, transmission), mortar);

    // Tone map
    outColor = vec4<f32>(outColor.rgb / (1.0 + outColor.rgb * 0.2), outColor.a);

    textureStore(writeTexture, gid.xy, outColor);
    textureStore(dataTextureA, gid.xy, spectralResponse);

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
