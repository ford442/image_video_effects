// ----------------------------------------------------------------
// Sentient Cyber-Chrono Void-Serpent
// Category: generative
// ----------------------------------------------------------------
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

const PI: f32 = 3.14159265359;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn hash33(p: vec3<f32>) -> vec3<f32> {
    var p2 = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.6))
    );
    return fract(sin(p2) * 43758.5453123);
}

fn noise3D(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    let n000 = dot(hash33(i + vec3<f32>(0.0, 0.0, 0.0)), f - vec3<f32>(0.0, 0.0, 0.0));
    let n100 = dot(hash33(i + vec3<f32>(1.0, 0.0, 0.0)), f - vec3<f32>(1.0, 0.0, 0.0));
    let n010 = dot(hash33(i + vec3<f32>(0.0, 1.0, 0.0)), f - vec3<f32>(0.0, 1.0, 0.0));
    let n110 = dot(hash33(i + vec3<f32>(1.0, 1.0, 0.0)), f - vec3<f32>(1.0, 1.0, 0.0));
    let n001 = dot(hash33(i + vec3<f32>(0.0, 0.0, 1.0)), f - vec3<f32>(0.0, 0.0, 1.0));
    let n101 = dot(hash33(i + vec3<f32>(1.0, 0.0, 1.0)), f - vec3<f32>(1.0, 0.0, 1.0));
    let n011 = dot(hash33(i + vec3<f32>(0.0, 1.0, 1.0)), f - vec3<f32>(0.0, 1.0, 1.0));
    let n111 = dot(hash33(i + vec3<f32>(1.0, 1.0, 1.0)), f - vec3<f32>(1.0, 1.0, 1.0));

    let nx00 = mix(n000, n100, u.x);
    let nx10 = mix(n010, n110, u.x);
    let nx01 = mix(n001, n101, u.x);
    let nx11 = mix(n011, n111, u.x);

    let nxy0 = mix(nx00, nx10, u.y);
    let nxy1 = mix(nx01, nx11, u.y);

    return mix(nxy0, nxy1, u.z);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

fn map(pos: vec3<f32>) -> vec2<f32> {
    var p = pos;
    let t = u.config.x * u.zoom_params.x * 0.5;

    let mouse = u.zoom_config.yz * 2.0 - 1.0;

    let mouse_pos = vec3<f32>(mouse.x * 3.0, mouse.y * 3.0, 0.0);
    let dist_to_mouse = length(p - mouse_pos);
    let pull = smoothstep(2.0, 0.0, dist_to_mouse);
    p = mix(p, mouse_pos, pull * 0.5);

    let bass = plasmaBuffer[0].x * u.zoom_params.y;

    var q = p;
    let serpent_freq = 0.5;
    let serpent_amp = 1.5;

    q.x = q.x + sin(q.z * serpent_freq + t) * serpent_amp;
    q.y = q.y + cos(q.z * serpent_freq * 0.8 + t * 1.2) * serpent_amp;

    let scale_size = 0.5;
    var scale_p = q;
    scale_p.z = (fract(scale_p.z / scale_size + 0.5) - 0.5) * scale_size;
    let scale_rot = rot(q.z * 2.0);
    scale_p = vec3<f32>(scale_rot[0].x * scale_p.x + scale_rot[1].x * scale_p.y,
                        scale_rot[0].y * scale_p.x + scale_rot[1].y * scale_p.y,
                        scale_p.z);

    let fracture = u.zoom_params.w;
    let disp = noise3D(q * 5.0 + t) * 0.1 * fracture;

    let serpent_thickness = 0.4 + bass * 0.3;
    let core_dist = length(q.xy) - serpent_thickness + disp;

    let scale_dist = length(scale_p) - 0.25 - disp;

    let serpent_dist = smin(core_dist, scale_dist, 0.2);

    var void_p = p;
    void_p.z = void_p.z + t * 2.0;
    let void_noise = noise3D(void_p * 2.0) * 0.5 + noise3D(void_p * 4.0) * 0.25;
    let void_dist = -void_p.y + void_noise * u.zoom_params.z * 2.0;

    var res = vec2<f32>(serpent_dist, 1.0);

    if (void_dist < res.x) {
        res = vec2<f32>(void_dist, 2.0);
    }

    return res;
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + vec3<f32>(e.x, e.y, e.y)).x - map(p - vec3<f32>(e.x, e.y, e.y)).x,
        map(p + vec3<f32>(e.y, e.x, e.y)).x - map(p - vec3<f32>(e.y, e.x, e.y)).x,
        map(p + vec3<f32>(e.y, e.y, e.x)).x - map(p - vec3<f32>(e.y, e.y, e.x)).x
    ));
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(2.0 * PI * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let tex_coords = vec2<i32>(id.xy);
    let dimensions = textureDimensions(writeTexture);

    if (tex_coords.x >= dimensions.x || tex_coords.y >= dimensions.y) {
        return;
    }

    let resolution = vec2<f32>(f32(dimensions.x), f32(dimensions.y));
    var uv = (vec2<f32>(tex_coords) - 0.5 * resolution) / resolution.y;

    let t = u.config.x;
    let bass = plasmaBuffer[0].x * u.zoom_params.y;

    var ro = vec3<f32>(0.0, 0.0, -4.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    let mouse = u.zoom_config.yz * 2.0 - 1.0;
    let cam_rot_y = rot(mouse.x * PI);
    let cam_rot_x = rot(-mouse.y * PI * 0.5);

    ro = vec3<f32>(cam_rot_y[0].x * ro.x + cam_rot_y[1].x * ro.z, ro.y, cam_rot_y[0].y * ro.x + cam_rot_y[1].y * ro.z);
    rd = vec3<f32>(cam_rot_y[0].x * rd.x + cam_rot_y[1].x * rd.z, rd.y, cam_rot_y[0].y * rd.x + cam_rot_y[1].y * rd.z);

    ro = vec3<f32>(ro.x, cam_rot_x[0].x * ro.y + cam_rot_x[1].x * ro.z, cam_rot_x[0].y * ro.y + cam_rot_x[1].y * ro.z);
    rd = vec3<f32>(rd.x, cam_rot_x[0].x * rd.y + cam_rot_x[1].x * rd.z, cam_rot_x[0].y * rd.y + cam_rot_x[1].y * rd.z);

    var dO = 0.0;
    var p = vec3<f32>(0.0);
    var hit_id = 0.0;
    var glow = 0.0;
    var steps = 0.0;

    for (var i = 0; i < 100; i++) {
        p = ro + rd * dO;
        let dS = map(p);

        if (dS.x < 0.001) {
            hit_id = dS.y;
            break;
        }
        if (dO > 20.0) {
            break;
        }

        dO += dS.x;

        if (dS.y == 1.0) {
             glow += 0.01 / (0.01 + abs(dS.x)) * (0.5 + bass * 0.5);
        }
        steps += 1.0;
    }

    var col = vec3<f32>(0.0);

    if (dO < 20.0) {
        let n = calcNormal(p);
        let l = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, l), 0.0);
        let amb = 0.1;
        let spec = pow(max(dot(reflect(rd, n), l), 0.0), 32.0);

        if (hit_id == 1.0) {
            let base_col = vec3<f32>(0.05, 0.05, 0.08);
            let spine_col = palette(p.z * 0.1 - t * u.zoom_params.x,
                                    vec3<f32>(0.5, 0.5, 0.5),
                                    vec3<f32>(0.5, 0.5, 0.5),
                                    vec3<f32>(1.0, 1.0, 1.0),
                                    vec3<f32>(0.0, 0.33, 0.67));

            col = base_col * (diff + amb) + spec;
            col += spine_col * glow * u.zoom_params.y;

        } else if (hit_id == 2.0) {
            let void_col = vec3<f32>(0.1, 0.02, 0.2) * (diff + amb);
            col = void_col;
        }
    }

    let fog = 1.0 - exp(-0.05 * dO);
    col = mix(col, vec3<f32>(0.02, 0.0, 0.05) + vec3<f32>(0.1, 0.05, 0.2) * glow * 0.2 * u.zoom_params.z, fog);

    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    col = clamp((col * (a * col + vec3<f32>(b))) / (col * (c * col + vec3<f32>(d)) + vec3<f32>(e)), vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, tex_coords, vec4<f32>(col, 1.0));
}
