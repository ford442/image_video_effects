// ═══════════════════════════════════════════════════════════════════
//  Bayer Dither Interactive
//  Category: effects
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-17
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount/FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn get_bayer_8x8(x: u32, y: u32) -> f32 {
    var m = array<i32, 64>(
        0, 32, 8, 40, 2, 34, 10, 42,
        48, 16, 56, 24, 50, 18, 58, 26,
        12, 44, 4, 36, 14, 46, 6, 38,
        60, 28, 52, 20, 62, 30, 54, 22,
        3, 35, 11, 43, 1, 33, 9, 41,
        51, 19, 59, 27, 49, 17, 57, 25,
        15, 47, 7, 39, 13, 45, 5, 37,
        63, 31, 55, 23, 61, 29, 53, 21
    );
    let idx = (y % 8u) * 8u + (x % 8u);
    return f32(m[idx]) / 64.0;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

    let coord     = vec2<i32>(gid.xy);
    let pixel_pos = vec2<f32>(gid.xy);
    let uv        = pixel_pos / resolution;

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let mouse = u.zoom_config.yz;

    // Scale the coordinate system for pixelation effect
    let scale      = mix(4.0, 64.0, u.zoom_params.w);
    let scaled_pos = floor(pixel_pos / scale);
    let sample_uv  = (scaled_pos * scale + scale * 0.5) / resolution;

    let original_color = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0).rgb;

    // Pre-processing: Contrast
    let contrast = u.zoom_params.y * 2.0 + 0.5;
    let c_color  = (original_color - 0.5) * contrast + 0.5;

    // Get Bayer Threshold
    let bayer = get_bayer_8x8(u32(scaled_pos.x), u32(scaled_pos.y));

    // Quantization Levels — bass makes levels more extreme (fewer levels = more posterized)
    let base_levels = max(1.0, u.zoom_params.x * 30.0 + 1.0);
    let levels      = max(1.0, base_levels * (1.0 + bass * 0.5));

    // Mids affect the t spread (dither threshold spread)
    let t_spread = mix(0.0, 2.0, u.zoom_params.z) * (1.0 + mids * 0.4);
    let L        = max(2.0, floor(levels));
    let t        = bayer * t_spread;

    // Ordered dither per channel — vec3 component-wise
    var final_dither: vec3<f32> = original_color;
    final_dither.r = floor(c_color.r * (L - 1.0) + (t - 0.5) + 0.5) / max(L - 1.0, 0.001);
    final_dither.g = floor(c_color.g * (L - 1.0) + (t - 0.5) + 0.5) / max(L - 1.0, 0.001);
    final_dither.b = floor(c_color.b * (L - 1.0) + (t - 0.5) + 0.5) / max(L - 1.0, 0.001);

    // Mix: mouse.x controls original vs dithered
    let mix_factor = mouse.x;
    let final_rgb  = mix(original_color, final_dither, mix_factor);

    // Meaningful alpha: dither difference from original + bass pulse
    let ditherDiff = length(final_dither - original_color);
    let alpha      = clamp(ditherDiff * 3.0 + bass * 0.3 + bayer * 0.2, 0.0, 1.0);

    let finalColor = vec4<f32>(final_rgb, alpha);

    textureStore(writeTexture, coord, finalColor);
    textureStore(dataTextureA, coord, finalColor);

    // Depth passthrough
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
