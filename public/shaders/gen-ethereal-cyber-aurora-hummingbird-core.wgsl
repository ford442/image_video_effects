// ----------------------------------------------------------------
// Ethereal Cyber-Aurora Hummingbird-Core
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Flutter Speed, y=Aura Intensity, z=Pollen Density, w=Aberration
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.001;

// --- Helper Functions ---
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// 3D Noise for volumetric pollen
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(q) * 43758.5453123);
}

fn noise3(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f2 = f * f * (vec3<f32>(3.0) - vec3<f32>(2.0) * f);

    let n = p.x + p.y * 57.0 + 113.0 * p.z;

    let res = mix(
        mix(
            mix(fract(sin(n + 0.0)*43758.5453), fract(sin(n + 1.0)*43758.5453), f2.x),
            mix(fract(sin(n + 57.0)*43758.5453), fract(sin(n + 58.0)*43758.5453), f2.x),
            f2.y
        ),
        mix(
            mix(fract(sin(n + 113.0)*43758.5453), fract(sin(n + 114.0)*43758.5453), f2.x),
            mix(fract(sin(n + 170.0)*43758.5453), fract(sin(n + 171.0)*43758.5453), f2.x),
            f2.y
        ),
        f2.z
    );
    return res;
}

// Simplex-like noise for auroral texture
fn simplex(p: vec3<f32>) -> f32 {
    return noise3(p * 2.0) * 0.5 + noise3(p * 4.0) * 0.25 + noise3(p * 8.0) * 0.125;
}

// SDF primitives
fn sdEllipsoid(p: vec3<f32>, r: vec3<f32>) -> f32 {
    let k0 = length(p / r);
    let k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / k1;
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let d = abs(p) - b;
    return length(max(d, vec3<f32>(0.0))) + min(max(d.x, max(d.y, d.z)), 0.0);
}

// --- Map Function ---
fn map(p_in: vec3<f32>, t: f32, audio: f32, flutter: f32) -> vec2<f32> {
    var p = p_in;
    var d = MAX_DIST;
    var mat_id = 0.0;

    // Temporal high-frequency distortion for wings
    let wing_time = t * flutter * 10.0;

    // Core body (cyber-organic SDF)
    var p_body = p;
    // Low frequency warp
    p_body.y += sin(p_body.x * 2.0 + t) * 0.1;
    let body_base = sdEllipsoid(p_body, vec3<f32>(0.4, 0.2, 0.6));
    let head = sdEllipsoid(p_body - vec3<f32>(0.0, 0.2, 0.7), vec3<f32>(0.2, 0.15, 0.25));
    let beak = sdEllipsoid(p_body - vec3<f32>(0.0, 0.2, 1.1), vec3<f32>(0.02, 0.02, 0.3));

    var body = smin(body_base, head, 0.2);
    body = smin(body, beak, 0.1);

    // Add auroral plasma texture displacement
    body -= simplex(p_body * 5.0 + vec3<f32>(t, 0.0, t)) * 0.05 * audio;

    // Wings
    var p_wing = p;
    p_wing.x = abs(p_wing.x) - 0.4; // mirror

    // Flapping rotation
    let flap_angle = sin(wing_time) * 1.5;

    // Manual rotation matrices instead of mat3x3 components for rotZ
    let rot_flap = rot(flap_angle);
    p_wing.xy = rot_flap * p_wing.xy;

    let rot_pitch = rot(0.5);
    p_wing.zy = rot_pitch * p_wing.zy;

    // High frequency displacement for fractal light trails
    let wing_disp = sin(p_wing.x * 20.0 + wing_time) * sin(p_wing.z * 15.0 - wing_time) * 0.05;

    let wing = sdBox(p_wing - vec3<f32>(0.5, 0.0, 0.0), vec3<f32>(0.6, 0.01, 0.3)) + wing_disp;

    // Chrono-flower gravity well (Radial domain repetition)
    var p_flower = p;
    p_flower.y += 1.0;

    let petals = 8.0;
    let angle = atan2(p_flower.z, p_flower.x);
    let r = length(p_flower.xz);
    let local_angle = (angle * petals / PI) - t;

    let flower_disp = sin(r * 5.0 - t * 2.0) * 0.2 * audio;
    let flower = sdEllipsoid(vec3<f32>(r - 1.5, p_flower.y, local_angle), vec3<f32>(0.5, 0.1, 0.2)) + flower_disp;

    // Combine
    if (body < d) {
        d = body;
        mat_id = 1.0; // Body
    }
    if (wing < d) {
        d = wing;
        mat_id = 2.0; // Wings
    }
    if (flower < d) {
        d = flower;
        mat_id = 3.0; // Flower
    }

    return vec2<f32>(d, mat_id);
}

fn calcNormal(p: vec3<f32>, t: f32, audio: f32, flutter: f32) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize(e.xyy * map(p + e.xyy, t, audio, flutter).x +
                     e.yyx * map(p + e.yyx, t, audio, flutter).x +
                     e.yxy * map(p + e.yxy, t, audio, flutter).x +
                     e.xxx * map(p + e.xxx, t, audio, flutter).x);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let uv = (vec2<f32>(id.xy) - 0.5 * res) / res.y;

    if (f32(id.x) >= res.x || f32(id.y) >= res.y) {
        return;
    }

    let t = u.config.x;
    let audio = u.config.y * 2.0 + 1.0;

    // Sliders
    let flutter = u.zoom_params.x; // Flutter Speed (1.0, 0.1, 5.0)
    let aura_intensity = u.zoom_params.y; // Aura Intensity (0.5, 0.0, 2.0)
    let pollen_density = u.zoom_params.z; // Pollen Density (1.0, 0.0, 3.0)
    let aberration = u.zoom_params.w; // Aberration (0.2, 0.0, 1.0)

    // Mouse Interaction
    var mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    if (length(mouse) < 0.01) {
        mouse = vec2<f32>(0.5, 0.5);
    }
    let m_uv = (mouse - 0.5) * PI * 2.0;

    // Camera setup
    var ro = vec3<f32>(0.0, 1.0, -4.0);

    // Mouse rotation
    let rot_x = rot(m_uv.x);
    ro.xz = rot_x * ro.xz;

    let rot_y = rot(m_uv.y);
    ro.yz = rot_y * ro.yz;

    var rd = normalize(vec3<f32>(uv, 1.0));
    rd.xz = rot_x * rd.xz;
    rd.yz = rot_y * rd.yz;

    // Aberration Ray Offsets
    var rd_r = rd;
    var rd_b = rd;
    let ab_amount = aberration * 0.02 * audio;
    rd_r.x += ab_amount;
    rd_b.x -= ab_amount;

    // Render Function
    var final_color = vec3<f32>(0.0);

    let rds = array<vec3<f32>, 3>(rd_r, rd, rd_b);
    let colors = array<vec3<f32>, 3>(vec3<f32>(1.0, 0.0, 0.0), vec3<f32>(0.0, 1.0, 0.0), vec3<f32>(0.0, 0.0, 1.0));

    for (var i = 0; i < 3; i++) {
        let cur_rd = rds[i];
        var dO = 0.0;
        var p = ro;
        var hit = false;
        var m = 0.0;

        var glow = 0.0;

        for (var i_step = 0; i_step < MAX_STEPS; i_step++) {
            let res_map = map(p, t, audio, flutter);
            let d = res_map.x;
            m = res_map.y;

            // Volumetric accumulation (Auroral bloom)
            if (d < 0.5) {
               glow += 0.01 / (1.0 + d * d * 50.0);
            }

            if (d < SURF_DIST) {
                hit = true;
                break;
            }
            if (dO > MAX_DIST) {
                break;
            }

            p += cur_rd * d;
            dO += d;
        }

        var col = vec3<f32>(0.0);

        if (hit) {
            let n = calcNormal(p, t, audio, flutter);
            let l = normalize(vec3<f32>(1.0, 2.0, -1.0));
            let diff = max(dot(n, l), 0.0);
            let fresnel = pow(1.0 - max(dot(n, -cur_rd), 0.0), 3.0);

            if (m == 1.0) {
                // Body: Deep cyan/magenta with auroral emission
                col = mix(vec3<f32>(0.0, 0.8, 1.0), vec3<f32>(1.0, 0.0, 0.8), sin(p.y * 5.0 + t) * 0.5 + 0.5);
                col *= diff;
                col += vec3<f32>(0.0, 1.0, 1.0) * fresnel * aura_intensity;
            } else if (m == 2.0) {
                // Wings: Refractive / Plasma trails
                col = vec3<f32>(1.0, 0.9, 0.1) * fresnel * 2.0;
                col += vec3<f32>(0.5, 0.1, 1.0) * sin(p.z * 10.0 - t * flutter * 5.0) * aura_intensity;
            } else if (m == 3.0) {
                // Chrono-flower
                col = vec3<f32>(0.1, 0.0, 0.2) * diff;
                col += vec3<f32>(0.8, 0.0, 1.0) * fresnel;
            }
        }

        // Background / Void Void
        col += vec3<f32>(0.0, 0.05, 0.1) * (1.0 - exp(-dO * 0.05));

        // Apply glow
        col += vec3<f32>(0.0, 0.5, 1.0) * glow * aura_intensity;

        // Volumetric Pollen
        if (pollen_density > 0.0) {
            let p_pollen = ro + cur_rd * min(dO, MAX_DIST) * 0.5;
            let n_pollen = noise3(p_pollen * 5.0 + t * 0.5);
            let p_mask = smoothstep(0.7, 1.0, n_pollen);
            col += vec3<f32>(1.0, 1.0, 0.5) * p_mask * pollen_density * audio;
        }

        final_color += col * colors[i];
    }

    textureStore(writeTexture, id.xy, vec4<f32>(final_color, 1.0));
}
