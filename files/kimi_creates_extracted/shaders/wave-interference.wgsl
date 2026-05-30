// ═══════════════════════════════════════════════════════════════════
//  Wave Interference
//  Category: distortion
//  Features: mouse-driven, interference-pattern, displacement
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
const TAU: f32 = 6.283185307179586;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;

    let freq = u.zoom_params.x * 20.0 + 5.0;
    let amp = u.zoom_params.y * 0.04 + 0.005;
    let speed = u.zoom_params.z * 3.0 + 0.5;
    let sources = u.zoom_params.w * 3.0 + 2.0;

    var mouse = u.zoom_config.yz;

    var displacement = vec2<f32>(0.0);

    // Source 1: Mouse position
    let s1 = mouse;
    let d1 = length((uv - s1) * vec2<f32>(aspect, 1.0));
    let wave1 = sin(d1 * freq - time * speed) / (d1 * 2.0 + 0.5);

    // Source 2: Counter-rotating
    let s2 = vec2<f32>(0.5 + cos(time * 0.3 * speed) * 0.3, 0.5 + sin(time * 0.3 * speed) * 0.3);
    let d2 = length((uv - s2) * vec2<f32>(aspect, 1.0));
    let wave2 = sin(d2 * freq * 1.3 + time * speed * 0.8) / (d2 * 2.0 + 0.5);

    // Combine waves
    var combinedWave = wave1 + wave2;

    // Add third source if parameter calls for it
    if (sources > 2.5) {
        let s3 = vec2<f32>(0.5 + cos(time * 0.2 * speed + PI) * 0.25, 0.5 + sin(time * 0.5 * speed) * 0.2);
        let d3 = length((uv - s3) * vec2<f32>(aspect, 1.0));
        let wave3 = sin(d3 * freq * 0.7 - time * speed * 1.2) / (d3 * 2.0 + 0.5);
        combinedWave += wave3;
    }

    // Add fourth source
    if (sources > 3.5) {
        let s4 = vec2<f32>(0.5 + cos(time * 0.4 * speed + PI * 0.5) * 0.35, 0.5 + sin(time * 0.25 * speed + PI) * 0.35);
        let d4 = length((uv - s4) * vec2<f32>(aspect, 1.0));
        let wave4 = sin(d4 * freq * 1.1 + time * speed * 0.6) / (d4 * 2.0 + 0.5);
        combinedWave += wave4;
    }

    // Convert wave height to displacement
    displacement = vec2<f32>(combinedWave * amp);

    // Rotate displacement for more interesting distortion
    let rotAngle = time * 0.1;
    let cosR = cos(rotAngle);
    let sinR = sin(rotAngle);
    displacement = vec2<f32>(
        displacement.x * cosR - displacement.y * sinR,
        displacement.x * sinR + displacement.y * cosR
    );

    let displacedUV = clamp(uv + displacement, vec2<f32>(0.0), vec2<f32>(1.0));
    let color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

    // Slight color shift based on wave intensity
    let intensity = clamp(abs(combinedWave) * 0.3, 0.0, 0.3);
    let finalColor = color + vec3<f32>(intensity * 0.1, intensity * 0.05, intensity * 0.15);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
