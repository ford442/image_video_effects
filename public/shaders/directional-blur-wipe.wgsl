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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
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
    let aspect = resolution.x / resolution.y;

    // Params
    let split_pos_param = u.zoom_params.x;
    let angle_param = u.zoom_params.y;
    let strength_param = u.zoom_params.z;
    let samples_param = u.zoom_params.w; // 0..1 -> 1..50 samples

    // Mouse overrides split pos if clicking/active?
    // Let's make the split line pass through the mouse if mouse is active (not 0,0)
    // Actually, let's use the params as offsets/modifiers to mouse control or standalone.
    // Standard behavior: Mouse defines the "wipe" position.

    // Line definition: dot(uv - origin, normal) > 0
    let origin = mouse; // Use mouse as origin of split
    // Or interpolate between param and mouse?
    // Let's use mouse X as split pos, Mouse Y as angle?

    // Combining params and mouse:
    // Split Pos: Base + Mouse X
    // Angle: Base + Mouse Y

    let angle = angle_param * 6.28 + (mouse.y - 0.5) * 3.14;
    let dir = vec2<f32>(cos(angle), sin(angle));
    let normal = vec2<f32>(-dir.y, dir.x);

    // Split position relative to center, shifted by mouse X
    // Let's define the line by a point P and normal N.
    // P = mouse
    let p_line = mouse;

    // Signed distance to line
    // Adjust UV for aspect ratio?
    let uv_aspect = vec2<f32>(uv.x * aspect, uv.y);
    let p_line_aspect = vec2<f32>(p_line.x * aspect, p_line.y);

    let dist = dot(uv_aspect - p_line_aspect, normal);

    var color = vec4<f32>(0.0);

    if (dist < 0.0) {
        // Clear side
        color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    } else {
        // Blur side
        let num_samples = i32(samples_param * 50.0) + 5;
        let strength = strength_param * 0.05;

        var accum = vec4<f32>(0.0);
        var weight = 0.0;

        for (var i = 0; i < num_samples; i++) {
            let t = f32(i) / f32(num_samples - 1);
            let offset = dir * t * strength;
            // Randomize offset slightly for noise?

            let sample_pos = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
            accum += textureSampleLevel(readTexture, u_sampler, sample_pos, 0.0);
            weight += 1.0;
        }
        color = accum / weight;

        // Add a line highlight
        let line_width = 0.005;
        if (dist < line_width) {
             color += vec4<f32>(0.2); // Highlight
        }
    }

    textureStore(writeTexture, global_id.xy, color);

    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
