// ═══════════════════════════════════════════════════════════════════
//  Steampunk Gear Lens
//  Category: image
//  Features: mouse-driven, audio-reactive
//  Complexity: Medium
//  Phase A Upgrade Swarm
//  Created: 2026-05-10
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
  zoom_params: vec4<f32>,  // x=Size, y=Teeth, z=Speed, w=Sepia
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let aspectVec = vec2<f32>(aspect, 1.0);
    var mouse = u.zoom_config.yz;
    let time = u.config.x;

    // Audio reactivity
    let bass = plasmaBuffer[0].x;

    let size = mix(0.1, 0.6, clamp(u.zoom_params.x, 0.0, 1.0));
    let teeth_count = mix(6.0, 20.0, clamp(u.zoom_params.y, 0.0, 1.0));
    let speed = (clamp(u.zoom_params.z, 0.0, 1.0) - 0.5) * 4.0;
    let sepia_str = clamp(u.zoom_params.w, 0.0, 1.0);

    var center = mouse;
    var p = (uv - center) * aspectVec;
    let r = length(p);
    let a = atan2(p.y, p.x);

    // Rotation with audio-reactive boost
    let audioBoost = 1.0 + bass * 0.5;
    let rot = time * speed * audioBoost;
    let a_rot = a - rot;

    // Gear Shape
    let teeth_angle = a_rot * teeth_count;
    let tooth = smoothstep(-0.5, 0.0, cos(teeth_angle)) - smoothstep(0.0, 0.5, cos(teeth_angle));
    let gear_r = max(size, 0.001) + 0.05 * sin(teeth_angle);

    let mask = 1.0 - smoothstep(gear_r, gear_r + 0.01, r);

    // Rim
    let rim = smoothstep(gear_r - 0.05, gear_r - 0.04, r) * mask;

    // Lens UVs
    let c = cos(rot);
    let s = sin(rot);
    let p_rot = vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);
    let uv_lens = center + p_rot / aspectVec;

    var color: vec4<f32>;

    if (mask > 0.0) {
        // Inside Gear
        var col = textureSampleLevel(readTexture, u_sampler, uv_lens, 0.0);

        // Sepia Filter
        let gray = dot(col.rgb, vec3<f32>(0.299, 0.587, 0.114));
        let sepia_col = vec3<f32>(gray * 1.2, gray * 1.0, gray * 0.8);
        let sepiaAlpha = mix(0.85, 1.0, gray);
        col = mix(col, vec4<f32>(sepia_col, sepiaAlpha), sepia_str);

        // Add Metallic Rim
        let metal = vec4<f32>(0.8, 0.6, 0.3, 0.9);
        color = mix(col, metal, rim);
    } else {
        // Outside Gear
        color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    }

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);

    // writeDepthTexture pass-through
    let depthVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depthVal, 0.0, 0.0, 1.0));
}
