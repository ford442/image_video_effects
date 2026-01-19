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

    // Normalize UV
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Parameters
    // x: Grid Density (10 to 80)
    // y: Influence Radius (0.1 to 1.5)
    // z: Max Rotation (PI to 4PI)
    // w: Gap Size (0.0 to 0.4)

    let density = u.zoom_params.x * 70.0 + 10.0;
    let radius = u.zoom_params.y * 1.4 + 0.1;
    let max_rot = u.zoom_params.z * 12.56; // up to 4PI
    let gap = u.zoom_params.w * 0.4;

    let mouse = u.zoom_config.yz;

    // Grid Calculations
    // Scale X by aspect to make square cells
    let grid_uv = vec2<f32>(uv.x * aspect, uv.y) * density;
    let cell_id = floor(grid_uv);
    let cell_local = fract(grid_uv); // 0.0 to 1.0

    // Cell Center in Global UV (aspect corrected)
    let cell_center_aspect = (cell_id + 0.5) / density;
    // Map back to true UV for distance check
    let cell_center = vec2<f32>(cell_center_aspect.x / aspect, cell_center_aspect.y);

    // Distance to mouse (corrected for aspect)
    let dist_vec = (cell_center - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dist_vec);

    // Calculate rotation angle
    var angle: f32 = 0.0;
    if (dist < radius) {
        let falloff = smoothstep(radius, 0.0, dist);
        // Add a bit of wave based on distance for ripple effect
        let wave = sin(dist * 10.0 - u.config.x * 2.0) * 0.5 + 0.5;
        angle = falloff * max_rot;

        // Add time-based idling
        angle = angle + (sin(u.config.x + cell_id.x * 0.1 + cell_id.y * 0.1) * 0.2 * falloff);
    }

    // 3D Flip Simulation (Vertical Flip around X axis)
    // We modify the Y coordinate of the texture lookup.
    // As the tile rotates, the projected height decreases -> cos(angle)
    // We map the 0..1 local coordinate to a larger range and check bounds

    let cos_a = cos(angle);
    let sin_a = sin(angle); // unused for simple projection but useful for shading

    // Perspective projection simulation
    // "Compressed" Y coordinate
    // If cos_a is 1, scale is 1. If cos_a is 0, scale is 0 (invisible).
    // To find the source pixel that projects to the current pixel:
    // current_y = (source_y - 0.5) * cos_a + 0.5
    // So: source_y = (current_y - 0.5) / cos_a + 0.5

    // Avoid division by zero
    let scale_y = max(abs(cos_a), 0.001);

    let source_local_y = (cell_local.y - 0.5) / scale_y + 0.5;

    var final_color = vec4<f32>(0.0, 0.0, 0.0, 1.0);

    // Check if the source pixel is within the tile bounds
    // Apply gap
    let bounds_min = gap;
    let bounds_max = 1.0 - gap;

    if (source_local_y >= bounds_min && source_local_y <= bounds_max &&
        cell_local.x >= bounds_min && cell_local.x <= bounds_max) {

        // Calculate Global Sample UV
        // We know the cell_id.
        // We need to map (cell_local.x, source_local_y) back to global UV.

        // Aspect un-correction for X
        let sample_u = (cell_id.x + cell_local.x) / density / aspect;
        let sample_v = (cell_id.y + source_local_y) / density;

        final_color = textureSampleLevel(readTexture, u_sampler, vec2<f32>(sample_u, sample_v), 0.0);

        // Shading / Backface
        // If cos_a < 0, we are seeing the back.
        // Let's darken it significantly or invert color
        if (cos_a < 0.0) {
            // Back face
            final_color = vec4<f32>(final_color.rgb * 0.2, 1.0); // Dark back
            // Maybe add a color tint?
            final_color = vec4<f32>(final_color.r + 0.1, final_color.g, final_color.b, 1.0);
        } else {
            // Front face shading based on angle
            // Make it shine when flat (cos_a ~ 1) or when catching light?
            // Simple diffuse: dot product with light.
            // Let's just darken slightly as it rotates away
            final_color = vec4<f32>(final_color.rgb * scale_y, 1.0);
        }

    } else {
        // Background / Gap
        // Make it transparent or black
        final_color = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }

    textureStore(writeTexture, global_id.xy, final_color);

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
