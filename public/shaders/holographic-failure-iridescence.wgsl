// ═══════════════════════════════════════════════════════════════════
//  Holographic Failure Iridescence
//  Category: advanced-hybrid
//  Features: holographic, thin-film-interference, glitch, depth-aware
//  Complexity: High
//  Chunks From: holographic-projection-failure.wgsl, spec-iridescence-engine.wgsl
//  Created: 2026-04-18
//  By: Agent CB-13 — Retro & Glitch Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Simulated hologram projection failure merged with thin-film
//  interference iridescence. Flickering artifacts and block noise
//  overlay soap-bubble spectral colors driven by depth and time.
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

fn rand(co: vec2<f32>) -> f32 {
    return fract(sin(dot(co, vec2<f32>(12.9898, 78.233))) * 43758.5453);
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
    for (var lambda = 380.0; lambda <= 700.0; lambda = lambda + 20.0) {
        let phase = opd / lambda;
        let interference = cos(phase * 6.28318530718) * 0.5 + 0.5;
        color += wavelengthToRGB(lambda) * interference;
        sampleCount = sampleCount + 1.0;
    }
    return color / max(sampleCount, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let time = u.config.x;

    let failureAmount = u.zoom_params.x;
    let holographicIntensity = u.zoom_params.y;
    let filmIOR = mix(1.2, 2.4, u.zoom_params.z);
    let turbulence = mix(0.0, 1.0, u.zoom_params.w);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let sample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Flicker
    let flicker = step(rand(vec2<f32>(time * 20.0, 0.0)), 0.9 - failureAmount * 0.5);

    // ═══ IRIDESCENCE ═══
    let toCenter = uv - vec2<f32>(0.5);
    let dist = length(toCenter);
    let cosTheta = sqrt(max(1.0 - dist * dist * 0.5, 0.01));

    let filmThicknessBase = mix(200.0, 800.0, holographicIntensity);
    let noiseVal = hash12(uv * 12.0 + time * 0.1) * 0.5
                 + hash12(uv * 25.0 - time * 0.15) * 0.25;
    var thickness = filmThicknessBase * (0.7 + depth * 0.6 + noiseVal * turbulence);

    // Mouse interaction
    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;
    if (isMouseDown) {
        let mouseDist = length(uv - mousePos);
        let mouseInfluence = exp(-mouseDist * mouseDist * 800.0);
        thickness += mouseInfluence * 300.0 * sin(time * 3.0 + mouseDist * 30.0);
    }

    let iridescent = thinFilmColor(thickness, cosTheta, filmIOR);
    let fresnel = pow(1.0 - cosTheta, 3.0);

    // ═══ HOLOGRAPHIC FAILURE ═══
    let holographic = vec3<f32>(
        0.3 + 0.4 * sin(time + uv.x * 5.0),
        0.5 + 0.3 * sin(time + uv.x * 5.0 + 2.09),
        0.7 + 0.3 * sin(time + uv.x * 5.0 + 4.18)
    );

    // Failure artifacts
    let blockNoise = rand(floor(uv * vec2<f32>(20.0, 5.0)) + time);
    let artifact = step(1.0 - failureAmount, blockNoise);

    // Combine: base -> iridescence -> holographic -> failure
    var finalColor = mix(sample.rgb * flicker, iridescent * holographicIntensity, fresnel * 0.7);
    finalColor = mix(finalColor, holographic * flicker, holographicIntensity * 0.3);
    finalColor = finalColor + artifact * 0.5 * failureAmount;

    // Depth-layered alpha
    let luma = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
    let depthAlpha = mix(0.3, 1.0, depth);
    let lumaAlpha = mix(0.4, 1.0, luma);
    let alpha = mix(lumaAlpha, depthAlpha, 0.5) * flicker;

    // HDR tone map
    finalColor = finalColor / (1.0 + finalColor * 0.2);
    finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, gid.xy, vec4<f32>(finalColor, alpha));
    textureStore(dataTextureA, gid.xy, vec4<f32>(iridescent, thickness / 1000.0));

    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
