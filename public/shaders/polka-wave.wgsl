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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    // Normalize coordinates
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let uv_aspect = vec2(uv.x * aspect, uv.y);
    let mouse = u.zoom_config.yz;
    let mouse_aspect = vec2(mouse.x * aspect, mouse.y);
    let time = u.config.x;

    // Params
    // x: Grid Density (10 - 100)
    // y: Wave Amplitude
    // z: Wave Frequency
    // w: Wave Speed

    let density = mix(20.0, 150.0, u.zoom_params.x);
    let amp = u.zoom_params.y;
    let freq = mix(5.0, 50.0, u.zoom_params.z);
    let speed = mix(0.5, 5.0, u.zoom_params.w);

    // Grid logic
    // We want square cells
    let grid_uv = uv * vec2(aspect, 1.0) * density;
    let cell_id = floor(grid_uv);
    let cell_uv = fract(grid_uv) - 0.5; // -0.5 to 0.5 center

    // Center of the cell in UV space (for sampling texture)
    let center_pos = (cell_id + 0.5) / density; // This is in aspect-corrected space
    let sample_uv = vec2(center_pos.x / aspect, center_pos.y);

    // Sample texture brightness
    let texColor = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0);
    let brightness = dot(texColor.rgb, vec3(0.299, 0.587, 0.114));

    // Calculate Wave
    // Distance from mouse to cell center
    let dist = distance(center_pos, mouse_aspect);

    // Wave function: ripples out from mouse
    let wave = sin(dist * freq - time * speed);

    // Modulate dot radius
    // Base radius is determined by brightness (halftone style)
    // Wave adds/subtracts from it

    // Max radius in cell_uv space is 0.5
    var radius = brightness * 0.45;

    if (amp > 0.0) {
        // Add wave effect
        radius += wave * 0.2 * amp;
    }

    // Clamp radius
    radius = clamp(radius, 0.05, 0.5);

    // Draw circle
    let dist_to_center = length(cell_uv);

    // Smooth edges (AA)
    let aa = 0.7 / density; // Roughly 1 pixel width
    let circle = 1.0 - smoothstep(radius - aa, radius + aa, dist_to_center);

    // Color the circle with the texture color, background black
    let finalColor = vec4(texColor.rgb * circle, 1.0);

    // Or maybe white background?
    // Usually halftone is black ink on white paper, or light dots on black.
    // Let's stick to "Light Dots on Black" (emission style) as it fits WebGPU demos better.

    textureStore(writeTexture, global_id.xy, finalColor);
}
