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
  zoom_params: vec4<f32>,  // x=Density, y=Zoom, z=Turbulence, w=Speed
  ripples: array<vec4<f32>, 50>,
};

fn hash2(p: vec2<f32>) -> vec2<f32> {
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
    let mouse = u.zoom_config.yz;

    // Params
    let density = 5.0 + u.zoom_params.x * 20.0;
    let zoomAmount = u.zoom_params.y * 2.0; // 0 to 2
    let turbulence = u.zoom_params.z;
    let speed = u.zoom_params.w * 2.0;
    let time = u.config.x * speed;

    // Correct aspect for grid
    let uvGrid = uv;
    uvGrid.x *= aspect;

    let i_st = floor(uvGrid * density);
    let f_st = fract(uvGrid * density);

    var m_dist = 1.0;  // Minimum distance
    var m_point = vec2<f32>(0.0); // Closest point relative pos
    var m_id = vec2<f32>(0.0);    // Closest point ID

    // Voronoi Loop
    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let id = i_st + neighbor;

            // Random point in cell
            var point = hash2(id);

            // Animate point
            point = 0.5 + 0.5 * sin(time + 6.2831 * point);

            // Vector from current pixel to point
            let diff = neighbor + point - f_st;
            let dist = length(diff);

            if (dist < m_dist) {
                m_dist = dist;
                m_point = diff; // Vector to center
                m_id = id;
            }
        }
    }

    // Interactive Turbulence based on Mouse
    let mouseDist = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));
    let mouseInfluence = smoothstep(0.5, 0.0, mouseDist); // Stronger near mouse

    // Apply turbulence
    // Use the cell ID to create random offset
    let cellHash = hash2(m_id);
    let turbAngle = (cellHash.x * 6.28) + time + mouseDist * 10.0;
    let turbVec = vec2<f32>(cos(turbAngle), sin(turbAngle)) * turbulence * 0.1 * (1.0 + mouseInfluence * 2.0);

    // Zoom Effect
    // Center of the cell in UV space
    // uv is current pixel.
    // m_point is vector from pixel to cell center (in grid space).
    // So cell center in grid space is: (uvGrid * density) + m_point
    // Wait, m_point is (neighbor + point - f_st).
    // Vector FROM pixel TO point.
    // So Pixel + m_point = Point.
    // Normalized vector to center:
    let dir = normalize(m_point);

    // Distort UV
    // Push UV away from cell center (zoom in) or towards (zoom out)
    // We want to sample the texture such that it looks like each cell is a lens.

    // Scale the offset from the center
    // If zoomAmount is 1.0, we want normal scale? No.
    // Lens distortion: sampleUV = center + (pixel - center) / zoom

    // Convert m_point (grid space delta) to UV space delta
    let uvDelta = m_point / density;
    uvDelta.x /= aspect; // Fix aspect back

    // Apply lens zoom
    // if zoom > 1, we divide delta, sampling smaller area -> magnification
    let lensScale = max(0.1, 1.0 - (zoomAmount * 0.5 + mouseInfluence * 0.5));

    let finalUV = uv + uvDelta * (1.0 - lensScale) + turbVec;

    // Add border
    let border = smoothstep(0.0, 0.05, m_dist);

    var color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

    // Darken edges
    // color = color * smoothstep(0.0, 0.1, m_dist); // Inverted? m_dist is 0 at center? No, m_dist is dist to center.
    // m_dist is 0 at center, approx 0.5 at edge.
    // So we want 1.0 at center, 0.0 at edge.

    // Calculate distance to edge (approx)
    // Voronoi edge distance is harder.
    // Just use center glow.
    color = color * (1.0 - smoothstep(0.3, 0.8, m_dist));

    // Tint cells based on ID
    let tint = vec3<f32>(cellHash.x, cellHash.y, 1.0 - cellHash.x) * 0.1;
    color = color + vec4<f32>(tint, 0.0);

    textureStore(writeTexture, global_id.xy, color);
}
