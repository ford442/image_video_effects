// ═══════════════════════════════════════════════════════════════════
//  Black Hole
//  Category: distortion
//  Features: gravitational-lensing, chromatic-aberration, audio-accretion, mouse-secondary, atmospheric-depth
//  Complexity: Medium
//  Chunks From: previous black-hole work + gravitational lensing + accretion disk patterns
//  Created: 2026-05-30
//  Updated: 2026-05-31
//  By: Grok (visual flourish pass — richer lensing, accretion, and atmosphere)
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

    // Time for animation
    let t = u.config.x;

    var final_color = vec3<f32>(0.0, 0.0, 0.0);

    if (dist < radius) {
        // Event Horizon (Black Void)
        final_color = vec3<f32>(0.0, 0.0, 0.0);
    } else {
        // Gravitational Lensing
        let dist_from_surface = dist - radius;
        
        // Inverse square-ish falloff for gravity
        let distortion = (gravity * 0.1) / (dist_from_surface * 5.0 + 0.1);

        // Direction from pixel towards mouse
        let pinch_factor = distortion * (0.5 + lensing_scale);

        // Chromatic gravitational lensing (different wavelengths bend differently)
        let chr_amount = distortion * 0.018;
        let offset_r = (d_vec_aspect / max(length(d_vec_aspect), 0.0001)) * (pinch_factor + chr_amount);
        let offset_g = (d_vec_aspect / max(length(d_vec_aspect), 0.0001)) * pinch_factor;
        let offset_b = (d_vec_aspect / max(length(d_vec_aspect), 0.0001)) * (pinch_factor - chr_amount);

        let offset_uv_r = vec2<f32>(offset_r.x / aspect, offset_r.y);
        let offset_uv_g = vec2<f32>(offset_g.x / aspect, offset_g.y);
        let offset_uv_b = vec2<f32>(offset_b.x / aspect, offset_b.y);

        let sample_r = textureSampleLevel(readTexture, u_sampler, clamp(uv - offset_uv_r, vec2<f32>(0.001,0.001), vec2<f32>(0.999,0.999)), 0.0).r;
        let sample_g = textureSampleLevel(readTexture, u_sampler, clamp(uv - offset_uv_g, vec2<f32>(0.001,0.001), vec2<f32>(0.999,0.999)), 0.0).g;
        let sample_b = textureSampleLevel(readTexture, u_sampler, clamp(uv - offset_uv_b, vec2<f32>(0.001,0.001), vec2<f32>(0.999,0.999)), 0.0).b;

        let bg_color = vec3<f32>(sample_r, sample_g, sample_b);

        // === Enhanced Accretion Disk with Visual Flourish ===
        let glow_falloff = exp(-dist_from_surface * 20.0);
        
        // Audio-reactive turbulence in the disk
        let angle = atan2(d_vec_aspect.y, d_vec_aspect.x);
        let disk_turb = sin(angle * 14.0 + t * 9.0 + bass * 5.0) * (0.12 + treble * 0.08) + 1.0;
        
        // Rich temperature gradient in the accretion disk
        let temp = 1.0 - (dist_from_surface * 0.8);
        let disk_color = vec3<f32>(
            1.0,
            0.55 + mids * 0.35 + temp * 0.15,
            0.15 + treble * 0.45 + temp * 0.25
        ) * disk_turb;
        
        let glow_color = disk_color * glow_intensity * 3.5 * glow_falloff;

        // Subtle redshift near the horizon
        let redshift = smoothstep(0.0, 0.6, dist_from_surface);
        let final_bg = mix(bg_color * vec3<f32>(1.0, 0.92, 0.85), bg_color, redshift);

        final_color = final_bg + glow_color;
    }

    let horizonMask = 1.0 - smoothstep(radius, radius + 0.08 + lensing_scale * 0.1, dist);
    // Richer alpha with atmospheric falloff and accretion contribution
    let atm = exp(-dist * 1.8);
    let finalAlpha = clamp(0.12 + horizonMask * 0.5 + glow_intensity * 0.18 + atm * 0.15, 0.06, 1.15);
    let a = clamp(finalAlpha, 0.0, 1.0);
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(final_color * a, a));

    // Passthrough depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(dist, radius, horizonMask, finalAlpha));
}
