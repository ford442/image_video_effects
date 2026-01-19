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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=Width, w=Height
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // Params
  ripples: array<vec4<f32>, 50>,
};

// Pixelate Blast
// Pixelates the image, with pixel size increasing based on distance from mouse (or proximity).

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz;

    // Params
    let minPixelSize = 1.0;
    let maxPixelSize = 50.0 + u.zoom_params.x * 100.0;
    let radius = 0.5 + u.zoom_params.y * 0.5;
    let invert = u.zoom_params.z; // If > 0.5, clear in center, pixelated outside. Else opposite.
    let colorCrunch = u.zoom_params.w; // Reduce color palette

    let aspect = resolution.x / resolution.y;
    var dist = 0.0;

    if (mouse.x >= 0.0) {
        let dVec = uv - mouse;
        dist = length(vec2<f32>(dVec.x * aspect, dVec.y));
    } else {
        dist = length(uv - vec2<f32>(0.5)); // Default center
    }

    // Determine pixel size at this location
    // smoothstep(0, radius, dist) -> 0 at center, 1 at radius
    var t = smoothstep(0.0, radius, dist);

    if (invert > 0.5) {
        // Clear in center (low pixel size), blocky outside
        // default behavior
    } else {
        // Blocky in center, clear outside
        t = 1.0 - t;
    }

    let pixelSize = mix(minPixelSize, maxPixelSize, t);

    // Calculate new UVs
    // To pixelate: floor(uv * resolution / pixelSize) * pixelSize / resolution
    // Note: pixelSize is in screen pixels approx

    let blocks = resolution / pixelSize;
    let blockUV = floor(uv * blocks) / blocks;
    // Center the sample in the block
    let centerUV = blockUV + (0.5 / blocks);

    var color = textureSampleLevel(readTexture, u_sampler, centerUV, 0.0);

    // Optional Color Crunch / Posterization
    if (colorCrunch > 0.1) {
        let steps = 4.0 + (1.0 - colorCrunch) * 20.0;
        color = floor(color * steps) / steps;
    }

    textureStore(writeTexture, global_id.xy, color);
}
