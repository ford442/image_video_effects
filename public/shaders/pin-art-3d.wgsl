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

fn luminance(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mouse = u.zoom_config.yz;

    // Parameters
    // density: Grid density (10 to 100)
    // pin_radius_factor: Size of pin relative to cell (0.1 to 0.95)
    // push_strength: How much mouse pushes down
    // metallic: Specular intensity

    let density = u.zoom_params.x * 90.0 + 10.0;
    let pin_radius_factor = u.zoom_params.y * 0.5 + 0.4; // 0.4 to 0.9
    let push_strength = u.zoom_params.z;
    let metallic = u.zoom_params.w;

    // Grid Setup (Square Cells)
    let grid_uv = vec2<f32>(uv.x * aspect, uv.y) * density;
    let cell_id = floor(grid_uv);
    let cell_local = fract(grid_uv) - 0.5; // -0.5 to 0.5 center

    // Sample Image Color at Cell Center
    let cell_center_uv_x = (cell_id.x + 0.5) / density / aspect;
    let cell_center_uv_y = (cell_id.y + 0.5) / density;
    let sample_uv = vec2<f32>(cell_center_uv_x, cell_center_uv_y);

    var color = vec4<f32>(0.0);
    if (sample_uv.x >= 0.0 && sample_uv.x <= 1.0 && sample_uv.y >= 0.0 && sample_uv.y <= 1.0) {
        color = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0);
    }

    let luma = luminance(color.rgb);

    // Calculate Pin Height
    // Base height is luma.
    // Mouse Interaction: Push down
    // Mouse distance in aspect-corrected space
    let mouse_aspect = vec2<f32>(mouse.x * aspect, mouse.y);
    let cell_center_aspect = vec2<f32>((cell_id.x + 0.5) / density, (cell_id.y + 0.5) / density);
    // Correct mouse Y coordinate? u.zoom_config.yz are 0..1.
    // Yes, multiply by density? No, we need consistent units.
    // Let's map everything to "grid units" or "screen aspect units".
    // cell_center_aspect is correct (0..aspect, 0..1).
    // mouse_aspect is correct.

    let dist_to_mouse = distance(mouse_aspect, cell_center_aspect);
    // Radius of influence: roughly 10% of screen width
    let influence_radius = 0.15;
    let push = smoothstep(influence_radius, 0.0, dist_to_mouse) * push_strength;

    let height = clamp(luma - push, 0.0, 1.0);

    // Rendering
    // We are rendering the pixel at 'uv' (global_id).
    // It belongs to 'cell_id'.
    // Is this pixel part of the pin head?
    // Pin head is a circle at center of cell.

    let dist_from_center = length(cell_local);
    let pin_radius = 0.5 * pin_radius_factor;

    // Anti-aliasing
    let aa = 0.02 * density; // scaling AA with density

    // Shadow
    // Shadow is offset by height.
    // Direction of light: Top-Left (-1, -1)
    let shadow_offset_dir = vec2<f32>(0.2, 0.2); // Shadow falls down-right
    let max_shadow_dist = 0.3; // max offset in cell units
    let shadow_pos = cell_local - shadow_offset_dir * height * max_shadow_dist;
    let dist_shadow = length(shadow_pos);

    let shadow_mask = 1.0 - smoothstep(pin_radius - aa, pin_radius + aa, dist_shadow);

    // Pin Head
    let pin_mask = 1.0 - smoothstep(pin_radius - aa, pin_radius + aa, dist_from_center);

    // Lighting for Pin Head
    // Normal estimation for a sphere cap
    // z = sqrt(r^2 - x^2 - y^2)
    // We normalize coords to -1..1 relative to radius for normal calc
    let normal_xy = cell_local / pin_radius;
    var normal_z = 0.0;
    if (length(normal_xy) < 1.0) {
        normal_z = sqrt(1.0 - dot(normal_xy, normal_xy));
    }
    let normal = normalize(vec3<f32>(normal_xy, normal_z));

    let light_dir = normalize(vec3<f32>(-0.5, -0.5, 1.0)); // Light from top-left-front
    let diffuse = max(dot(normal, light_dir), 0.0);

    // Specular
    let view_dir = vec3<f32>(0.0, 0.0, 1.0);
    let reflect_dir = reflect(-light_dir, normal);
    let spec = pow(max(dot(view_dir, reflect_dir), 0.0), 16.0) * metallic;

    // Composite
    // Background is black (void)
    var final_color = vec3<f32>(0.05, 0.05, 0.05); // Dark backboard

    // Apply Shadow (multiply)
    // Shadow alpha depends on height (higher pins cast stronger/sharper shadows? or just opaque)
    // Let's make shadow semi-transparent black
    let shadow_alpha = 0.6 * shadow_mask;
    final_color = mix(final_color, vec3<f32>(0.0), shadow_alpha);

    // Apply Pin Head
    // Pin color is the image color modulated by light
    // Add some metallic tint (white specular)
    let shaded_pin = color.rgb * (0.3 + 0.7 * diffuse) + vec3<f32>(spec);

    final_color = mix(final_color, shaded_pin, pin_mask);

    textureStore(writeTexture, global_id.xy, vec4<f32>(final_color, 1.0));

    // Depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
