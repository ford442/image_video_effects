// ----------------------------------------------------------------
// Bismuth Singularity-Loom Engine
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

struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

// --- CORE LOGIC ---
const MAX_STEPS: i32 = 120;
const MAX_DIST: f32 = 50.0;
const SURF_DIST: f32 = 0.001;

fn rot3D(axis: vec3<f32>, angle: f32) -> mat3x3<f32> {
    let c = cos(angle);
    let s = sin(angle);
    let t = 1.0 - c;
    let x = axis.x; let y = axis.y; let z = axis.z;
    return mat3x3<f32>(
        t*x*x + c,   t*x*y - s*z, t*x*z + s*y,
        t*x*y + s*z, t*y*y + c,   t*y*z - s*x,
        t*x*z - s*y, t*y*z + s*x, t*z*z + c
    );
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

fn mod_f32(x: f32, y: f32) -> f32 {
    return x - y * floor(x / y);
}

fn map(p: vec3<f32>) -> vec2<f32> {
    let time = u.config.x;
    let audio = u.config.y;
    let mouse = u.zoom_config.yz;

    var pos = p;

    // Angular repetition
    let angle = atan2(pos.z, pos.x);
    let radius = length(vec2<f32>(pos.x, pos.z));
    let sector = 6.28318 / 6.0;

    let a_mod = mod_f32(angle + sector * 0.5, sector) - sector * 0.5;

    pos = vec3<f32>(radius * cos(a_mod), pos.y, radius * sin(a_mod));

    // Shift outwards to create space for singularity
    pos = pos - vec3<f32>(2.5, 0.0, 0.0);

    // Twist based on mouse
    pos = rot3D(vec3<f32>(0.0, 1.0, 0.0), time * 0.1 + mouse.x * 2.0) * pos;
    pos = rot3D(vec3<f32>(1.0, 0.0, 0.0), mouse.y * 2.0) * pos;

    // Implementation of stepped Bismuth hopper-crystal logic via repeated boolean subtractions
    var q = abs(pos) - vec3<f32>(1.0);
    var d = sdBox(q, vec3<f32>(1.0)); // Placeholder base shape

    let iters = i32(u.zoom_params.y);
    var scale = 1.0;
    let ext = audio * u.zoom_params.w;

    for (var i: i32 = 0; i < 10; i++) {
        if (i >= iters) { break; }

        q = abs(q) - vec3<f32>(0.5 / scale) - vec3<f32>(ext * 0.1 / scale);
        q = rot3D(normalize(vec3<f32>(1.0, 1.0, 1.0)), 0.1) * q;

        let sub_box = sdBox(q, vec3<f32>(0.6 / scale));
        d = max(d, -sub_box);

        scale *= 1.3;
    }

    return vec2<f32>(d, 1.0); // dist, material_id
}

fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + vec3<f32>(e.x, e.y, e.y)).x - map(p - vec3<f32>(e.x, e.y, e.y)).x,
        map(p + vec3<f32>(e.y, e.x, e.y)).x - map(p - vec3<f32>(e.y, e.x, e.y)).x,
        map(p + vec3<f32>(e.y, e.y, e.x)).x - map(p - vec3<f32>(e.y, e.y, e.x)).x
    ));
}

fn raymarching(ro: vec3<f32>, rd_in: vec3<f32>) -> vec4<f32> {
    var dO: f32 = 0.0;
    var col: vec3<f32> = vec3<f32>(0.0);
    var p = ro;
    var rd = rd_in;

    var hit = false;
    var glow = 0.0;
    var iter_count = 0;

    let mouse = u.zoom_config.yz;

    for(var i: i32 = 0; i < MAX_STEPS; i++) {
        iter_count = i;
        // Implement gravitational lensing (bend ray towards center)
        let dist_to_center = length(p);
        let pull_str = (u.zoom_params.x + mouse.y * 0.5) / (dist_to_center * dist_to_center + 0.1);
        rd = normalize(rd - normalize(p) * pull_str * 0.05); // Bend ray

        let map_res = map(p);
        let dS = map_res.x;

        glow += 0.01 / (0.01 + abs(dS));

        if(dS < SURF_DIST) {
            hit = true;
            break;
        }
        if(dO > MAX_DIST) {
            break;
        }

        p += rd * dS;
        dO += dS;
    }

    // Shade base on hit normal + iridescence
    if (hit) {
        let normal = getNormal(p);
        let view_dir = -rd;
        let ndotv = max(dot(normal, view_dir), 0.0);

        let freq = u.zoom_params.z;
        let a = vec3<f32>(0.5);
        let b = vec3<f32>(0.5);
        let c = vec3<f32>(freq);
        let d = vec3<f32>(0.0, 0.33, 0.67);

        let base_col = palette(ndotv, a, b, c, d);
        let ao = 1.0 - f32(iter_count) / f32(MAX_STEPS);

        col = base_col * ao;
    }

    // Add emissive flux veins based on audio
    let audio = u.config.y;
    col += vec3<f32>(0.1, 0.4, 1.0) * glow * 0.015 * (1.0 + audio * 3.0);

    return vec4<f32>(col, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    if (id.x >= dims.x || id.y >= dims.y) { return; }

    let uv = (vec2<f32>(id.xy) - 0.5 * vec2<f32>(dims)) / f32(dims.y);

    let ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(uv.x, uv.y, 1.0));

    let color = raymarching(ro, rd);

    textureStore(writeTexture, id.xy, color);
}
