// ═══════════════════════════════════════════════════════════════════
//  Polka Dot Reveal
//  Category: artistic
//  Features: mouse-driven, audio-reactive
//  Complexity: Medium
//  Created: 2026-05-10
//  By: Shader Upgrade Swarm Phase A
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    var uv = vec2<f32>(global_id.xy) / resolution;
    var mouse = u.zoom_config.yz;
    let time = u.config.x;

    // Parameters
    let intensity = clamp(u.zoom_params.x, 0.0, 1.0);
    let speed = clamp(u.zoom_params.y, 0.0, 1.0);
    let scale = clamp(u.zoom_params.z, 0.01, 1.0);
    let detail = clamp(u.zoom_params.w, 0.01, 1.0);

    // Audio reactivity — bass drives dot radius
    let bass = plasmaBuffer[0].x;

    // Calculate distance influence
    let aspect = resolution.x / resolution.y;
    let dist = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(mouse.x * aspect, mouse.y));

    // Map distance to grid density using Scale param
    let densityMin = mix(10.0, 40.0, scale);
    let densityMax = mix(80.0, 250.0, scale);
    let density = mix(densityMax, densityMin, smoothstep(0.0, 0.8, dist));

    let grid_uv = floor(uv * density) / density;
    let cell_center = grid_uv + (0.5 / density);

    // Sample color at cell center
    let color = textureSampleLevel(readTexture, u_sampler, cell_center, 0.0);
    let lum = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Determine dot radius based on luminance and audio
    let max_radius = 0.5;
    let audioBoost = 1.0 + bass * 0.4;
    let radius = lum * max_radius * audioBoost;

    // Subtle radius pulse from Speed param
    let pulse = 1.0 + sin(time * (0.5 + speed * 2.0)) * 0.05 * speed;
    let animated_radius = radius * pulse;

    // Local UV in cell [0, 1]
    let local_uv = fract(uv * density);
    let dist_to_center = distance(local_uv, vec2<f32>(0.5));

    // Anti-aliasing width adjusted by density and Detail param
    let aa = mix(0.03, 0.15, detail) * density / 50.0;
    let circle = 1.0 - smoothstep(animated_radius - aa, animated_radius + aa, dist_to_center);

    // Meaningful alpha: brighter dots are more opaque, scaled by intensity
    let dotAlpha = mix(0.2, 1.0, lum) * intensity;
    let dotColor = vec4<f32>(color.rgb, dotAlpha);

    // Transparent background where there is no dot
    var final_color = mix(vec4<f32>(0.0, 0.0, 0.0, 0.0), dotColor, circle);

    // Randomization-safety clamps
    final_color = clamp(final_color, vec4<f32>(0.0), vec4<f32>(1.0));

    textureStore(writeTexture, vec2<i32>(global_id.xy), final_color);

    // Pass depth through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
