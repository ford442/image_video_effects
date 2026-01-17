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

// Voronoi Web
// Param1: Web Thickness
// Param2: Cell Scale
// Param3: Glow Strength
// Param4: Pulse Speed

fn hash2(p: vec2<f32>) -> vec2<f32> {
    var p2 = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(p2) * 43758.5453123);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    var st = uv;
    st.x = st.x * aspect;

    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    var mouseSt = mousePos;
    mouseSt.x = mouseSt.x * aspect;

    let thickness = u.zoom_params.x * 0.1 + 0.01;
    let scale = u.zoom_params.y * 10.0 + 3.0;
    let glow = u.zoom_params.z * 2.0;
    let pulseSpeed = u.zoom_params.w;

    // Scale space
    let i_st = floor(st * scale);
    let f_st = fract(st * scale);

    var m_dist = 1.0;  // Minimum distance
    var m_point = vec2<f32>(0.0);

    // 1st pass: Find closest point
    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let point = hash2(i_st + neighbor);

            // Animate points
            let p_anim = 0.5 + 0.5 * sin(time * pulseSpeed + 6.2831 * point);
            let diff = neighbor + p_anim - f_st;
            let dist = length(diff);

            if (dist < m_dist) {
                m_dist = dist;
                m_point = point;
            }
        }
    }

    // 2nd pass: Distance to borders (Voronoi edges)
    var m_dist2 = 1.0;
    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let point = hash2(i_st + neighbor);
            let p_anim = 0.5 + 0.5 * sin(time * pulseSpeed + 6.2831 * point);

            let diff = neighbor + p_anim - f_st;
            let dist = length(diff);

            if (dist > m_dist + 0.0001) { // Skip the closest point itself
                // Intersection of two perpendicular bisectors logic simplified for "border distance"
                // Actually simpler: just find 2nd closest distance.
                // But better for edges: dot( (p1+p2)/2 - uv, normalize(p2-p1) )
                m_dist2 = min(m_dist2, dist);
            }
        }
    }

    // Check distance to mouse as an "external" voronoi point that overrides?
    // Or just overlay a web from the mouse?
    // Let's make the mouse attract the web lines.

    // Instead of complex 2nd pass edge detection, let's use the difference between closest and 2nd closest
    // This creates "mountains" at the edges.
    let edgeVal = m_dist2 - m_dist;

    // Create the web pattern
    let web = smoothstep(thickness, 0.0, edgeVal);

    // Mouse influence: Glow intensity based on distance to mouse
    let distToMouse = length(st - mouseSt);
    let mouseInfluence = smoothstep(0.5, 0.0, distToMouse);

    // Sample original image
    var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Mix web
    let webColor = vec3<f32>(0.0, 0.8, 1.0) + vec3<f32>(0.5 * sin(time), 0.0, 0.5 * cos(time));

    // Final composite
    let finalGlow = web * (glow + mouseInfluence * 2.0);
    color = mix(color, vec4<f32>(webColor, 1.0), finalGlow * 0.5);
    color = color + vec4<f32>(webColor * finalGlow, 0.0);

    textureStore(writeTexture, global_id.xy, color);

    // Pass depth
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
