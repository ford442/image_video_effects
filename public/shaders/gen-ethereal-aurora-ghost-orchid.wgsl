// ----------------------------------------------------------------
// Ethereal-Aurora Ghost-Orchid
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

fn hash1(n: f32) -> f32 {
    return fract(sin(n) * 43758.5453123);
}

fn smax(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (a - b) / k, 0.0, 1.0);
    return mix(b, a, h) + k * h * (1.0 - h);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn rot2(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn rotY(angle: f32) -> mat3x3<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return mat3x3<f32>(
        c, 0.0, s,
        0.0, 1.0, 0.0,
        -s, 0.0, c
    );
}

fn snoise(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f_smooth = f * f * (vec3<f32>(3.0) - vec2<f32>(2.0).xxx * f);
    let n = p.x + p.y * 157.0 + p.z * 113.0;

    let v1 = mix(hash1(n + 0.0), hash1(n + 1.0), f_smooth.x);
    let v2 = mix(hash1(n + 157.0), hash1(n + 158.0), f_smooth.x);
    let v3 = mix(hash1(n + 113.0), hash1(n + 114.0), f_smooth.x);
    let v4 = mix(hash1(n + 270.0), hash1(n + 271.0), f_smooth.x);

    let res1 = mix(v1, v2, f_smooth.y);
    let res2 = mix(v3, v4, f_smooth.y);
    return mix(res1, res2, f_smooth.z) * 2.0 - 1.0;
}

fn map(p_in: vec3<f32>, time: f32, audio_react: f32, mouse_pos: vec2<f32>) -> f32 {
    var p = p_in;

    // Mouse Interaction: Gravity well
    let mouse_world = vec3<f32>((mouse_pos.x - 0.5) * 5.0, (mouse_pos.y - 0.5) * -5.0, 0.0);
    let dist_mouse = length(p.xy - mouse_world.xy);
    let pull = smoothstep(3.0, 0.0, dist_mouse);
    p.x -= pull * (mouse_world.x - p.x) * 0.5;
    p.y -= pull * (mouse_world.y - p.y) * 0.5;

    // Stem
    let stem_d = length(p.xy) - 0.05 + p.z * 0.01;

    // Petals
    var petal_d = 100.0;
    let num_petals = 5.0;
    for (var i = 0.0; i < num_petals; i += 1.0) {
        let angle = (i / num_petals) * PI * 2.0 + time * 0.2;
        var q = p;
        let q_xy = rot2(angle) * q.xy;
        q.x = q_xy.x;
        q.y = q_xy.y;

        q.y -= 0.5; // Offset from center

        // Bend
        q.z -= q.y * q.y * 0.5;

        // Unfurl with audio
        q.x += sin(q.y * 5.0 + time) * 0.2 * audio_react;

        let d = length(vec3<f32>(q.x, smax(0.0, abs(q.y) - 1.5, 0.2), q.z)) - 0.05 - smax(0.0, 1.0 - abs(q.y), 0.5) * 0.1;
        petal_d = smin(petal_d, d, 0.2);
    }

    // Core Stamen
    var core_d = length(p) - 0.2 - audio_react * 0.1;

    // Combine and add noise displacement
    var d = smin(stem_d, petal_d, 0.5);
    d = smin(d, core_d, 0.3);

    let disp = snoise(p * 2.0 + vec3<f32>(time * 0.5, time * 0.2, time * 0.1)) * 0.1;

    return d + disp;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));

    if (fragCoord.x >= res.x || fragCoord.y >= res.y) {
        return;
    }

    let uv = (fragCoord - 0.5 * res) / res.y;
    let time = u.config.x;
    let audio = u.config.y;
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);

    let petal_complex = u.zoom_params.x; // Petal Complexity
    let aurora_int = u.zoom_params.y; // Aurora Intensity
    let audio_react = u.zoom_params.z * audio; // Audio Reactivity
    let pollen_dens = u.zoom_params.w; // Pollen Density

    var ro = vec3<f32>(0.0, 0.0, -5.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    ro = rotY(time * 0.1) * ro;
    rd = rotY(time * 0.1) * rd;

    var t = 0.0;
    var d = 0.0;
    var col = vec3<f32>(0.0);
    var emission = vec3<f32>(0.0);

    // Raymarching
    for (var i = 0; i < 64; i += 1) {
        let p = ro + rd * t;
        d = map(p, time, audio_react, mouse);

        if (d < 0.01) {
            // Volumetric aurora emission
            let noise_val = snoise(p * petal_complex + vec3<f32>(0.0, -time, 0.0));
            let aurora_col = mix(vec3<f32>(0.0, 0.8, 1.0), vec3<f32>(0.8, 0.0, 1.0), noise_val * 0.5 + 0.5);
            emission += aurora_col * 0.05 * aurora_int / (1.0 + abs(d) * 10.0);
            t += 0.02; // Step inside
        } else {
            t += d;
        }

        if (t > 10.0) { break; }
    }

    // Add pollen
    let pollen_val = snoise(vec3<f32>(uv * 20.0, time));
    if (pollen_val > 0.8) {
        let spark = pow(pollen_val, 10.0) * pollen_dens;
        emission += vec3<f32>(1.0, 0.8, 0.2) * spark;
    }

    col += emission;

    // Bloom / ACES
    col = col / (col + vec3<f32>(1.0));
    col = pow(col, vec3<f32>(1.0 / 2.2));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}