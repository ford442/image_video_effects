// ----------------------------------------------------------------
// Nebular Chrono-Astrolabe
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
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
    config: vec4<f32>, // x: Time, y: Audio/Click, z: ResX, w: ResY
    zoom_config: vec4<f32>, // x: ZoomTime, y: MouseX, z: MouseY, w: Gen
    zoom_params: vec4<f32>, // Sliders mapping
    ripples: array<vec4<f32>, 50>,
};

const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.001;

// --- SDF Primitives ---
fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

// --- Transformations ---
fn rot2D(angle: f32) -> mat2x2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return mat2x2<f32>(c, -s, s, c);
}

// --- Map Function ---
fn map(p: vec3<f32>) -> vec2<f32> {
    var d = MAX_DIST;
    var mat_id = 0.0;

    var p1 = p;
    // Apply mouse gravity well
    let mouse_pos = vec3<f32>((u.zoom_config.y - 0.5) * 5.0, (0.5 - u.zoom_config.z) * 5.0, 0.0);
    let dist_to_mouse = length(p1 - mouse_pos);
    p1 += normalize(mouse_pos - p1) * (1.0 / (dist_to_mouse * dist_to_mouse + 1.0)) * u.zoom_params.w;

    // Inner Core
    var p_core = p1;
    p_core.xy = rot2D(u.config.x * u.zoom_params.x) * p_core.xy;
    let core = length(p_core) - 0.5;
    d = core;
    mat_id = 1.0;

    // Astrolabe Rings
    let num_rings = i32(u.zoom_params.y);
    for(var i=0; i<5; i++) {
        if(i >= num_rings) { break; }
        var p_ring = p1;
        let fi = f32(i);
        p_ring.yz = rot2D(u.config.x * 0.5 + u.config.y * 2.0 + fi * 0.5) * p_ring.yz;
        p_ring.xz = rot2D(u.config.x * 0.2 * u.zoom_params.x + fi * 1.2) * p_ring.xz;

        let ring = sdTorus(p_ring, vec2<f32>(1.5 + fi * 0.4, 0.05 + fi * 0.02));

        if (ring < d) {
            d = ring;
            mat_id = 2.0 + fi * 0.5;
        }
    }

    return vec2<f32>(d, mat_id);
}

// --- Raymarch ---
fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec3<f32> {
    var dO = 0.0;
    var mat = 0.0;
    var glow = 0.0;
    for(var i=0; i<MAX_STEPS; i++) {
        let p = ro + rd * dO;
        let dS = map(p);
        dO += dS.x;
        mat = dS.y;

        // Accumulate glow based on distance to surfaces
        glow += max(0.0, 0.05 - dS.x) * u.zoom_params.z;

        if(dO > MAX_DIST || abs(dS.x) < SURF_DIST) { break; }
    }
    return vec3<f32>(dO, mat, glow);
}

// --- Normals ---
fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let d = map(p).x;
    let e = vec2<f32>(0.001, 0.0);
    let n = d - vec3<f32>(
        map(p - e.xyy).x,
        map(p - e.yxy).x,
        map(p - e.yyx).x
    );
    return normalize(n);
}

// --- Main Compute ---
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let uv = (vec2<f32>(id.xy) * 2.0 - res) / res.y;

    if (f32(id.x) >= res.x || f32(id.y) >= res.y) { return; }

    let ro = vec3<f32>(0.0, 0.0, -10.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    let rm = raymarch(ro, rd);
    let d = rm.x;
    let mat = rm.y;
    let glow = rm.z;

    var col = vec3<f32>(0.0);

    if (d < MAX_DIST) {
        let p = ro + rd * d;
        let n = getNormal(p);
        let lightDir = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);

        if (mat == 1.0) {
            col = vec3<f32>(0.2, 0.8, 1.0) * diff + vec3<f32>(0.0, 0.4, 0.8); // Core
        } else if (mat >= 2.0) {
            // Vary ring color slightly based on material id
            let ring_col = vec3<f32>(1.0, 0.8, 0.2) * (1.0 - (mat - 2.0) * 0.2);
            col = ring_col * diff + vec3<f32>(0.8, 0.4, 0.0) * 0.5; // Rings
        }
    } else {
        col = vec3<f32>(0.01, 0.02, 0.05); // Background
    }

    // Add volumetric glow
    col += vec3<f32>(0.1, 0.4, 0.8) * glow * 0.5;

    // Output
    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}