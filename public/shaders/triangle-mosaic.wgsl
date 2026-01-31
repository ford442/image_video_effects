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

fn rotate2d(angle: f32) -> mat2x2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return mat2x2<f32>(c, -s, s, c);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    let scale_param = u.zoom_params.x; // Scale
    let rotation_param = u.zoom_params.y; // Global Rotation
    let twist_param = u.zoom_params.z; // Interactive Twist
    let mix_param = u.zoom_params.w; // Mix

    let cells = scale_param * 50.0 + 5.0;

    // Correct aspect ratio for grid
    var p = uv;
    p.x *= aspect;

    // Center for rotation
    let center = vec2<f32>(0.5 * aspect, 0.5);

    // Interactive twist
    let d = distance(p, vec2<f32>(mouse.x * aspect, mouse.y));
    let angle = rotation_param * 6.28 + (1.0 - smoothstep(0.0, 0.5, d)) * twist_param * 3.14;

    // Skew for triangular grid
    let s = vec2<f32>(1.0, 1.732); // sqrt(3)

    // Apply rotation to UVs before grid mapping? No, rotate the grid sampling.
    // Let's rotate the point P around the mouse? Or just global rotation?
    // Let's do local rotation of the grid coordinates.

    // Triangle Grid Logic
    let uv_scaled = p * cells;
    let r = vec2<f32>(1.0, 1.732);
    let h = r * 0.5;

    let a = mod(uv_scaled, r) - h;
    let b = mod(uv_scaled - h, r) - h;

    let g = dot(a, a) < dot(b, b);
    var vert_id = vec2<f32>(0.0);

    if (g) {
        vert_id = floor(uv_scaled / r) * r + h;
    } else {
        vert_id = floor((uv_scaled - h) / r) * r + h + h;
    }

    // vert_id is the center of the hex/triangle area?
    // Actually this logic produces a hexagonal grid center.
    // For triangles, we need 3 centers?
    // Let's stick to Hexagon centers for now as "Triangle Mosaic" often implies Delaunay/Hex duals.
    // Or just simple skewed grid.

    // Let's use the skewed grid approach for actual triangles.
    let skew_mat = mat2x2<f32>(1.0, 0.0, -0.57735, 1.1547);
    let unskew_mat = mat2x2<f32>(1.0, 0.0, 0.5, 0.866025);

    let skewed_uv = uv_scaled * skew_mat;
    let i_uv = floor(skewed_uv);
    let f_uv = fract(skewed_uv);

    // Split quad into two triangles
    var tri_offset = vec2<f32>(0.0);
    if (f_uv.x > f_uv.y) {
        tri_offset = vec2<f32>(0.66, 0.33); // centroid approx
    } else {
        tri_offset = vec2<f32>(0.33, 0.66);
    }

    let tri_center_skewed = i_uv + tri_offset;
    var tri_center = tri_center_skewed * unskew_mat;

    // Map back to UV space
    tri_center = tri_center / cells;
    tri_center.x /= aspect;

    // Apply twist rotation to the sampling point relative to the actual pixel?
    // No, we want to sample the image at the triangle center.

    var sample_uv = tri_center;

    // Apply global rotation to sample_uv around 0.5
    let uv_centered = sample_uv - 0.5;
    let rot_mat = rotate2d(angle);
    sample_uv = 0.5 + uv_centered * rot_mat;

    var color = textureSampleLevel(readTexture, u_sampler, clamp(sample_uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let orig = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Edge darkening
    // let dist_to_edge ... (complex)

    color = mix(orig, color, mix_param);

    textureStore(writeTexture, global_id.xy, color);

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

fn mod(x: vec2<f32>, y: vec2<f32>) -> vec2<f32> {
    return x - y * floor(x / y);
}
