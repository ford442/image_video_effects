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

// Simple hash for Voronoi
fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mouse = u.zoom_config.yz;
    let time = u.config.x;

    // Params
    let density = mix(5.0, 50.0, u.zoom_params.x);
    let lightRadius = u.zoom_params.y;
    let colorMode = u.zoom_params.z;
    let pulseSpeed = u.zoom_params.w;

    // Aspect corrected UV for voronoi
    let st = uv * vec2(aspect, 1.0) * density;

    let i_st = floor(st);
    let f_st = fract(st);

    var m_dist = 1.0;  // Minimun distance
    var m_point = vec2(0.0); // Closest point ID

    // Voronoi Cell Search
    for (var y= -1; y <= 1; y++) {
        for (var x= -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let point = hash22(i_st + neighbor);

            // Animate point
            let anim = 0.5 + 0.5 * sin(time * pulseSpeed + 6.2831 * point);
            let pos = neighbor + point * anim;

            let diff = pos - f_st;
            let dist = length(diff);

            if (dist < m_dist) {
                m_dist = dist;
                m_point = point; // Use the random point as ID
            }
        }
    }

    // We have the cell info.
    // Calculate cell center in screen UV
    // The 'point' is relative to grid.
    // This is hard to reverse exactly without storing more info.
    // Instead, let's just use the current pixel distance to mouse to light up the whole cell?
    // Better: We are in a specific cell. The cell is defined by 'i_st'.
    // The closest point ID 'm_point' acts as a seed.

    // Let's use the distance from the pixel to mouse to trigger the cell.
    // But we want the WHOLE cell to light up uniformly if it's close.
    // To do that, we need the cell center's distance to mouse.
    // Approximating: The current pixel is close enough to center.

    let dVec = (uv - mouse) * vec2(aspect, 1.0);
    let distMouse = length(dVec);

    // Highlight based on distance
    let highlight = 1.0 - smoothstep(lightRadius, lightRadius + 0.1, distMouse);

    // Add some pulsing to the highlight
    let pulse = 0.8 + 0.2 * sin(time * 5.0);

    // Sample texture
    var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Border
    let border = smoothstep(0.02, 0.05, m_dist);

    // Apply effect
    if (colorMode < 0.5) {
        // Tech Mode: Darken everything, light up cells near mouse
        let cellColor = color * highlight * pulse;
        color = mix(vec4(0.0, 0.0, 0.0, 1.0), cellColor, border);
        // Add neon edge
        color += vec4(0.0, 1.0, 1.0, 1.0) * (1.0 - border) * highlight;
    } else {
        // Glass Mode: Refract
        // Use the cell normal (diff from center) to offset UV?
        // m_dist is distance to center.
        // We need vector to center.
        // Re-calculate is expensive.
        // Let's just use 'highlight' to brighten.
        color = color * (0.5 + 0.5 * highlight);
        // Dark borders
        color *= border;
    }

    textureStore(writeTexture, global_id.xy, color);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
}
