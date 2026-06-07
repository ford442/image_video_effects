// ═══════════════════════════════════════════════════════════════════
//  Directional Blur Wipe
//  Category: post-processing
//  Features: mouse-driven, audio-reactive, blur-wipe, depth-scatter, chromatic-offset, upgraded-rgba
//  Complexity: High
//  Chunks From: directional-blur-wipe, bass_env
//  Created: 2024-01-01
//  Upgraded: 2026-05-31
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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthScatter = mix(0.7, 1.3, depth);

    let split_pos_param = u.zoom_params.x;
    let angle_param = u.zoom_params.y;
    let strength_param = u.zoom_params.z * bass_env(bass, mids);
    let samples_param = u.zoom_params.w;

    let angle = angle_param * 6.28 + (mouse.y - 0.5) * 3.14;
    let dir = vec2<f32>(cos(angle), sin(angle));
    let normal = vec2<f32>(-dir.y, dir.x);

    let p_line = mouse;
    let uv_aspect = vec2<f32>(uv.x * aspect, uv.y);
    let p_line_aspect = vec2<f32>(p_line.x * aspect, p_line.y);
    let dist = dot(uv_aspect - p_line_aspect, normal);

    var color = vec4<f32>(0.0);
    if (dist < 0.0) {
        color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    } else {
        let num_samples = i32(samples_param * 50.0) + 5;
        let strength = strength_param * 0.05 * depthScatter;

        var accum = vec3<f32>(0.0);
        var weight = 0.0;

        // Chromatic offset: R and B sample at slightly different offsets per sample
        for (var i = 0; i < num_samples; i = i + 1) {
            let t = f32(i) / f32(num_samples - 1);
            let offset = dir * t * strength;
            let chroma = treble * 0.01 * t;

            let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
            let sampleColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
            accum = accum + sampleColor.rgb;
            weight = weight + 1.0;
        }
        let blurRGB = accum / weight;

        // Per-channel blur for chromatic dispersion
        let rUV = clamp(uv + dir * strength * 1.1, vec2<f32>(0.0), vec2<f32>(1.0));
        let bUV = clamp(uv - dir * strength * 0.9, vec2<f32>(0.0), vec2<f32>(1.0));
        let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
        let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

        color = vec4<f32>(mix(blurRGB.r, r, 0.3), blurRGB.g, mix(blurRGB.b, b, 0.3), 1.0);

        // Bass drives blur-side brightness pulse
        color = color + vec4<f32>(bass * 0.1 * (dist * 0.5 + 0.5), bass * 0.05, 0.0, 0.0);

        let line_width = 0.005;
        if (dist < line_width) {
             color = color + vec4<f32>(0.2 + mids * 0.1, 0.15 + treble * 0.1, 0.1, 0.0);
        }
    }

    let alpha = color.a;
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color.rgb, alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(color.rgb, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
