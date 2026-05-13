// ----------------------------------------------------------------
// Holographic Bismuth-Core Reactor
// Category: generative
// ----------------------------------------------------------------

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
  config: vec4<f32>, // x: resolution.x, y: resolution.y, z: time, w: aspect
  zoom_config: vec4<f32>, // x: mouse.x, y: mouse.y, z: is_clicking, w: audio_intensity
  zoom_params: vec4<f32>, // param1: Core Size, param2: Iridescence Shift, param3: Pulse Intensity, param4: Plasma Density
  ripples: array<vec4<f32>, 50>
};

const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 50.0;
const SURF_DIST: f32 = 0.001;

// 3D rotation helper
fn rot3D(axis: vec3<f32>, angle: f32) -> mat3x3<f32> {
    let a = normalize(axis);
    let s = sin(angle);
    let c = cos(angle);
    let oc = 1.0 - c;
    return mat3x3<f32>(
        oc * a.x * a.x + c,           oc * a.x * a.y - a.z * s,  oc * a.z * a.x + a.y * s,
        oc * a.x * a.y + a.z * s,     oc * a.y * a.y + c,        oc * a.y * a.z - a.x * s,
        oc * a.z * a.x - a.y * s,     oc * a.y * a.z + a.x * s,  oc * a.z * a.z + c
    );
}

// Custom KIFS box SDF for 90-degree steps
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn map(p_in: vec3<f32>) -> vec2<f32> {
    var p = p_in;

    // Mouse warp of gravity field
    let mouse = u.zoom_config.xy;
    p = rot3D(vec3<f32>(1.0, 0.0, 0.0), mouse.y * 3.14) * p;
    p = rot3D(vec3<f32>(0.0, 1.0, 0.0), mouse.x * 3.14) * p;

    var s: f32 = 1.0;

    // Audio reactive pulse
    let pulse = sin(u.config.z * 2.0) * 0.5 + 0.5;
    let core_scale = u.zoom_params.x * (1.0 + pulse * u.zoom_config.w * u.zoom_params.z);

    // KIFS Bismuth fractals
    for (var i = 0; i < 4; i++) {
        p = abs(p) - vec3<f32>(0.5, 0.5, 0.5) * core_scale;
        p = rot3D(vec3<f32>(0.0, 1.0, 0.0), 1.5708) * p; // 90 deg folding
        p = rot3D(vec3<f32>(1.0, 0.0, 0.0), 1.5708) * p;
        p = p * 1.5;
        s *= 1.5;
    }

    let d1 = sdBox(p, vec3<f32>(0.3, 0.3, 0.3)) / s;

    // Orbiting micro-crystals
    var p2 = p_in;
    p2 = rot3D(vec3<f32>(0.0, 1.0, 0.0), u.config.z) * p2;
    p2 = p2 - round(p2 / 2.0) * 2.0; // Domain repetition
    let d2 = sdBox(p2, vec3<f32>(0.05, 0.05, 0.05));

    if (d1 < d2) {
        return vec2<f32>(d1, 1.0); // ID 1 = Core
    }
    return vec2<f32>(d2, 2.0); // ID 2 = Micro-crystals
}

fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p).x;
    let n = vec3<f32>(
        d - map(p - vec3<f32>(e.x, e.y, e.y)).x,
        d - map(p - vec3<f32>(e.y, e.x, e.y)).x,
        d - map(p - vec3<f32>(e.y, e.y, e.x)).x
    );
    return normalize(n);
}

// Iridescence based on thin-film interference
fn iridescence(dot_vn: f32) -> vec3<f32> {
    let t = dot_vn * 2.0 + u.zoom_params.y + u.config.z * 0.5 + u.zoom_config.w * u.zoom_params.z;
    let r = sin(t * 3.14) * 0.5 + 0.5;
    let g = sin(t * 3.14 + 2.09) * 0.5 + 0.5;
    let b = sin(t * 3.14 + 4.18) * 0.5 + 0.5;
    return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let uv = (vec2<f32>(id.xy) - 0.5 * u.config.xy) / u.config.y;
    if (uv.x > 1.0 || uv.y > 1.0 || uv.x < -1.0 || uv.y < -1.0) { return; }

    var ro = vec3<f32>(0.0, 0.0, -5.0);
    var rd = normalize(vec3<f32>(uv.x, uv.y, 1.0));

    var p = ro;
    var dO = 0.0;
    var res = vec2<f32>(0.0);
    var accum = 0.0;

    for (var i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * dO;
        res = map(p);
        let dS = res.x;
        dO += dS;

        // Volumetric plasma accumulation
        accum += u.zoom_params.w * 0.05 / (1.0 + abs(dS) * 50.0);

        if (dS < SURF_DIST || dO > MAX_DIST) { break; }
    }

    var col = vec3<f32>(0.0);

    if (dO < MAX_DIST) {
        let n = getNormal(p);
        let v = -rd;
        let dot_vn = max(dot(v, n), 0.0);

        col = iridescence(dot_vn);

        // Add lighting falloff
        col *= exp(-dO * 0.1);
    }

    // Add plasma bloom
    col += vec3<f32>(0.2, 0.6, 1.0) * accum;

    let out_col = vec4<f32>(col, 1.0);
    let coords = vec2<i32>(id.xy);
    if (coords.x < i32(u.config.x) && coords.y < i32(u.config.y)) {
        textureStore(writeTexture, coords, out_col);
    }
}