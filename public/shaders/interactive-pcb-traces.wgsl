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
  config: vec4<f32>,       // x=Time, y=MouseClickCount
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY
  zoom_params: vec4<f32>,  // x=GridScale, y=PulseSpeed, z=TraceGlow, w=BackgroundDim
  ripples: array<vec4<f32>, 50>,
};

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Parameters
    let grid_scale = mix(10.0, 50.0, u.zoom_params.x);
    let pulse_speed = mix(2.0, 10.0, u.zoom_params.y);
    let trace_glow = mix(0.5, 3.0, u.zoom_params.z);
    let bg_dim = mix(0.1, 0.8, u.zoom_params.w);

    let aspect = resolution.x / resolution.y;
    let uv_scaled = vec2<f32>(uv.x * aspect, uv.y) * grid_scale;
    let id = floor(uv_scaled);
    let f = fract(uv_scaled);

    // Voronoi (Manhattan Distance)
    var m_dist = 10.0;
    var cell_id = vec2<f32>(0.0);
    var cell_center_local = vec2<f32>(0.0);

    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            // Random offset within the cell (keep it somewhat centered for pads)
            let point_offset = hash22(id + neighbor) * 0.6 + 0.2;
            let point_pos = neighbor + point_offset;

            // Manhattan Distance: |dx| + |dy|
            let dist = abs(point_pos.x - f.x) + abs(point_pos.y - f.y);

            if (dist < m_dist) {
                m_dist = dist;
                cell_center_local = point_pos;
                cell_id = id + neighbor;
            }
        }
    }

    // Determine "Trace" vs "Pad"
    // Pads are near the center (low m_dist)
    // Traces are the boundaries.
    // We can approximate boundaries by high m_dist or by comparing to second closest (expensive).
    // Let's create a visual style where the cell is filled with circuitry pattern based on m_dist.

    // Circuit Pattern: Stepped rings
    let rings = sin(m_dist * 20.0);
    let is_trace = smoothstep(0.9, 1.0, rings);

    // Pad at center
    let is_pad = 1.0 - smoothstep(0.0, 0.2, m_dist);

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
    let mouse_uv_scaled = vec2<f32>(mouse.x * aspect, mouse.y) * grid_scale;

    // Distance from mouse to this CELL's center (in grid space)
    let cell_world_pos = cell_id + vec2<f32>(0.5); // approximate
    let dist_to_mouse = length(cell_world_pos - mouse_uv_scaled);

    // Pulse Wave
    let wave_front = dist_to_mouse - time * pulse_speed;
    // Repeating pulse every X units of distance
    // Or simpler:
    let pulse_signal = smoothstep(0.8, 1.0, sin(dist_to_mouse * 0.5 - time * pulse_speed));

    // Colors
    // Sample original image
    let img_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let luma = dot(img_color, vec3<f32>(0.333));

    // PCB Colors
    let pcb_green = vec3<f32>(0.0, 0.2, 0.1);
    let trace_gold = vec3<f32>(0.8, 0.6, 0.2);
    let signal_cyan = vec3<f32>(0.0, 1.0, 0.8);

    // Background is dimmed image tinted green
    var final_color = mix(img_color * bg_dim, pcb_green * luma, 0.5);

    // Add Traces (Gold)
    // Modulate trace intensity by image brightness (traces run through bright areas?)
    // Or just overlay.
    let trace_mask = is_trace * (0.2 + 0.8 * hash12(cell_id)); // vary per cell
    final_color = mix(final_color, trace_gold * trace_glow, trace_mask * 0.5);

    // Add Pads (Gold)
    final_color = mix(final_color, trace_gold * 2.0, is_pad);

    // Add Signal Pulse (Cyan)
    // Pulse travels through traces and pads
    let active_signal = pulse_signal * trace_glow;

    // Pulse lights up the traces and pads significantly
    let signal_color = signal_cyan * active_signal;

    // Composite signal
    // Use screen blend or additive
    final_color += signal_color * (trace_mask + is_pad);

    // Mouse Highlight (near cursor)
    let mouse_hover = smoothstep(5.0, 0.0, dist_to_mouse);
    final_color += vec3<f32>(0.2, 0.5, 0.2) * mouse_hover;

    textureStore(writeTexture, global_id.xy, vec4<f32>(final_color, 1.0));

    // Passthrough depth
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
