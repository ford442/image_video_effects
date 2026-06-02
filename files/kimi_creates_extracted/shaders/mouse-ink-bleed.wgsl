// ═══════════════════════════════════════════════════════════════════
//  Mouse Ink Bleed
//  Category: interactive-mouse
//  Features: mouse-driven, ink-diffusion, organic-spread
//  Complexity: Medium
//  Created: 2026-05-31
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

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;

    let spread = u.zoom_params.x * 0.08 + 0.01;
    let turbulence = u.zoom_params.y * 4.0;
    let decay = u.zoom_params.z * 2.0 + 0.5;
    let colorIntensity = u.zoom_params.w * 2.0;

    var mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w > 0.5;

    // Ink spread radius based on mouse interaction
    var inkRadius = 0.0;
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let elapsed = time - ripple.z;
        if (elapsed > 0.0 && elapsed < 4.0) {
            let dist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
            let rippleRadius = elapsed * spread * 4.0;
            let rippleWidth = 0.02 + elapsed * 0.01;
            let rippleStrength = exp(-decay * elapsed) * smoothstep(rippleRadius + rippleWidth, rippleRadius, dist);
            inkRadius = max(inkRadius, rippleStrength);
        }
    }

    // Active mouse ink when held down
    if (mouseDown) {
        let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
        let activeInk = exp(-mouseDist * mouseDist * 50.0) * 0.8;
        inkRadius = max(inkRadius, activeInk);
    }

    // Turbulent noise for organic ink edges
    let noiseVal = noise(uv * turbulence * 8.0 + time * 0.2);
    let noiseVal2 = noise(uv * turbulence * 16.0 - time * 0.15);
    let organicEdge = noiseVal * 0.5 + noiseVal2 * 0.3;

    // Displace UV based on ink field
    let gradX = noise(uv * turbulence * 6.0 + vec2<f32>(0.01, 0.0)) - noise(uv * turbulence * 6.0 - vec2<f32>(0.01, 0.0));
    let gradY = noise(uv * turbulence * 6.0 + vec2<f32>(0.0, 0.01)) - noise(uv * turbulence * 6.0 - vec2<f32>(0.0, 0.01));
    let displacement = vec2<f32>(gradX, gradY) * inkRadius * spread * 2.0;

    let displacedUV = clamp(uv + displacement, vec2<f32>(0.0), vec2<f32>(1.0));
    var color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

    // Darken and desaturate ink areas
    let luminance = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let inkColor = mix(vec3<f32>(luminance), color * vec3<f32>(0.3, 0.25, 0.35), 0.3);
    color = mix(color, inkColor, inkRadius * colorIntensity);

    // Add subtle ink coloration at edges
    let edgeGlow = smoothstep(0.1, 0.6, inkRadius) * (1.0 - smoothstep(0.4, 0.9, inkRadius));
    color += vec3<f32>(0.05, 0.02, 0.08) * edgeGlow * colorIntensity;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
