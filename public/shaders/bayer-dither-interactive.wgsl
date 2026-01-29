// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
        return;
    }

    // Pixel coordinates
    let pixel_pos = vec2<f32>(gid.xy);
    let uv = pixel_pos / resolution;

    // Params
    // Mouse X: Dither Strength / Mix (1.0 = full dither)
    // Mouse Y: Scale of the dither pattern (pixelation)
    let mouse = u.zoom_config.yz;

    // Scale the coordinate system for pixelation effect
    // Scale factor: 1.0 to 16.0
    let scale = mix(1.0, 16.0, mouse.y);
    let scaled_pos = floor(pixel_pos / scale);
    let sample_uv = (scaled_pos * scale + scale * 0.5) / resolution;

    let original_color = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0).rgb;

    // Pre-processing: Contrast
    let contrast = u.zoom_params.y * 2.0 + 0.5; // 0.5 to 2.5
    let c_color = (original_color - 0.5) * contrast + 0.5;

    // Get Bayer Threshold
    let bayer = get_bayer_8x8(u32(scaled_pos.x), u32(scaled_pos.y));

    // Quantization Levels (Bit Depth)
    // 1.0 (2 colors) to 8.0 (256 colors approx if logarithmic?)
    // Linear: 2 to 32
    let levels = max(1.0, u.zoom_params.x * 30.0 + 1.0);

    // Dithering logic
    // Add noise based on bayer value before quantization
    // Spread determines how much the dither affects the value
    let spread = 1.0 / levels;

    let dither_val = (bayer - 0.5) * spread;

    var dithered_color = c_color + dither_val;

    // Quantize
    dithered_color = floor(dithered_color * levels) / (levels - 1.0); // Normalize back to 0..1
    // Actually standard quantization: floor(x * (L-1) + 0.5) / (L-1) ?
    // With dither added, we just floor.
    // Let's stick to standard dither formula:
    // output = floor(input * (levels-1) + threshold) / (levels-1)

    // Re-calculating with standard formula
    let L = max(2.0, floor(levels));
    let t = bayer; // 0..1
    // Ordered Dither: color + (t - 0.5)/L ?
    // Or: if (color > t) 1 else 0 (for 1 bit)

    // For multi-level:
    // val = color * (L - 1)
    // val += (t - 0.5)
    // val = floor(val + 0.5) / (L - 1)

    var final_dither = original_color;
    final_dither.r = floor(c_color.r * (L - 1.0) + (t - 0.5) + 0.5) / (L - 1.0);
    final_dither.g = floor(c_color.g * (L - 1.0) + (t - 0.5) + 0.5) / (L - 1.0);
    final_dither.b = floor(c_color.b * (L - 1.0) + (t - 0.5) + 0.5) / (L - 1.0);

    // Mix based on Mouse X
    // Actually let's make Mouse X control the "Dither Influence" vs "Just Quantization"
    // Or just mix with original.
    // Let's assume Mouse X controls the "strength" of the effect overall?
    // User requested "Mouse Responsive".
    // Let's make Mouse X control the mix between Original and Dithered.
    // And Mouse Y controls the Pixel Scale.

    let mix_factor = mouse.x; // 0 = Original, 1 = Dithered

    let final_color = mix(original_color, final_dither, mix_factor);

    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(final_color, 1.0));
}
