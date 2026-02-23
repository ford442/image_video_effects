@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var filteringSampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 32>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    let coords = vec2<i32>(global_id.xy);

    if (coords.x >= i32(dimensions.x) || coords.y >= i32(dimensions.y)) {
        return;
    }

    let uv = vec2<f32>(coords) / vec2<f32>(dimensions);
    let aspect = u.config.z / u.config.w;

    // Parameters
    let grid_density = u.zoom_params.x; // 20.0 to 100.0
    let touch_radius = u.zoom_params.y; // 0.1 to 0.8
    let rotation_strength = u.zoom_params.z; // 0.0 to 2.0
    let cell_gap = u.zoom_params.w; // 0.0 to 0.4

    // Grid calculations
    let grid_uv = floor(uv * grid_density) / grid_density;
    let cell_center = grid_uv + (0.5 / grid_density);

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
    let dist_vec = (cell_center - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dist_vec);

    let influence = smoothstep(touch_radius, 0.0, dist);

    // Rotation logic
    let angle = influence * rotation_strength * 3.14159;
    let c = cos(angle);
    let s = sin(angle);

    // Local UVs
    let local_uv = fract(uv * grid_density);
    let centered = local_uv - 0.5;

    // Rotate centered UVs
    let rotated = vec2<f32>(
        centered.x * c - centered.y * s,
        centered.x * s + centered.y * c
    );

    // Determine cell color from center
    let cell_color = textureSampleLevel(readTexture, u_sampler, cell_center, 0.0);

    // Basic 3D effect (bevel) or gap
    let scale = 0.5 - (cell_gap * 0.5);
    // Add "pop" effect on hover
    let pop = influence * 0.2;
    let current_scale = scale + pop;

    // Box SDF
    let box_dist = max(abs(rotated.x), abs(rotated.y)) - current_scale;

    var final_color = vec4<f32>(0.0, 0.0, 0.0, 1.0);

    if (box_dist < 0.0) {
        final_color = cell_color;

        // Add shading based on rotated coordinates to simulate 3D face
        // Top-Left light
        let light = (rotated.x - rotated.y) * 0.5 + 0.5; // 0..1 gradient
        final_color = vec4<f32>(final_color.rgb * (0.8 + 0.4 * light), 1.0);
    }

    textureStore(writeTexture, coords, final_color);
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, filteringSampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
