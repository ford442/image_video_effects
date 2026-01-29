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

// Pixel Stretch Cross
// Param 1: Stretch Width
// Param 2: Decay
// Param 3: Mix Strength
// Param 4: Opacity

fn get_mouse() -> vec2<f32> {
    var mouse = u.zoom_config.yz;
    if (mouse.x < 0.0) { return vec2<f32>(0.5, 0.5); }
    return mouse;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = get_mouse();

    let stretch_width = u.zoom_params.x;
    let decay = u.zoom_params.y * 10.0;
    let mix_strength = u.zoom_params.z;
    let opacity = u.zoom_params.w;

    var finalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Stretch Horizontal (sample from mouse.x)
    let dist_x = abs(uv.x - mouse.x);
    if (abs(uv.y - mouse.y) < stretch_width) {
        // We are in the horizontal bar
        // We want to smear the pixel at mouse.x outwards
        let smear_uv = vec2<f32>(mouse.x, uv.y);
        let smear_col = textureSampleLevel(readTexture, u_sampler, smear_uv, 0.0);

        // Distance from center of cross
        let d = abs(uv.x - mouse.x);
        let factor = exp(-d * decay);

        finalColor = mix(finalColor, smear_col, factor * mix_strength);
    }

    // Stretch Vertical (sample from mouse.y)
    let dist_y = abs(uv.y - mouse.y);
    if (abs(uv.x - mouse.x) < stretch_width) {
        // We are in the vertical bar
        let smear_uv = vec2<f32>(uv.x, mouse.y);
        let smear_col = textureSampleLevel(readTexture, u_sampler, smear_uv, 0.0);

        let d = abs(uv.y - mouse.y);
        let factor = exp(-d * decay);

        // Additive or Max? Let's use mix.
        // If we are near center, we might have already mixed horizontal.
        // Let's take the max of the factors?
        finalColor = mix(finalColor, smear_col, factor * mix_strength);
    }

    // Global Opacity
    finalColor = mix(textureSampleLevel(readTexture, u_sampler, uv, 0.0), finalColor, opacity);

    textureStore(writeTexture, global_id.xy, finalColor);
}
