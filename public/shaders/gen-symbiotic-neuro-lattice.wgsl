#include "_prelude.wgsl"
// --- CONSTANTS ---
const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.001;

// --- UTILS ---
// Rotation matrix
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Smooth minimum (for organic blending)
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Hash function for random node positions
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.6))
    );
    return fract(sin(q) * 43758.5453123);
}

// --- SDFs ---
// Capsule
fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

// Lattice mapping function
fn map(p_in: vec3<f32>) -> vec2<f32> { // returns vec2(dist, material_id)
    var p = p_in;

    // Interaction: Mouse gravity well
    if (u.zoom_config.w > 0.5) {
        let mouse_ndc = (u.zoom_config.yz * 2.0 - 1.0) * vec2<f32>(u.config.z / u.config.w, 1.0);
        let dist_to_mouse = length(p.xy - mouse_ndc);
        let pull = 1.0 / (1.0 + dist_to_mouse * dist_to_mouse);
        p -= normalize(vec3<f32>(mouse_ndc, 0.0) - p) * pull * u.zoom_params.y; // using p2 for gravity strength
    }

    // Audio reactivity
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let pulse = sin(u.config.x * u.zoom_params.w) * 0.5 + 0.5;

    let grid_size = 2.0;
    let local_p = fract(p / grid_size) * grid_size - grid_size * 0.5;
    let cell_id = floor(p / grid_size);

    var min_dist = 1000.0;

    // Core node
    let node_pos = (hash3(cell_id) - 0.5) * grid_size * 0.8;
    let node_dist = length(local_p - node_pos) - u.zoom_params.x * 0.4 - bass * 0.1;
    min_dist = smin(min_dist, node_dist, 0.5);

    return vec2<f32>(min_dist, 1.0);
}

// --- RENDERING ---
fn get_normal(p: vec3<f32>) -> vec3<f32> {
    let d = map(p).x;
    let e = vec2<f32>(0.001, 0.0);
    let n = d - vec3<f32>(
        map(p - e.xyy).x,
        map(p - e.yxy).x,
        map(p - e.yyx).x
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let uv = vec2<f32>(global_id.xy) / resolution;
    if (uv.x >= 1.0 || uv.y >= 1.0) { return; }

    // Normalized coordinates
    let q = (uv - 0.5) * 2.0;
    let aspect = resolution.x / resolution.y;
    var ro = vec3<f32>(0.0, 0.0, -5.0 + u.config.x * u.zoom_params.z); // moving forward, speed mapped to p3
    var rd = normalize(vec3<f32>(q.x * aspect, q.y, 1.0));

    // Raymarching loop
    var d0 = 0.0;
    var hit = false;
    var mat_id = 0.0;

    for(var i=0; i<MAX_STEPS; i++) {
        let p = ro + rd * d0;
        let d = map(p);
        if(abs(d.x) < SURF_DIST) {
            hit = true;
            mat_id = d.y;
            break;
        }
        if(d0 > MAX_DIST) { break; }
        d0 += d.x;
    }

    var col = vec3<f32>(0.01, 0.02, 0.05); // Background
    var depth = 1.0;

    if(hit) {
        let p = ro + rd * d0;
        let n = get_normal(p);
        let l = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let dif = clamp(dot(n, l), 0.0, 1.0);
        let amb = 0.1;

        let node_col = vec3<f32>(0.8, 0.9, 1.0); // Metallic look
        col = node_col * (dif + amb);

        depth = d0 / MAX_DIST;
    }

    // Outputs
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 1.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(0.0));
}
