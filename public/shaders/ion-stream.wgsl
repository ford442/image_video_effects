// ═══════════════════════════════════════════════════════════════════
//  ion-stream - Turbulent displacement effect with mouse interaction
//  Category: distortion
//  Features: upgraded-rgba, depth-aware, displacement, turbulence
//  Upgraded: 2026-03-22
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    
    let coord = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    var mouse = u.zoom_config.yz;
    var center = mouse;
    let distVec = (uv - center) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    let strength = u.zoom_params.x * 0.5;
    let falloff = u.zoom_params.y * 5.0 + 0.1;
    let turbulence = u.zoom_params.z;
    let colorShift = u.zoom_params.w;

    // Displace away from mouse
    var offset = vec2<f32>(0.0);
    if (dist > 0.001) {
        var dir = normalize(distVec);
        let influence = strength / (1.0 + pow(dist * falloff, 2.0));

        // Add turbulence
        let angle = atan2(dir.y, dir.x) + turbulence * dist * 10.0;
        let turbDir = vec2<f32>(cos(angle), sin(angle));

        offset = turbDir * influence;
    }

    let sampleUV = uv - offset; // Look back to see where pixel came from
    var color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;

    // Color tint based on displacement
    let displacementLen = length(offset);
    if (displacementLen > 0.001) {
        let tint = vec3<f32>(1.0 + colorShift, 0.8, 0.5);
        color = mix(color, color * tint, min(displacementLen * 10.0, 1.0));
    }

    // Calculate alpha based on displacement and luminance
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let dispAlpha = mix(0.85, 1.0, min(displacementLen * 5.0, 1.0));
    let alpha = mix(dispAlpha * 0.8, dispAlpha, luma);
    let finalAlpha = mix(alpha * 0.8, alpha, depth);

    textureStore(writeTexture, coord, vec4<f32>(color, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
