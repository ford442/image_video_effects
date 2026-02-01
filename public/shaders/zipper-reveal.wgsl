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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
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
    let mouse = u.zoom_config.yz;

    // Params
    let spread = u.zoom_params.x;     // Width of the V-shape
    let tooth_size = u.zoom_params.y; // Size of zipper teeth
    let angle = u.zoom_params.z;      // Rotation angle

    // Center logic around mouse
    // Translate UV to be relative to mouse
    let rel_uv = uv - mouse;

    // Rotate UV
    let cos_a = cos(angle);
    let sin_a = sin(angle);
    let rot_uv = vec2<f32>(
        rel_uv.x * cos_a - rel_uv.y * sin_a,
        rel_uv.x * sin_a + rel_uv.y * cos_a
    );

    // Now work in rotated space.
    // x is perpendicular to zipper line, y is along the zipper line.
    // Let's assume the zipper opens "upwards" relative to rotation (negative Y in rotated space).
    // Or let's make it intuitive: Dragging down (increasing Y) unzips it.
    // So if rot_uv.y < 0 (above mouse), it's open.

    var gap = 0.0;

    // The zipper opens as we go further negative in Y (upwards from mouse)
    if (rot_uv.y < 0.0) {
        gap = abs(rot_uv.y) * spread;
    }

    // Sawtooth pattern for teeth
    // Dependent on Y position along the zipper
    let tooth_wave = abs((fract(rot_uv.y / tooth_size) - 0.5) * 2.0);
    // Teeth stick out.
    // The "hole" is gap. The teeth are attached to the edge of the hole.
    // Let's say the mechanical edge is at `gap`.
    // The teeth oscillate around `gap`.

    let tooth_amplitude = tooth_size * 0.5;
    // Interleave teeth: Left side has teeth where Right side has gaps?
    // Normal zipper: teeth interlock.
    // Left side: High when fract < 0.5
    // Right side: High when fract > 0.5

    let y_fract = fract(rot_uv.y / tooth_size);

    // Basic displacement boundary
    var boundary_dist = gap;

    // Add interlocking logic
    // If rot_uv.y > 0.0 (closed part), we still want to show the seam.
    // But for now let's focus on the open part.

    // Distance from center axis
    let dist_x = abs(rot_uv.x);

    // Determine if we are in the "void"
    var is_void = false;
    var is_tooth = false;

    // Tooth visualization logic
    // The actual separation is `gap`.
    // Teeth extend inwards from `gap + tooth_amplitude` to `gap - tooth_amplitude`?
    // No, teeth are solid.

    // Let's define the solid edge at `gap + tooth_offset`.
    // Left Side (x < 0): Tooth present if y_fract < 0.5
    // Right Side (x > 0): Tooth present if y_fract >= 0.5

    var tooth_present = false;
    if (rot_uv.x < 0.0) {
        if (y_fract < 0.5) { tooth_present = true; }
    } else {
        if (y_fract >= 0.5) { tooth_present = true; }
    }

    // Adjust boundary based on tooth
    // If tooth is present, the solid extends closer to center.
    // Solid edge = gap.
    // If tooth present, solid edge = gap - tooth_amplitude.
    // Wait, if gap is 0, teeth interlock.
    // So solid edge is `gap`.
    // If tooth present, we add to the solid -> it reaches x = gap - tooth_size?
    // At y=0 (gap=0): Left tooth reaches x = 0? Right tooth reaches x = 0?
    // Let's say boundary is `gap`.
    // If tooth present, boundary = gap - tooth_amplitude (closer to center).
    // If no tooth, boundary = gap + tooth_amplitude (further from center).

    let shape_boundary = gap + (select(tooth_amplitude, -tooth_amplitude, tooth_present));

    // Visual tweak: enforce a minimum gap so we see black
    let min_gap = 0.0;

    // If we are inside the gap
    if (dist_x < shape_boundary) {
        // Inside void
        is_void = true;
    } else if (dist_x < shape_boundary + tooth_size * 0.2) {
        // Edge highlight (metallic)
        is_tooth = true;
    }

    if (is_void) {
        // Draw dark void or "undershirt"
        // Maybe a subtle grid pattern
        let void_color = vec4<f32>(0.05, 0.05, 0.05, 1.0);
        textureStore(writeTexture, vec2<i32>(global_id.xy), void_color);
    } else {
        // Draw Image
        if (is_tooth) {
             // Metallic look
             textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(0.7, 0.7, 0.8, 1.0));
        } else {
             // Sample texture
             // Displace texture to simulate fabric folding away
             // We want to pull pixels from "under" the zipper area.
             // Effectively, we push the texture coordinates outwards away from the zipper center.

             // The amount of push should be related to 'gap'.
             // We need to sample closer to the center line by 'gap' amount?
             // No, the fabric physically moved OUT. So the pixel at 'uv' (which is far out) should show what was originally at 'uv - gap'.

             let push_dir = sign(rot_uv.x);

             // Calculate displacement vector in rotated space
             let disp_x = -push_dir * gap; // Move sample coordinate TOWARDS center

             // Convert displacement back to global space
             let disp_vec_rot = vec2<f32>(disp_x, 0.0);
             let disp_vec_global = vec2<f32>(
                 disp_vec_rot.x * cos_a + disp_vec_rot.y * sin_a,
                 -disp_vec_rot.x * sin_a + disp_vec_rot.y * cos_a
             );

             let sample_uv = uv + disp_vec_global;

             // Bounds check
             if (sample_uv.x < 0.0 || sample_uv.x > 1.0 || sample_uv.y < 0.0 || sample_uv.y > 1.0) {
                 textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(0.0, 0.0, 0.0, 1.0));
             } else {
                 let color = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0);
                 textureStore(writeTexture, vec2<i32>(global_id.xy), color);
             }
        }
    }
}
