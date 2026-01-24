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

// ASCII Lens
// Param 1: Lens Radius (0.0 to 1.0)
// Param 2: Grid Density (High values = smaller chars)

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    var mouse = u.zoom_config.yz;
    if (mouse.x < 0.0) { mouse = vec2<f32>(0.5, 0.5); }

    let lensRadius = u.zoom_params.x; // Default 0.3
    let density = 50.0 + u.zoom_params.y * 150.0; // 50 to 200 grid cells vertical

    // Calculate distance to mouse for lens effect
    let dist = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(mouse.x * aspect, mouse.y));

    if (dist < lensRadius) {
        // Inside Lens: ASCII Effect

        // Define grid
        let grid = vec2<f32>(density * aspect, density); // Adjust X for aspect to make square cells
        let cellUV = floor(uv * grid) / grid;
        let localUV = fract(uv * grid);

        // Sample color at cell center (pixelated look)
        // Add half pixel offset to sample center of block
        let sampleUV = cellUV + (vec2<f32>(0.5) / grid);
        let col = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
        let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));

        var charVal = 0.0;
        let center = vec2<f32>(0.5, 0.5);
        let distCenter = length(localUV - center);

        // Line width proportional to density? Constant is better for pixel crispness.
        // In UV space (0-1), 1 pixel width is roughly 1.0 / (res.y / density * 8.0).
        // Let's use a fixed relative width.
        let width = 0.1;

        // Procedural Glyphs
        // Sorted by brightness
        if (luma > 0.8) {
            // # Block / Full
            charVal = 1.0;
        } else if (luma > 0.6) {
            // @ Square Frame + Dot
            if (abs(localUV.x - 0.5) > 0.2 || abs(localUV.y - 0.5) > 0.2) { charVal = 1.0; }
            if (distCenter < 0.1) { charVal = 1.0; }
        } else if (luma > 0.4) {
            // + Plus
            if (abs(localUV.x - 0.5) < width || abs(localUV.y - 0.5) < width) { charVal = 1.0; }
        } else if (luma > 0.25) {
            // - Minus
             if (abs(localUV.y - 0.5) < width) { charVal = 1.0; }
        } else if (luma > 0.1) {
            // . Dot
            if (distCenter < 0.15) { charVal = 1.0; }
        }

        let finalColor = col * charVal;

        textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

    } else {
        // Outside Lens: Normal
        let col = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
        textureStore(writeTexture, global_id.xy, col);
    }
}
