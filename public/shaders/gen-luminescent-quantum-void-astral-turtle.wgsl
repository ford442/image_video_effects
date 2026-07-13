struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

// ----------------------------------------------------------------
// Luminescent Quantum-Void Astral-Turtle
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

// PRNG
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash33(p3_in: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p3_in * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// 2D Rotation
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D Noise (value noise)
fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    let n = mix(
        mix(
            mix(hash12(i.xy + vec2<f32>(0.0, 0.0) + i.z * vec2<f32>(17.0, 37.0)),
                hash12(i.xy + vec2<f32>(1.0, 0.0) + i.z * vec2<f32>(17.0, 37.0)), u.x),
            mix(hash12(i.xy + vec2<f32>(0.0, 1.0) + i.z * vec2<f32>(17.0, 37.0)),
                hash12(i.xy + vec2<f32>(1.0, 1.0) + i.z * vec2<f32>(17.0, 37.0)), u.x), u.y),
        mix(
            mix(hash12(i.xy + vec2<f32>(0.0, 0.0) + (i.z + 1.0) * vec2<f32>(17.0, 37.0)),
                hash12(i.xy + vec2<f32>(1.0, 0.0) + (i.z + 1.0) * vec2<f32>(17.0, 37.0)), u.x),
            mix(hash12(i.xy + vec2<f32>(0.0, 1.0) + (i.z + 1.0) * vec2<f32>(17.0, 37.0)),
                hash12(i.xy + vec2<f32>(1.0, 1.0) + (i.z + 1.0) * vec2<f32>(17.0, 37.0)), u.x), u.y), u.z);
    return n;
}

// fBm
fn fbm(p: vec3<f32>, octaves: i32) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec3<f32>(100.0);
    var p_mut = p;
    for (var i = 0; i < octaves; i = i + 1) {
        v = v + a * noise(p_mut);
        p_mut = p_mut * 2.0 + shift;
        a = a * 0.5;
    }
    return v;
}

// SDFs
fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

fn sdEllipsoid(p: vec3<f32>, r: vec3<f32>) -> f32 {
    let k0 = length(p / r);
    let k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / k1;
}

// Smooth min
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

struct MapResult {
    d: f32,
    mat: f32,
    glow: vec3<f32>,
}

fn map(pos: vec3<f32>, time: f32, audio: f32) -> MapResult {
    var res = MapResult(1000.0, 0.0, vec3<f32>(0.0));
    let t = time * 0.5;

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
    let mouse_dist = length(mouse);
    var p = pos;

    // Orbital distortion from mouse
    let rotA = rot2D(mouse.x * 2.0);
    let rotB = rot2D(mouse.y * 2.0);
    let rotX = rot2D(mouse_dist * 5.0);
    let xz_new = rotX * p.xz;
    p = vec3<f32>(xz_new.x, p.y, xz_new.y);

    let xy_r = rotA * p.xy;
    p = vec3<f32>(xy_r.x, xy_r.y, p.z);
    let yz_r = rotB * p.yz;
    p = vec3<f32>(p.x, yz_r.x, yz_r.y);

    // Turtle Body
    var turtle_p = p;
    // Hovering motion
    turtle_p = turtle_p + vec3<f32>(0.0, sin(t * 2.0) * 0.2, 0.0);
    let yz_t = rot2D(sin(t)*0.1) * turtle_p.yz;
    turtle_p = vec3<f32>(turtle_p.x, yz_t.x, yz_t.y);

    // Shell
    let frac_detail = u.zoom_params.x; // Fractal Detail
    let acoustic_react = u.zoom_params.w; // Acoustic Reactivity

    var shell_p = turtle_p;
    let shell_base = sdEllipsoid(shell_p, vec3<f32>(1.2, 0.5, 1.5));
    // fBm displacement for crystalline shell
    let shell_disp = fbm(shell_p * frac_detail + t, 4) * 0.3;
    let shell_audio_disp = audio * acoustic_react * fbm(shell_p * 10.0 - t * 5.0, 2) * 0.2;
    let d_shell = shell_base - shell_disp + shell_audio_disp;

    // Head
    var head_p = turtle_p - vec3<f32>(0.0, 0.1, 1.8);
    let d_head = sdEllipsoid(head_p, vec3<f32>(0.3, 0.25, 0.4));

    // Fins
    // Front fins
    var fl_p = turtle_p - vec3<f32>(1.2, 0.0, 1.0);
    let xy_fl = rot2D(0.5 + sin(t*3.0)*0.2) * fl_p.xy;
    fl_p = vec3<f32>(xy_fl.x, xy_fl.y, fl_p.z);
    let yz_fl = rot2D(-0.2) * fl_p.yz;
    fl_p = vec3<f32>(fl_p.x, yz_fl.x, yz_fl.y);
    let d_fl = sdEllipsoid(fl_p, vec3<f32>(0.8, 0.05, 0.3));

    var fr_p = turtle_p - vec3<f32>(-1.2, 0.0, 1.0);
    let xy_fr = rot2D(-0.5 - sin(t*3.0)*0.2) * fr_p.xy;
    fr_p = vec3<f32>(xy_fr.x, xy_fr.y, fr_p.z);
    let yz_fr = rot2D(-0.2) * fr_p.yz;
    fr_p = vec3<f32>(fr_p.x, yz_fr.x, yz_fr.y);
    let d_fr = sdEllipsoid(fr_p, vec3<f32>(0.8, 0.05, 0.3));

    // Temporal rippling on fins
    let ripple = sin(turtle_p.x * 5.0 + t * 10.0) * 0.05 * audio * acoustic_react;
    let d_fins = smin(d_fl, d_fr, 0.2) + ripple;

    // Combine turtle parts
    let d_turtle_body = smin(d_head, d_fins, 0.3);
    let d_turtle = smin(d_shell, d_turtle_body, 0.2);

    res.d = d_turtle;
    res.mat = 1.0;

    // Quantum Core (inside shell)
    let d_core = sdSphere(turtle_p - vec3<f32>(0.0, 0.1, 0.0), 0.4) - audio * 0.2;
    if (d_core < res.d) {
        res.d = d_core;
        res.mat = 2.0;
    }

    // Plasma Glow mapping
    let pg = u.zoom_params.y;
    res.glow = vec3<f32>(0.0);
    if (d_shell < 0.5) {
        let emission = clamp(1.0 - d_shell*2.0, 0.0, 1.0) * pg;
        let c_base = vec3<f32>(0.2, 0.8, 1.0); // Cyan
        let c_peak = vec3<f32>(1.0, 0.2, 0.8); // Pink
        res.glow = mix(c_base, c_peak, audio * acoustic_react) * emission;
    }

    return res;
}

// Raymarching
fn calcNormal(p: vec3<f32>, time: f32, audio: f32) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.001;
    return normalize(
        e.xyy * map(p + e.xyy, time, audio).d +
        e.yyx * map(p + e.yyx, time, audio).d +
        e.yxy * map(p + e.yxy, time, audio).d +
        e.xxx * map(p + e.xxx, time, audio).d
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let size = textureDimensions(writeTexture);
    if (id.x >= size.x || id.y >= size.y) { return; }

    let time = u.config.x;
    let audio = u.config.y;

    let fragCoord = vec2<f32>(id.xy);
    let resolution = vec2<f32>(size);
    var uv = (fragCoord - 0.5 * resolution) / resolution.y;

    // Camera setup
    let ro = vec3<f32>(0.0, 2.0, -6.0);
    let ta = vec3<f32>(0.0, 0.0, 0.0);
    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));
    let rd = normalize(uv.x * uu + uv.y * vv + 1.5 * ww);

    // Raymarching
    var t_dist = 0.0;
    var col = vec3<f32>(0.0);
    var accum_glow = vec3<f32>(0.0);

    let max_steps = 100;
    let max_dist = 20.0;
    let surf_dist = 0.001;

    var hit = false;
    var m = MapResult(0.0, 0.0, vec3<f32>(0.0));

    for (var i = 0; i < max_steps; i = i + 1) {
        let p = ro + rd * t_dist;
        m = map(p, time, audio);

        // Volumetric accumulation
        let void_dens = u.zoom_params.z;
        let v_noise = fbm(p * 0.5 - time * 0.2, 3);
        let vol_dens_local = max(0.0, v_noise - 0.5) * void_dens;
        accum_glow = accum_glow + m.glow * 0.02 + vec3<f32>(0.1, 0.05, 0.2) * vol_dens_local * 0.05 * (1.0 + audio * u.zoom_params.w);

        if (abs(m.d) < surf_dist) {
            hit = true;
            break;
        }
        if (t_dist > max_dist) {
            break;
        }
        t_dist = t_dist + m.d * 0.5; // step safely
    }

    if (hit) {
        let p = ro + rd * t_dist;
        let n = calcNormal(p, time, audio);
        let l = normalize(vec3<f32>(1.0, 2.0, -3.0));

        let dif = max(dot(n, l), 0.0);
        let amb = 0.1;
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

        var mat_col = vec3<f32>(0.1, 0.1, 0.2); // Shell base
        if (m.mat == 2.0) {
            mat_col = vec3<f32>(1.0, 0.5, 0.8) * (1.0 + audio * 2.0); // Core
        }

        col = mat_col * (dif + amb) + vec3<f32>(0.5, 0.8, 1.0) * fresnel * u.zoom_params.y;
    }

    // Add accumulated glow and background
    col = col + accum_glow;

    // Chromatic aberration / Bloom mapping based on distance/audio
    col = col * (1.0 - length(uv) * 0.3);

    // Tonemapping
    col = col / (col + vec3<f32>(1.0));
    col = pow(col, vec3<f32>(1.0 / 2.2));

    textureStore(writeTexture, id.xy, vec4<f32>(col, 1.0));
}
