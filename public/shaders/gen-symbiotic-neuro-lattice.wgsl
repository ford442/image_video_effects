// ═══════════════════════════════════════════════════════════════════
//  Symbiotic Neuro-Lattice
//  Category: generative
//  Features: ray-marching, audio-reactive, mouse-control, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-15
//  Ideas: axon capsules; firing wave
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.001;

fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / max(k, 0.001), 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    let q = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.6))
    );
    return fract(sin(q) * 43758.5453123);
}

fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

fn linkCapsule(local_p: vec3<f32>, node_pos: vec3<f32>, cell: vec3<f32>, off: vec3<f32>, grid: f32, radius: f32) -> f32 {
    let far = (hash3(cell + off) - 0.5) * grid * 0.8 + off * grid;
    return sdCapsule(local_p, node_pos, far, radius);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn map(p_in: vec3<f32>) -> vec2<f32> {
    var p = p_in;

    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
    let aspect = u.config.z / max(u.config.w, 0.001);
    let mouse_ndc = (u.zoom_config.yz * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
    let to_mouse = vec3<f32>(mouse_ndc, 0.0) - p;
    let dist_m = length(to_mouse);
    let pull = held / (1.0 + dist_m * dist_m);
    p = p - to_mouse / max(dist_m, 0.0001) * pull * u.zoom_params.y;

    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let grid_size = 2.0;
    let local_p = fract(p / grid_size) * grid_size - grid_size * 0.5;
    let cell_id = floor(p / grid_size);

    let node_pos = (hash3(cell_id) - 0.5) * grid_size * 0.8;
    // ── Idea 2: firing wave — Pulse Frequency travels across the lattice
    let fire = sin(u.config.x * u.zoom_params.w - dot(cell_id, vec3<f32>(0.85, 0.45, 0.7))) * 0.5 + 0.5;
    let node_dist = length(local_p - node_pos) - u.zoom_params.x * 0.4 - bass * 0.1 - fire * u.zoom_params.x * 0.12;
    var min_dist = node_dist;

    // ── Idea 1: axons — the capsule SDF, linked to the six neighbours
    let axon_r = max(u.zoom_params.x * 0.09, 0.02);
    let k = 0.3;
    min_dist = smin(min_dist, linkCapsule(local_p, node_pos, cell_id, vec3<f32>( 1.0, 0.0, 0.0), grid_size, axon_r), k);
    min_dist = smin(min_dist, linkCapsule(local_p, node_pos, cell_id, vec3<f32>(-1.0, 0.0, 0.0), grid_size, axon_r), k);
    min_dist = smin(min_dist, linkCapsule(local_p, node_pos, cell_id, vec3<f32>( 0.0, 1.0, 0.0), grid_size, axon_r), k);
    min_dist = smin(min_dist, linkCapsule(local_p, node_pos, cell_id, vec3<f32>( 0.0,-1.0, 0.0), grid_size, axon_r), k);
    min_dist = smin(min_dist, linkCapsule(local_p, node_pos, cell_id, vec3<f32>( 0.0, 0.0, 1.0), grid_size, axon_r), k);
    min_dist = smin(min_dist, linkCapsule(local_p, node_pos, cell_id, vec3<f32>( 0.0, 0.0,-1.0), grid_size, axon_r), k);

    return vec2<f32>(min_dist, fire);
}

fn get_normal(p: vec3<f32>) -> vec3<f32> {
    let d = map(p).x;
    let e = vec2<f32>(0.001, 0.0);
    let n = d - vec3<f32>(
        map(p - e.xyy).x,
        map(p - e.yxy).x,
        map(p - e.yyx).x
    );
    return n / max(length(n), 0.0001);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let q = (uv - 0.5) * 2.0;
    let aspect = resolution.x / max(resolution.y, 0.001);
    let ro = vec3<f32>(0.0, 0.0, -5.0 + u.config.x * u.zoom_params.z);
    let rd = normalize(vec3<f32>(q.x * aspect, q.y, 1.0));

    var d0 = 0.0;
    var hit = false;
    var mat_id = 0.0;

    for (var i = 0; i < MAX_STEPS; i = i + 1) {
        let p = ro + rd * d0;
        let d = map(p);
        if (abs(d.x) < SURF_DIST) {
            hit = true;
            mat_id = d.y;
            break;
        }
        if (d0 > MAX_DIST) { break; }
        d0 = d0 + d.x;
    }

    var col = vec3<f32>(0.01, 0.02, 0.05);
    var depth = 1.0;

    if (hit) {
        let p = ro + rd * d0;
        let n = get_normal(p);
        let l = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let dif = clamp(dot(n, l), 0.0, 1.0);
        let fire = clamp(mat_id, 0.0, 1.0);
        let node_col = mix(vec3<f32>(0.45, 0.55, 0.68), vec3<f32>(0.82, 0.94, 1.0), fire);
        col = node_col * (dif + 0.1) + vec3<f32>(0.15, 0.55, 1.0) * fire * fire;
        depth = clamp(d0 / MAX_DIST, 0.0, 1.0);
    }

    let display = aces(max(col, vec3<f32>(0.0)));
    let alpha = select(0.22, 0.7 + clamp(mat_id, 0.0, 1.0) * 0.25, hit);
    let outColor = vec4<f32>(display, alpha);

    textureStore(writeTexture, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, outColor);
}
