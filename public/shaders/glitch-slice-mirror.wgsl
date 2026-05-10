// ═══════════════════════════════════════════════════════════════════
//  Glitch Slice Mirror
//  Category: distortion
//  Features: mouse-driven, audio-reactive
//  Complexity: Medium
//  Chunks From: original glitch-slice-mirror
//  Created: 2026-05-10
//  By: Phase A Upgrade Swarm
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    var uv = vec2<f32>(global_id.xy) / resolution;
    var mouse = u.zoom_config.yz;
    let time = u.config.x;

    let paramIntensity = u.zoom_params.x;
    let paramSpeed = u.zoom_params.y;
    let paramScale = u.zoom_params.z;
    let paramDetail = u.zoom_params.w;

    let bass = plasmaBuffer[0].x;
    let audioBoost = 1.0 + bass * 0.5;

    // Mirror Logic
    var target_uv = uv;
    if (uv.x > mouse.x) {
        target_uv.x = mouse.x - (uv.x - mouse.x);
    }

    // Glitch Logic near seam
    let glitch_width = 0.1 * max(paramIntensity * 2.0, 0.001);
    let dist_to_seam = abs(uv.x - mouse.x);

    var color = vec4<f32>(0.0);

    if (dist_to_seam < glitch_width) {
        let intensity = (1.0 - dist_to_seam / max(glitch_width, 0.001)) * audioBoost;

        // Blocky noise
        let block_size = vec2<f32>(
            0.02 + paramScale * 0.06,
            0.01 + paramScale * 0.02
        );
        let seed = floor(uv / max(block_size, vec2<f32>(0.001))) + time * (0.1 + paramSpeed * 2.0);
        let noise = hash(fract(seed));

        if (noise > 0.8) {
            target_uv.x = target_uv.x + (noise - 0.5) * 0.1 * intensity;
        }

        // Clamp after displacement to prevent out-of-bounds sampling
        target_uv = clamp(target_uv, vec2<f32>(0.0), vec2<f32>(1.0));

        // Chromatic Aberration
        let split = (0.005 + paramDetail * 0.03) * intensity * noise;
        let r = textureSampleLevel(readTexture, u_sampler, target_uv + vec2<f32>(split, 0.0), 0.0).r;
        let g = textureSampleLevel(readTexture, u_sampler, target_uv, 0.0).g;
        let b = textureSampleLevel(readTexture, u_sampler, target_uv - vec2<f32>(split, 0.0), 0.0).b;

        // Luminance-based alpha
        let lum = dot(vec3<f32>(r, g, b), vec3<f32>(0.299, 0.587, 0.114));
        let alpha = clamp(lum, 0.3, 1.0);
        color = vec4<f32>(r, g, b, alpha);

        // Scanline darkening
        if (sin(uv.y * (50.0 + paramDetail * 300.0)) > 0.9) {
            color.rgb = color.rgb * 0.5;
        }
    } else {
        color = textureSampleLevel(readTexture, u_sampler, target_uv, 0.0);
    }

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);

    // Pass depth (using distorted/clamped UV)
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, target_uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
