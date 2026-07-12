// ----------------------------------------------------------------
// Chrono-Kitsune Prism Weaver
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Prism Hue Shift, y=Tail Count, z=Weave Tightness, w=Chrono Echo
    ripples: array<vec4<f32>, 50>,
};

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

const PI = 3.14159265359;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += vec3<f32>(dot(q, q.yxz + vec3<f32>(33.33)));
    return fract((q.xxy + q.yxx) * q.zyx);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn map(p: vec3<f32>, time: f32, tail_count: f32, weave_tightness: f32) -> vec2<f32> {
    var d = 1000.0;
    var mat = 0.0;

    // Kitsune central body
    let body_p = p - vec3<f32>(0.0, 0.0, 5.0);
    var d_body = length(body_p) - 1.2;
    d_body += 0.1 * sin(body_p.x * 10.0 + time) * sin(body_p.y * 10.0 + time) * sin(body_p.z * 10.0 + time);

    d = min(d, d_body);
    if (d == d_body) { mat = 1.0; }

    // Prismatic Tails
    let count = clamp(floor(tail_count * 9.0), 3.0, 9.0);
    var d_tails = 1000.0;
    for (var i = 0.0; i < count; i += 1.0) {
        let phase = i * PI * 2.0 / count;
        var tp = p;
        tp.z -= 6.0;

        let spread = rot(phase);
        let rotated_xy = spread * tp.xy;
        tp = vec3<f32>(rotated_xy.x, rotated_xy.y, tp.z);

        tp.x -= 0.8;

        let wave = sin(tp.z * weave_tightness * 0.5 - time * 2.0 + phase) * 0.5;
        tp.x += wave;

        let d_cyl = length(tp.xy) - 0.2 - tp.z * 0.03;
        let z_bounds = max(-tp.z, tp.z - 20.0);
        let tail_dist = max(d_cyl, z_bounds);

        d_tails = smin(d_tails, tail_dist, 0.4);
    }

    d = smin(d, d_tails, 0.6);
    if (d == d_tails || d < d_body) { mat = 2.0; }

    return vec2<f32>(d, mat);
}

fn calcNormal(p: vec3<f32>, time: f32, tail_count: f32, weave_tightness: f32) -> vec3<f32> {
    let e = vec2<f32>(0.01, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, time, tail_count, weave_tightness).x - map(p - e.xyy, time, tail_count, weave_tightness).x,
        map(p + e.yxy, time, tail_count, weave_tightness).x - map(p - e.yxy, time, tail_count, weave_tightness).x,
        map(p + e.yyx, time, tail_count, weave_tightness).x - map(p - e.yyx, time, tail_count, weave_tightness).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dim = vec2<f32>(u.config.z, u.config.w);
    let coord = vec2<f32>(f32(id.x), f32(id.y));

    if (id.x >= u32(dim.x) || id.y >= u32(dim.y)) {
        return;
    }

    let uv = (coord - 0.5 * dim) / dim.y;
    let time = u.config.x;
    let audio = u.config.y;

    // Mouse coordinates mappings
    var mpos = vec2<f32>(u.zoom_config.y, u.zoom_config.z) / dim * 2.0 - vec2<f32>(1.0);
    mpos.y = -(mpos.y - 0.5) * 2.0;
    if (length(mpos) > 1.5) { mpos = vec2<f32>(0.0); }

    let p_prism_hue = u.zoom_params.x;
    let p_tail_count = u.zoom_params.y;
    let p_weave = u.zoom_params.z;
    let p_echo = u.zoom_params.w;

    // Ray setup
    var ro = vec3<f32>(0.0, 0.0, -2.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Mouse spatial bend
    let m_rot_x = rot(mpos.x * 2.0);
    let m_rot_y = rot(mpos.y * 2.0);

    let rd_xy = m_rot_x * rd.xz;
    rd.x = rd_xy.x;
    rd.z = rd_xy.y;

    let rd_yz = m_rot_y * rd.yz;
    rd.y = rd_yz.x;
    rd.z = rd_yz.y;

    var t = 0.0;
    var d = 0.0;
    var m = 0.0;
    var p = ro;

    var glow = 0.0;

    // Raymarching
    for (var i = 0; i < 80; i++) {
        p = ro + rd * t;
        let res = map(p, time, p_tail_count, 1.0 + p_weave * 3.0);
        d = res.x;
        m = res.y;

        if (m == 2.0) {
            glow += 0.02 / (1.0 + d*d*50.0);
        }

        if (d < 0.01) { break; }
        t += d * 0.7;
        if (t > 40.0) { break; }
    }

    var col = vec3<f32>(0.0);

    if (t < 40.0) {
        let n = calcNormal(p, time, p_tail_count, 1.0 + p_weave * 3.0);
        let l = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, l), 0.0);
        let view = normalize(ro - p);
        let fre = pow(1.0 - max(dot(n, view), 0.0), 4.0);

        let hue = p_prism_hue + t * 0.1 - time * 0.5;
        let base_col = vec3<f32>(0.5 + 0.5 * sin(hue * 6.28 + vec3<f32>(0.0, 2.0, 4.0)));

        if (m == 1.0) {
            // Kitsune Body
            col = mix(base_col * diff, vec3<f32>(1.0, 0.8, 1.0), fre);
        } else if (m == 2.0) {
            // Tails
            col = base_col * (diff + fre * 2.0) + vec3<f32>(glow * audio);
        }
    }

    // Add volumetric glow and space dust
    let hue_glow = p_prism_hue - time * 0.2;
    let glow_col = vec3<f32>(0.5 + 0.5 * sin(hue_glow * 6.28 + vec3<f32>(0.0, 2.0, 4.0)));
    col += glow_col * glow * 1.5;

    // Tone map
    col = col / (1.0 + col);

    // Temporal Ping Pong Feedback
    let tex_coord = coord / dim;

    // Displace previous frame based on center and temporal warp
    let center_dir = normalize(tex_coord - 0.5);
    let dist_center = length(tex_coord - 0.5);
    let displacement = center_dir * sin(dist_center * 20.0 - time * 5.0) * 0.005 * p_echo;

    let prev_coord = clamp(tex_coord + displacement, vec2<f32>(0.0), vec2<f32>(1.0));
    let prev_frame = textureSampleLevel(dataTextureC, u_sampler, prev_coord, 0.0).xyz;

    // Prismatic color shift on the feedback
    let shifted_prev = prev_frame * vec3<f32>(0.99, 0.95, 0.9);
    col = mix(col, shifted_prev, 0.85 * p_echo * (1.0 - audio * 0.3));

    let final_alpha = 1.0;

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, final_alpha));
    textureStore(dataTextureA, vec2<i32>(id.xy), vec4<f32>(col, final_alpha));
}
