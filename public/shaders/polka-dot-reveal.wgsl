// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4 (Use these for ANY float sliders)
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz;

    // Calculate distance influence
    let aspect = resolution.x / resolution.y;
    let dist = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(mouse.x * aspect, mouse.y));

    // Map distance to grid density
    // Close = high density (small dots, e.g. 200)
    // Far = low density (big dots, e.g. 20)
    let density = mix(200.0, 20.0, smoothstep(0.0, 0.8, dist));

    let grid_uv = floor(uv * density) / density;
    let cell_center = grid_uv + (0.5 / density);

    // Sample color at cell center
    let color = textureSampleLevel(readTexture, u_sampler, cell_center, 0.0);
    let lum = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Determine dot radius based on luminance
    // Max radius is half cell width (0.5 in local coords)
    let max_radius = 0.5;
    let radius = lum * max_radius; // Darker = smaller dots? Or Brighter = bigger dots? Standard halftone is bigger = darker (ink).
    // Let's do: Brighter = bigger dots (additive light model)

    // Local UV in cell [0, 1]
    let local_uv = fract(uv * density);
    let dist_to_center = distance(local_uv, vec2<f32>(0.5));

    var final_color = vec4<f32>(0.0); // Black background

    // Smooth circle
    let aa = 0.1 * density / 50.0; // Anti-aliasing width adjusted by density
    let circle = 1.0 - smoothstep(radius - aa, radius + aa, dist_to_center);

    final_color = mix(vec4<f32>(0.0, 0.0, 0.0, 1.0), color, circle);

    textureStore(writeTexture, vec2<i32>(global_id.xy), final_color);

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
