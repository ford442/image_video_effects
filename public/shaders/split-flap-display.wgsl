// ═══════════════════════════════════════════════════════════════════
//  Split Flap Display
//  Category: simulation
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-25
//  Ideas: lower-leaf lag on the hinge; drum-index pip through the half-turn
//  A packing: raw (angle, velocity, 0, 1); read C at the cell-center pixel
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Audio: bass drives auto-flip bursts, mids widens interaction, treble adds kick
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params
    let rows = 5.0 + u.zoom_params.x * 40.0; // Number of rows
    let interaction_radius = (0.1 + u.zoom_params.y * 0.3) * (1.0 + mids * 0.4);
    let auto_flip_speed = u.zoom_params.z * (1.0 + bass * 1.5);

    // Grid Setup (Square cells)
    let cell_h = 1.0 / rows;
    let cell_w = cell_h / aspect;
    let grid_dims = vec2<f32>(1.0 / cell_w, rows);

    let grid_uv = uv * grid_dims;
    let cell_id = floor(grid_uv);
    let cell_uv_local = fract(grid_uv) - 0.5; // -0.5 to 0.5

    let cell_center_uv = (cell_id + 0.5) / grid_dims;

    // Previous (angle, velocity) lives in C. Read the pixel this cell writes,
    // which is the cell center — not cell_id, which is a different pixel.
    let resI = vec2<i32>(i32(resolution.x), i32(resolution.y));
    let statePx = clamp(vec2<i32>(cell_center_uv * resolution), vec2<i32>(0), resI - vec2<i32>(1));
    let prev_state = textureLoad(dataTextureC, statePx, 0);
    var angle = prev_state.r;
    var velocity = prev_state.g;

    let mouse = u.zoom_config.yz;
    let dist_to_mouse = distance(cell_center_uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));

    if (dist_to_mouse < interaction_radius) {
        velocity = velocity + 0.02 + treble * 0.05;
    }

    let rand = fract(sin(dot(cell_id, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    if (fract(u.config.x * 0.5 + rand) < 0.005 * auto_flip_speed) {
         velocity = velocity + 0.2;
    }

    angle = angle + velocity;
    velocity = velocity * mix(0.8, 0.99, u.zoom_params.w);

    // Magnetic stop at every half-turn.
    let nearest_pi = round(angle / 3.14159) * 3.14159;
    let diff = nearest_pi - angle;
    velocity = velocity + diff * 0.02;

    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(angle, velocity, 0.0, 1.0));

    // ── Idea: split timing — the lower leaf trails the velocity ──
    let lag = clamp(velocity, -1.5, 1.5) * 0.42;
    let visAngle = select(angle, angle - lag, cell_uv_local.y > 0.0);
    let cos_a = cos(visAngle);
    let scale_y = cos_a;
    let texture_local_y = cell_uv_local.y / (scale_y + 0.0001);

    var final_color = vec4<f32>(0.1, 0.1, 0.1, 1.0);

    if (abs(texture_local_y) <= 0.5) {
        let local_uv_unscaled = vec2<f32>(cell_uv_local.x, texture_local_y);
        let sample_pos = clamp((cell_id + 0.5 + local_uv_unscaled) / grid_dims, vec2<f32>(0.0), vec2<f32>(1.0));
        var col = textureSampleLevel(readTexture, u_sampler, sample_pos, 0.0);

        let shade = 0.4 + 0.6 * abs(cos_a);
        col = vec4<f32>(col.rgb * shade, col.a);

        // Back face: inverted and cool, once this half has passed edge-on.
        if (cos_a < 0.0) {
            col = vec4<f32>((1.0 - col.rgb) * vec3<f32>(0.8, 0.9, 1.0), col.a);
        }

        final_color = col;
    }

    // Hinge stays a screen-space line at the cell center.
    if (abs(cell_uv_local.y) < 0.02 * cell_h) {
        final_color = vec4<f32>(0.0, 0.0, 0.0, final_color.a);
    }

    // ── Idea: drum pip — height is progress through the current half-turn ──
    let glyph = fract(angle / 3.14159265);
    let pip = exp(-abs(cell_uv_local.y - (glyph - 0.5)) * 70.0) * step(0.40, cell_uv_local.x);
    final_color = vec4<f32>(mix(final_color.rgb, vec3<f32>(0.95, 0.82, 0.35), pip * 0.9), final_color.a);

    let onTile = step(abs(texture_local_y), 0.5);
    let edgeOn = abs(cos_a);
    final_color.a = mix(0.22, 0.35 + 0.65 * edgeOn, onTile);

    let display = acesToneMap(max(final_color.rgb, vec3<f32>(0.0)));
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(display, final_color.a));

    let srcDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depth = mix(srcDepth, edgeOn, onTile * 0.65);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
