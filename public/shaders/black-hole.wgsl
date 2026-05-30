// ═══════════════════════════════════════════════════════════════════
//  Black Hole
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Low
//  Chunks From: black-hole
//  Created: 2026-05-30
//  By: Copilot CLI
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
  config: vec4<f32>,       // x=Time, y=Ripples, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // Params
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
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    // Parameters
    let gravity = u.zoom_params.x * (1.0 + bass * 0.35);        // Distortion strength
    let radius = u.zoom_params.y * 0.3;   // Event horizon size (0.0 - 0.3)
    let glow_intensity = u.zoom_params.z * (1.0 + treble * 0.4); // Accretion disk glow
    let lensing_scale = u.zoom_params.w * (1.0 + mids * 0.25);  // Lensing width factor

    // Mouse Interaction (Center of Black Hole)
    var mouse = u.zoom_config.yz;

    // Calculate vector from mouse to current pixel (aspect corrected)
    let d_vec_raw = uv - mouse;
    let d_vec_aspect = vec2<f32>(d_vec_raw.x * aspect, d_vec_raw.y);
    let dist = length(d_vec_aspect);

    var final_color = vec3<f32>(0.0, 0.0, 0.0);

    if (dist < radius) {
        // Event Horizon (Black Void)
        final_color = vec3<f32>(0.0, 0.0, 0.0);
    } else {
        // Gravitational Lensing
        // We pull pixels from *closer* to the center effectively stretching the background around the hole.
        // Formula: sample_uv = uv - (offset_vector)
        // Offset should be larger when close to radius.
        
        let dist_from_surface = dist - radius;
        
        // Inverse square-ish falloff for gravity
        let distortion = (gravity * 0.1) / (dist_from_surface * 5.0 + 0.1);

        // Direction from pixel towards mouse
        let pinch_factor = distortion * (0.5 + lensing_scale);

        // We need to apply aspect correction to the offset to avoid oval distortion
        let offset = (d_vec_aspect / max(length(d_vec_aspect), 0.0001)) * pinch_factor;
        // Un-aspect the offset for UV space
        let offset_uv = vec2<f32>(offset.x / aspect, offset.y);

        let sample_uv = clamp(uv - offset_uv, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));

        // Wrap/Repeat is handled by sampler, but let's clamp or wrap manually if needed?
        // Default sampler is Repeat.

        let bg_color = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0).rgb;

        // Accretion Disk Glow
        // Very bright near the radius
        let glow_falloff = exp(-dist_from_surface * 20.0);
        let glow_color = vec3<f32>(1.0, 0.7 + mids * 0.2, 0.3 + treble * 0.15) * glow_intensity * 3.0 * glow_falloff;

        // Doppler shifting / Redshift? (Optional, maybe just color tint)
        // Let's add the glow
        final_color = bg_color + glow_color;
    }

    let horizonMask = 1.0 - smoothstep(radius, radius + 0.08 + lensing_scale * 0.1, dist);
    let finalAlpha = clamp(0.16 + horizonMask * 0.45 + glow_intensity * 0.12, 0.08, 1.0);
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(final_color, finalAlpha));

    // Passthrough depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(dist, radius, horizonMask, finalAlpha));
}
