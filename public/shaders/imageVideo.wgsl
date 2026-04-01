struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@group(0) @binding(0) var mySampler: sampler;
@group(0) @binding(1) var myTexture: texture_2d<f32>;
@group(0) @binding(2) var<uniform> uniforms: Uniforms;
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

struct VertexOutput {
    @builtin(position) Position: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@vertex
fn vs_main(@builtin(vertex_index) VertexIndex: u32) -> VertexOutput {
    var pos = array<vec2<f32>, 4>(
        vec2<f32>(-1.0, -1.0),
        vec2<f32>( 1.0, -1.0),
        vec2<f32>(-1.0,  1.0),
        vec2<f32>( 1.0,  1.0)
    );

    var output: VertexOutput;
    output.Position = vec4<f32>(pos[VertexIndex], 0.0, 1.0);

    // Standard 0-1 UVs
    let baseUV = vec2<f32>(
        f32(VertexIndex % 2u),
        1.0 - f32(VertexIndex / 2u)
    );

    // --- ASPECT RATIO CORRECTION (COVER MODE) ---
    // Calculates scale factors to ensure the image covers the entire screen
    // without stretching, cropping the excess.
    let screenAspect = uniforms.canvasWidth / uniforms.canvasHeight;
    let texW = max(uniforms.textureWidth, 1.0);
    let texH = max(uniforms.textureHeight, 1.0);
    let imageAspect = texW / texH;

    var uv = baseUV;

    if (screenAspect > imageAspect) {
        // Screen is wider than image: Fit Width (1.0), crop Height
        // The image is "zoomed in" vertically to fill the width
        let scaleHeight = imageAspect / screenAspect;
        uv.y = (uv.y - 0.5) * scaleHeight + 0.5;
    } else {
        // Screen is taller than image: Fit Height (1.0), crop Width
        // The image is "zoomed in" horizontally to fill the height
        let scaleWidth = screenAspect / imageAspect;
        uv.x = (uv.x - 0.5) * scaleWidth + 0.5;
    }

    output.uv = uv;
    return output;
}

@fragment
fn fs_main(@location(0) uv: vec2<f32>) -> @location(0) vec4<f32> {
    return textureSample(myTexture, mySampler, uv);
}
