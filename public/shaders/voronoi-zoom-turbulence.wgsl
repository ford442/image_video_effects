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
  zoom_params: vec4<f32>,  // x=Density, y=Speed, z=MaxZoom, w=MouseRadius
  ripples: array<vec4<f32>, 50>,
};

// Voronoi Zoom Turbulence
// Partitions the screen into Voronoi cells.
// Each cell acts as a lens with a dynamic zoom level.
// Zoom modulates with time and mouse proximity.

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;

    // Parameters
    let density = u.zoom_params.x * 30.0 + 3.0;
    let speed = u.zoom_params.y * 2.0;
    let zoomMax = u.zoom_params.z * 5.0 + 1.0;
    let mouseRadius = u.zoom_params.w * 0.5 + 0.1;

    // Voronoi Grid Calculation
    // Use aspect corrected coordinates for square cells
    let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
    let uv_grid = uv_corrected * density;
    let i_st = floor(uv_grid);
    let f_st = fract(uv_grid);

    var m_dist = 10.0;
    var cell_id = vec2<f32>(0.0);
    var cell_point_local = vec2<f32>(0.0); // Point relative to grid cell (0-1)

    // Find closest seed point
    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let point = hash22(i_st + neighbor);

            // Jitter/Animate center?
            // Keeping them static makes the lenses stable, which is better for this effect.
            // point = 0.5 + 0.5 * sin(time + 6.2831 * point);

            let diff = neighbor + point - f_st;
            let dist = length(diff);

            if (dist < m_dist) {
                m_dist = dist;
                cell_id = i_st + neighbor;
                cell_point_local = point;
            }
        }
    }

    // Determine center of the closest Voronoi cell in UV space
    // Grid coordinate of point = cell_id + cell_point_local
    let grid_pos_corrected = cell_id + cell_point_local;
    let uv_center_corrected = grid_pos_corrected / density;
    let uv_center = vec2<f32>(uv_center_corrected.x / aspect, uv_center_corrected.y);

    // Calculate Dynamic Zoom
    let cell_rnd = hash22(cell_id).x; // Random float 0-1 per cell

    // Oscillation
    let osc = sin(time * speed + cell_rnd * 20.0) * 0.5 + 0.5;

    // Mouse Influence
    let dist_to_mouse = distance(uv_center, mouse);
    // Influence is 1.0 when close, 0.0 when far
    let influence = 1.0 - smoothstep(0.0, mouseRadius, dist_to_mouse);

    // Zoom Logic:
    // Base low zoom + High turbulence near mouse
    // Or Global turbulence + Extra near mouse
    let finalZoom = 1.0 + (zoomMax - 1.0) * osc * (0.2 + 0.8 * influence);

    // Map UVs relative to cell center
    let vec_to_pixel = uv - uv_center;
    let new_vec = vec_to_pixel / finalZoom;
    let final_uv = uv_center + new_vec;

    // Border Effect (optional)
    // Darken edges based on distance from cell center (m_dist)
    // m_dist is in grid space. Max distance is approx 0.707 (corner) to 1.0.
    // Let's fade edges slightly.
    let edge = smoothstep(0.0, 0.05, 0.6 - m_dist); // Soft edge mask

    var color = textureSampleLevel(readTexture, u_sampler, final_uv, 0.0);

    // Apply vignette to cell
    // color.rgb *= smoothstep(0.7, 0.3, m_dist);

    textureStore(writeTexture, global_id.xy, color);

    // Depth Pass
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, final_uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
