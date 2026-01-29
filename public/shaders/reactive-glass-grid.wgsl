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
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Density, y=Refraction, z=Glow, w=EdgeSmooth
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    // Parameters
    let density = u.zoom_params.x * 50.0 + 5.0; // 5 to 55
    let refr_strength = u.zoom_params.y * 0.1;
    let glow_strength = u.zoom_params.z;
    let edge_smooth = u.zoom_params.w * 0.4 + 0.01;

    // Grid calculations
    let grid_uv = uv * density;
    let cell_id = floor(grid_uv);
    let cell_uv = fract(grid_uv); // 0.0 to 1.0 inside cell

    // Cell center in screen UV space
    let cell_center = (cell_id + 0.5) / density;

    // Distance from mouse to this cell (using aspect corrected distance)
    let dist_vec = (cell_center - mouse) * vec2<f32>(aspect, 1.0);
    let dist_to_mouse = length(dist_vec);

    // Mouse influence falls off with distance
    let influence = smoothstep(0.5, 0.0, dist_to_mouse);

    // Calculate a pseudo-normal for the glass tile (pillow shape)
    // 0.5 at center, -0.5 at left/bottom, 0.5 at right/top
    let local_p = cell_uv - 0.5;

    // Tilt the normal based on mouse position?
    // Let's just do a simple lens refraction per tile + offset by mouse

    // Displace lookup based on local curvature (glass block effect)
    var displacement = local_p * refr_strength * (1.0 + influence * 2.0);

    // Add some chromatic aberration near mouse
    let aberration = influence * refr_strength * 0.5;

    // Sample texture
    let final_uv = uv - displacement;
    let r_uv = final_uv + aberration;
    let b_uv = final_uv - aberration;

    var color = vec4<f32>(
        textureSampleLevel(readTexture, u_sampler, r_uv, 0.0).r,
        textureSampleLevel(readTexture, u_sampler, final_uv, 0.0).g,
        textureSampleLevel(readTexture, u_sampler, b_uv, 0.0).b,
        1.0
    );

    // Tile Edges (Grout/Bevel)
    // Distance from center 0..0.5
    let d_edge = max(abs(local_p.x), abs(local_p.y)); // Chebyshev distance 0..0.5
    // Smoothstep for edge darkening
    let edge_mask = 1.0 - smoothstep(0.5 - edge_smooth, 0.5, d_edge);

    color = color * edge_mask;

    // Add glow/emission based on influence
    // Use a warm color or the pixel color
    let glow_color = vec3<f32>(0.2, 0.6, 1.0) * glow_strength * influence;

    // Add glow to the tile edges specifically?
    let edge_glow = (1.0 - edge_mask) * influence * glow_strength * 2.0;

    color = vec4<f32>(color.rgb + glow_color + edge_glow, 1.0);

    textureStore(writeTexture, global_id.xy, color);

    // Pass depth
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, final_uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
