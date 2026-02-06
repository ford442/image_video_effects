// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Angle, Velocity
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Params
    let rows = 5.0 + u.zoom_params.x * 40.0; // Number of rows
    let interaction_radius = 0.1 + u.zoom_params.y * 0.3;
    let auto_flip_speed = u.zoom_params.z;

    // Grid Setup (Square cells)
    let cell_h = 1.0 / rows;
    let cell_w = cell_h / aspect;
    let grid_dims = vec2<f32>(1.0 / cell_w, rows);

    let grid_uv = uv * grid_dims;
    let cell_id = floor(grid_uv);
    let cell_uv_local = fract(grid_uv) - 0.5; // -0.5 to 0.5

    // Determine cell center for state sampling
    let cell_center_uv = (cell_id + 0.5) / grid_dims;

    // Read previous state (Angle, Velocity)
    // We sample from dataTextureA which stores the previous frame's state
    let prev_state = textureSampleLevel(dataTextureA, u_sampler, cell_center_uv, 0.0);
    var angle = prev_state.r;
    var velocity = prev_state.g;

    // Physics / Interaction
    let mouse = u.zoom_config.yz;
    let dist_to_mouse = distance(cell_center_uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));

    // Mouse Interaction: Push
    if (dist_to_mouse < interaction_radius) {
        // Add velocity based on mouse movement or just proximity
        // Let's just spin them if mouse is near
        velocity = velocity + 0.02;
    }

    // Auto flip (idle animation)
    // Random flip based on time and cell ID
    let rand = fract(sin(dot(cell_id, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    if (fract(u.config.x * 0.5 + rand) < 0.005 * auto_flip_speed) {
         velocity = velocity + 0.2;
    }

    // Apply Velocity
    angle = angle + velocity;

    // Damping / Friction
    velocity = velocity * 0.92;

    // Snap to grid (optional, simulates mechanical stops)?
    // Mechanical split flaps usually stop at discrete characters.
    // Let's add a "magnetic" stop at every PI (180 degrees)
    let nearest_pi = round(angle / 3.14159) * 3.14159;
    let diff = nearest_pi - angle;
    velocity = velocity + diff * 0.02; // Spring force to nearest flip state

    // Store new state
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(0.0, 0.0, 0.0, 0.0)); // Clear main texture first? No, we overwrite.

    // We need to write the state to dataTextureA for the NEXT frame.
    // BUT the standard pipeline might swap A and B?
    // In this codebase, usually dataTextureA is used for persistence.
    // We write to dataTextureA at the current pixel.
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(angle, velocity, 0.0, 1.0));

    // Rendering Logic
    // We are at pixel `uv`. We belong to `cell_id`.
    // The tile for this cell is rotated by `angle`.

    let cos_a = cos(angle);

    // Simple 2.5D projection: Scale Y based on cosine of angle.
    // If cos_a is 0, the tile is invisible (edge on).

    let scale_y = cos_a;

    // To find which part of the texture to show, we invert the scaling.
    // current_pixel_y_offset = texture_y_offset * scale_y
    // texture_y_offset = current_pixel_y_offset / scale_y

    let texture_local_y = cell_uv_local.y / (scale_y + 0.0001); // Avoid div by zero

    var final_color = vec4<f32>(0.1, 0.1, 0.1, 1.0); // Background color (gap)

    if (abs(texture_local_y) <= 0.5) {
        // We hit the tile surface

        // Calculate the UV to sample from the source image
        // We want the image to look mapped onto the grid.
        // So we reconstruct the global UV but using the 'unscaled' local Y.

        let local_uv_unscaled = vec2<f32>(cell_uv_local.x, texture_local_y);
        let sample_pos = (cell_id + 0.5 + local_uv_unscaled) / grid_dims;

        var col = textureSampleLevel(readTexture, u_sampler, sample_pos, 0.0);

        // Shading: Darken as it tilts away
        let shade = 0.4 + 0.6 * abs(cos_a);
        col = vec4<f32>(col.rgb * shade, 1.0);

        // Backface: If cos_a < 0, we are looking at the back.
        // Let's make the back inverted colors or just tinted red/darker.
        if (cos_a < 0.0) {
            col = vec4<f32>(1.0 - col.rgb, 1.0); // Invert
            col = vec4<f32>(col.rgb * vec3<f32>(0.8, 0.9, 1.0), 1.0); // Blue tint
        }

        final_color = col;
    }

    // Draw split line (hinge)
    if (abs(cell_uv_local.y) < 0.02 * cell_h) {
         // This logic is flawed because cell_uv_local is distorted by projection?
         // No, cell_uv_local is the SCREEN space coordinate relative to cell center.
         // The hinge is always at the center of the screen cell area?
         // Actually the hinge is the axis of rotation.
         // If we are simulating a rotating card, the axis is at y=0 (center).
         // So yes, a line at y=0 is the axis.
         if (abs(cell_uv_local.y) < 0.02) {
             final_color = vec4<f32>(0.0, 0.0, 0.0, 1.0);
         }
    }

    textureStore(writeTexture, vec2<i32>(global_id.xy), final_color);

    // Write depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
