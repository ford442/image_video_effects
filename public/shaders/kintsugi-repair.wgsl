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
  zoom_params: vec4<f32>,  // x=Scale, y=CrackWidth, z=Displacement, w=Shininess
  ripples: array<vec4<f32>, 50>,
};

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// Returns vec3(min_dist, cell_id_hash, edge_dist)
fn voronoi(uv: vec2<f32>, scale: f32) -> vec4<f32> {
    let p = uv * scale;
    let i_st = floor(p);
    let f_st = fract(p);

    var min_dist = 8.0;
    var id_point = vec2<f32>(0.0);
    var cell_center = vec2<f32>(0.0);

    // First pass: find closest point
    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let point = hash22(i_st + neighbor);

            // Animate points slowly
            let anim = sin(u.config.x * 0.1 + 6.28 * point) * 0.1;

            let diff = neighbor + point + anim - f_st;
            let dist = length(diff);

            if (dist < min_dist) {
                min_dist = dist;
                id_point = point; // Use the hash point as ID
                cell_center = diff;
            }
        }
    }

    // Second pass: distance to borders (edge distance)
    var min_edge_dist = 8.0;
    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let point = hash22(i_st + neighbor);
            let anim = sin(u.config.x * 0.1 + 6.28 * point) * 0.1;

            let diff = neighbor + point + anim - f_st;

            // Skip the closest center itself
            if (dot(diff - cell_center, diff - cell_center) > 0.0001) {
                // Distance to the line halfway between cell_center and diff
                // The line passes through midpoint M = (cell_center + diff) * 0.5
                // The normal is N = normalize(diff - cell_center)
                // Distance = dot(M, N) ? No.
                // Distance from origin (f_st relative to current grid) to the perpendicular bisector.

                // Vector from center to neighbor
                let to_neighbor = diff - cell_center;
                let len = length(to_neighbor);
                let mid_dist = len * 0.5;

                // We want to project the vector (0,0) -> midpoint onto the direction of to_neighbor?
                // Actually simpler:
                // Voronoi edge distance is dot( (diff + cell_center)*0.5, normalize(diff-cell_center) )
                // But vectors are relative to f_st.

                let dist = dot( 0.5 * (cell_center + diff), normalize(diff - cell_center) );
                min_edge_dist = min(min_edge_dist, dist);
            }
        }
    }

    // min_edge_dist is positive inside the cell. approaches 0 at edge.
    // Invert it for "crack"

    return vec4<f32>(min_dist, id_point.x, id_point.y, min_edge_dist);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let uv_corr = vec2<f32>(uv.x * aspect, uv.y);

    let scale = u.zoom_params.x * 20.0 + 3.0;
    let crack_width = u.zoom_params.y * 0.1 + 0.001;
    let displacement = u.zoom_params.z * 0.05;
    let shiny = u.zoom_params.w;

    let vor = voronoi(uv_corr, scale);
    let edge_dist = vor.w;
    let id = vor.yz;

    // Crack mask
    let crack = 1.0 - smoothstep(0.0, crack_width, edge_dist);

    // Displacement
    // Shift UV based on cell ID
    let shift = (id - 0.5) * displacement;
    let uv_displaced = uv + shift;

    // Gold color
    let gold_base = vec3<f32>(1.0, 0.84, 0.0);

    // Lighting for gold (fake normal)
    // We can use the gradient of edge_dist as normal approx near edge?
    // Or just simple specular based on mouse
    let mouse = u.zoom_config.yz * vec2<f32>(aspect, 1.0);
    let to_mouse = normalize(mouse - uv_corr);
    // Cheap normal: points away from edge?
    // Hard to calculate without derivatives or multiple samples.
    // Let's make it sparkle based on ID and view angle.
    let sparkle = pow(abs(sin(dot(id, vec2<f32>(12.9898, 78.233)) * 6.28 + u.config.x)), 10.0) * shiny;
    let gold = gold_base * (0.5 + 0.5 * sparkle + 0.5 * crack); // Brighter in center of crack

    // Fetch texture
    let img_color = textureSampleLevel(readTexture, u_sampler, uv_displaced, 0.0).rgb;

    // Mix
    // If crack > 0.5, show gold. But smoothstep gives gradient.
    let final_color = mix(img_color, gold, crack);

    textureStore(writeTexture, global_id.xy, vec4<f32>(final_color, 1.0));
}
