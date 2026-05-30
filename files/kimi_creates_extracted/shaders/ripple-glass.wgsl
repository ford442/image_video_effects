// ═══════════════════════════════════════════════════════════════════
//  Ripple Glass
//  Category: distortion
//  Features: mouse-driven, multi-frequency, glass-refraction
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

const PI: f32 = 3.141592653589793;

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;

    let freq1 = u.zoom_params.x * 8.0 + 2.0;
    let freq2 = u.zoom_params.y * 16.0 + 4.0;
    let amp = u.zoom_params.z * 0.03 + 0.005;
    let speed = u.zoom_params.w * 2.0 + 0.5;

    var mouse = u.zoom_config.yz;

    var displacement = vec2<f32>(0.0);

    // Layer 1: Large slow ripples
    let phase1 = uv.x * freq1 + uv.y * freq1 * 0.7 + time * speed;
    displacement.x += sin(phase1) * amp;
    displacement.y += cos(phase1 * 0.8) * amp;

    // Layer 2: Smaller faster ripples
    let phase2 = uv.x * freq2 * 1.3 - uv.y * freq2 + time * speed * 1.5;
    displacement.x += sin(phase2) * amp * 0.5;
    displacement.y += cos(phase2 * 1.1) * amp * 0.5;

    // Layer 3: Mouse-centered radial ripples
    let mouseOffset = uv - mouse;
    let mouseDist = length(mouseOffset * vec2<f32>(aspect, 1.0));
    let mouseWave = sin(mouseDist * freq1 * 2.0 - time * speed * 3.0);
    let mouseFalloff = exp(-mouseDist * 4.0);
    displacement += normalize(mouseOffset + vec2<f32>(0.001)) * mouseWave * amp * 2.0 * mouseFalloff;

    // Layer 4: Fine noise ripple
    let noiseRipple = hash(uv * 100.0 + time) - 0.5;
    displacement += vec2<f32>(noiseRipple) * amp * 0.3;

    let displacedUV = clamp(uv + displacement, vec2<f32>(0.0), vec2<f32>(1.0));
    let color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

    // Subtle chromatic separation at ripple peaks
    let chromaticOffset = length(displacement) * 8.0;
    let r = textureSampleLevel(readTexture, u_sampler, clamp(displacedUV + vec2<f32>(chromaticOffset * 0.002, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(displacedUV - vec2<f32>(chromaticOffset * 0.002, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    let finalColor = vec3<f32>(r, color.g, b);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
