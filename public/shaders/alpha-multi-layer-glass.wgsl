// ═══════════════════════════════════════════════════════════════════
//  Alpha Multi-Layer Glass
//  Category: visual-effects
//  Features: mouse-driven, rgba-data-channel
//  Complexity: Medium
//  RGBA Channels:
//    R = Refracted red (post-distortion)
//    G = Refracted green (with chromatic offset)
//    B = Refracted blue (with larger chromatic offset)
//    A = Accumulated transmittance (how much light passes through)
//  Why f32: Transmittance is the product of multiple layer factors
//  and needs precision to avoid total darkness after 3+ layers.
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

// ═══ CHUNK: hash12 (from chunk-library.md / gen_grid.wgsl) ═══
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let time = u.config.x;

    // === PARAMETERS ===
    let layerCount = 3.0;
    let iorBase = mix(1.1, 1.6, u.zoom_params.x);
    let thickness = mix(0.001, 0.01, u.zoom_params.y);
    let chromaticStrength = u.zoom_params.z * 0.003;

    // === GLASS SURFACE NORMAL (procedural) ===
    let noiseUV = uv * 4.0 + vec2<f32>(time * 0.01, time * 0.008);
    let normalX = (fbm2(noiseUV, 3) - 0.5) * 2.0;
    let normalY = (fbm2(noiseUV + vec2<f32>(50.0), 3) - 0.5) * 2.0;
    let surfaceNormal = normalize(vec2<f32>(normalX, normalY));

    // === MOUSE DISTORTION ===
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = smoothstep(0.3, 0.0, mouseDist) * mouseDown;
    let mouseNormal = normalize(uv - mousePos + vec2<f32>(0.0001));
    let finalNormal = normalize(mix(surfaceNormal, mouseNormal, mouseInfluence * 0.5));

    // === RIPPLE DISTORTION ===
    let rippleCount = min(u32(u.config.y), 50u);
    var rippleNormal = vec2<f32>(0.0);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age < 1.5 && rDist < 0.15) {
            let strength = smoothstep(0.15, 0.0, rDist) * max(0.0, 1.0 - age * 0.7);
            let dir = normalize(uv - ripple.xy + vec2<f32>(0.0001));
            rippleNormal += dir * strength;
        }
    }
    let totalNormal = normalize(finalNormal + rippleNormal * 0.3);

    // === MULTI-LAYER REFRACTION ===
    var totalTransmittance = 1.0;
    var finalColor = vec3<f32>(0.0);

    for (var layer = 0; layer < 3; layer = layer + 1) {
        let layerF = f32(layer);
        let ior = iorBase + layerF * 0.05;

        // Fresnel reflectance (Schlick approximation)
        let cosI = max(0.0, totalNormal.y);
        let R0 = pow((1.0 - ior) / (1.0 + ior), 2.0);
        let reflectance = R0 + (1.0 - R0) * pow(1.0 - cosI, 5.0);
        let layerTransmittance = 1.0 - reflectance * 0.3;

        // Refraction offset per layer
        let refractOffset = totalNormal * thickness * (layerF + 1.0);

        // Chromatic aberration: different IOR per channel
        let refractR = uv + refractOffset * (1.0 + chromaticStrength * 1.0);
        let refractG = uv + refractOffset * (1.0 + chromaticStrength * 1.5);
        let refractB = uv + refractOffset * (1.0 + chromaticStrength * 2.0);

        let sampleR = textureSampleLevel(readTexture, u_sampler, clamp(refractR, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
        let sampleG = textureSampleLevel(readTexture, u_sampler, clamp(refractG, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
        let sampleB = textureSampleLevel(readTexture, u_sampler, clamp(refractB, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

        // Layer tint
        let tint = vec3<f32>(
            1.0 - layerF * 0.1,
            1.0 - layerF * 0.05,
            1.0 - layerF * 0.02
        );

        let layerColor = vec3<f32>(sampleR, sampleG, sampleB) * tint;
        finalColor += layerColor * totalTransmittance * layerTransmittance;
        totalTransmittance *= layerTransmittance;
    }

    // Add background through remaining transmittance
    let bgColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    finalColor += bgColor * totalTransmittance;

    finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.0));

    // === STORE STATE ===
    textureStore(dataTextureA, coord, vec4<f32>(finalColor, totalTransmittance));

    // === WRITE DISPLAY ===
    textureStore(writeTexture, coord, vec4<f32>(finalColor, totalTransmittance));

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
