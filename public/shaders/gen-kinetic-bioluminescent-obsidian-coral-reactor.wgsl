// ----------------------------------------------------------------
// Kinetic Bioluminescent Obsidian-Coral Reactor
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Color Shift, .y = Coral Density, .z = Fluid Speed, .w = Glow Intensity
  ripples: array<vec4<f32>, 50>,
};

const MAX_STEPS: i32 = 90;
const MAX_DIST: f32 = 40.0;
const SURF_DIST: f32 = 0.005;

fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Custom smooth min for organic blending
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// 3D Simplex noise based on Morgan McGuire's snippet
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.6))
    );
    return fract(sin(q) * 43758.5453) * 2.0 - 1.0;
}

fn snoise(p: vec3<f32>) -> f32 {
    let i = floor(p + dot(p, vec3<f32>(1.0 / 3.0)));
    let x0 = p - i + dot(i, vec3<f32>(1.0 / 6.0));
    var g = step(vec3<f32>(0.0), x0.yzx - x0.xyz);
    let l = 1.0 - g;
    let i1 = min(g.xyz, l.zxy);
    let i2 = max(g.xyz, l.zxy);
    let x1 = x0 - i1 + 1.0 / 6.0;
    let x2 = x0 - i2 + 2.0 / 6.0;
    let x3 = x0 - 1.0 + 3.0 / 6.0;
    var n = max(0.6 - vec4<f32>(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), vec4<f32>(0.0));
    n = n * n * n * n;
    return 42.0 * dot(n, vec4<f32>(dot(hash3(i), x0), dot(hash3(i + i1), x1), dot(hash3(i + i2), x2), dot(hash3(i + 1.0), x3)));
}

// Distance to an infinite hollow grid (Menger-like)
fn sdLattice(p: vec3<f32>) -> f32 {
    var q = abs(p) - 1.0;
    var res = min(max(q.x, q.y), min(max(q.y, q.z), max(q.z, q.x)));
    // Repeat space
    let c = vec3<f32>(4.0);
    var p2 = p - c * round(p/c);
    var q2 = abs(p2) - 1.2;
    let box = max(q2.x, max(q2.y, q2.z));

    // Cross intersection
    let cr = min(max(abs(p2.x), abs(p2.y)), min(max(abs(p2.y), abs(p2.z)), max(abs(p2.z), abs(p2.x)))) - 0.5;
    return max(box, -cr);
}

struct MapResult {
    dist: f32,
    mat_id: f32, // 0.0 for obsidian, 1.0 for coral
    emission: f32
}

fn map(p_in: vec3<f32>, time: f32, bass: f32) -> MapResult {
    var p = p_in;

    // Twist space based on time
    let tw = rot2D(p.z * 0.05 * sin(time * 0.2));
    var p_tw = vec3<f32>(tw * p.xy, p.z);

    // 1. Brutalist Obsidian Lattice
    let obsidian_d = sdLattice(p_tw);

    // 2. Organic Bioluminescent Coral
    let density = u.zoom_params.y;
    let flow_speed = u.zoom_params.z;

    // Flowing displacement
    let noise_val = snoise(p_tw * density + vec3<f32>(0.0, 0.0, -time * flow_speed))
                  + 0.5 * snoise(p_tw * density * 2.0 + vec3<f32>(time * flow_speed * 0.5, 0.0, 0.0));

    // Core of the coral grows inside the lattice, pulsing with audio bass
    let coral_base = length(p_tw.xy) - (1.5 + bass * 0.5);
    let coral_d = coral_base - noise_val * 0.8;

    // Blend them
    let k = 0.8; // blend factor
    let h = clamp(0.5 + 0.5 * (obsidian_d - coral_d) / k, 0.0, 1.0);
    let final_d = mix(obsidian_d, coral_d, h) - k * h * (1.0 - h);

    return MapResult(final_d, h, h * max(0.0, -coral_d + 0.2));
}

fn getNormal(p: vec3<f32>, time: f32, bass: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, time, bass).dist - map(p - e.xyy, time, bass).dist,
        map(p + e.yxy, time, bass).dist - map(p - e.yxy, time, bass).dist,
        map(p + e.yyx, time, bass).dist - map(p - e.yyx, time, bass).dist
    ));
}

// Cosine palette for coral colors
fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.0, 0.10, 0.20); // Cyan to Magenta shift base
    return a + b * cos(6.28318 * (c * t + d + u.zoom_params.x));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let coords = vec2<i32>(global_id.xy);
    if (coords.x >= i32(dims.x) || coords.y >= i32(dims.y)) { return; }

    let base_uv = vec2<f32>(coords) / vec2<f32>(dims);
    var uv = base_uv * 2.0 - 1.0;
    let aspect = f32(dims.x) / f32(dims.y);
    uv.x *= aspect;

    let time = u.config.x;

    // Audio Reactivity
    let bass = extraBuffer[0];
    let treble = extraBuffer[100];

    // Mouse Interaction
    var mouse = u.zoom_config.yz * 2.0 - 1.0;
    mouse.x *= aspect;
    mouse.y *= -1.0;

    // Camera Setup
    let cam_speed = 2.0;
    var ro = vec3<f32>(0.0, 0.0, time * cam_speed);

    // Gentle camera sway
    ro.x += sin(time * 0.4) * 0.5;
    ro.y += cos(time * 0.3) * 0.5;

    var rd = normalize(vec3<f32>(uv, 1.2));

    // Look around with mouse
    if (u.zoom_config.w > 0.0) {
        let rm_y = rot2D(-mouse.x * 1.5);
        let rm_x = rot2D(mouse.y * 1.5);
        var r_rd = vec3<f32>(rm_y * rd.xz, rd.y).xzy;
        r_rd = vec3<f32>(r_rd.x, rm_x * r_rd.yz);
        rd = r_rd;
    }

    // Raymarching
    var dO = 0.0;
    var p = ro;
    var res: MapResult;
    var steps_taken = 0;

    for (var i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * dO;
        res = map(p, time, bass);
        if (abs(res.dist) < SURF_DIST || dO > MAX_DIST) {
            steps_taken = i;
            break;
        }
        dO += res.dist * 0.8; // 0.8 relaxation for safe stepping
    }

    // Background color
    var col = vec3<f32>(0.0);

    if (dO < MAX_DIST) {
        var n = getNormal(p, time, bass);

        // Mouse point light (lantern effect)
        var lantern_pos = ro + vec3<f32>(mouse.x * 2.0, mouse.y * 2.0, 3.0);
        let lantern_dir = normalize(lantern_pos - p);
        let lantern_dist = length(lantern_pos - p);

        // Micro-facet perturbation near mouse for obsidian
        if (res.mat_id < 0.5 && lantern_dist < 5.0) {
             let perturb = snoise(p * 20.0 + treble * 5.0) * 0.05;
             n = normalize(n + vec3<f32>(perturb));
        }

        // Lighting calculation
        let l1_dir = normalize(vec3<f32>(1.0, 1.0, -1.0)); // Main directional
        var dif = max(dot(n, l1_dir), 0.0);

        // Specular for Obsidian
        let view_dir = normalize(ro - p);
        let half_vec = normalize(l1_dir + view_dir);
        var spec = pow(max(dot(n, half_vec), 0.0), 128.0) * 2.0;

        // Mouse Lantern light
        let lan_dif = max(dot(n, lantern_dir), 0.0) / (1.0 + lantern_dist * lantern_dist * 0.2);
        let lan_half = normalize(lantern_dir + view_dir);
        let lan_spec = pow(max(dot(n, lan_half), 0.0), 64.0) * lan_dif;

        // Base shading (obsidian is black, highly reflective)
        var mat_col = vec3<f32>(0.01) * dif + vec3<f32>(spec);
        mat_col += vec3<f32>(1.0, 0.9, 0.8) * (lan_dif + lan_spec) * 2.0 * u.zoom_config.w;

        // Emission for Coral
        let glow_intensity = u.zoom_params.w * 2.0;
        let em_col = palette(res.mat_id * 2.0 + p.z * 0.1 - time * 0.5) * res.emission * glow_intensity * (1.0 + bass);

        // Mix material and emission based on mat_id (h)
        col = mix(mat_col, em_col, res.mat_id);

        // Rim light
        let rim = 1.0 - max(dot(view_dir, n), 0.0);
        col += vec3<f32>(0.1, 0.3, 0.5) * smoothstep(0.6, 1.0, rim) * res.mat_id;

    }

    // Depth fog
    let fog = 1.0 - exp(-dO * 0.05);
    col = mix(col, vec3<f32>(0.0, 0.01, 0.02), fog);

    // Add some global glow based on steps
    col += palette(time * 0.1) * f32(steps_taken) * 0.002 * bass;

    // Tonemapping
    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(0.4545)); // Gamma correction

    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
}