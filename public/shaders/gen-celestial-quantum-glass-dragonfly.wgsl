// ----------------------------------------------------------------
// Celestial Quantum-Glass Dragonfly
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
    zoom_params: vec4<f32>,  // x=Wing Frequency, y=Fractal Density, z=Refraction Index, w=Glow Intensity
    ripples: array<vec4<f32>, 50>,
};

// --- CORE UTILITIES ---
fn rot2d(a: f32) -> mat2x2<f32> {
    let s = sin(a); let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn rot3x(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}

fn rot3y(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}

fn rot3z(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0);
}

// Noise / Hash
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

fn noise3(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f_pow = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(
            mix(dot(hash3(p + vec3<f32>(0.0,0.0,0.0)), f - vec3<f32>(0.0,0.0,0.0)),
                dot(hash3(p + vec3<f32>(1.0,0.0,0.0)), f - vec3<f32>(1.0,0.0,0.0)), f_pow.x),
            mix(dot(hash3(p + vec3<f32>(0.0,1.0,0.0)), f - vec3<f32>(0.0,1.0,0.0)),
                dot(hash3(p + vec3<f32>(1.0,1.0,0.0)), f - vec3<f32>(1.0,1.0,0.0)), f_pow.x), f_pow.y),
        mix(
            mix(dot(hash3(p + vec3<f32>(0.0,0.0,1.0)), f - vec3<f32>(0.0,0.0,1.0)),
                dot(hash3(p + vec3<f32>(1.0,0.0,1.0)), f - vec3<f32>(1.0,0.0,1.0)), f_pow.x),
            mix(dot(hash3(p + vec3<f32>(0.0,1.0,1.0)), f - vec3<f32>(0.0,1.0,1.0)),
                dot(hash3(p + vec3<f32>(1.0,1.0,1.0)), f - vec3<f32>(1.0,1.0,1.0)), f_pow.x), f_pow.y), f_pow.z);
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var w = 0.5;
    var x = p;
    for (var i = 0; i < 4; i = i + 1) {
        f = f + w * noise3(x);
        x = x * 2.01;
        w = w * 0.5;
    }
    return f;
}

// SDF Helpers
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn sdCappedCylinder(p: vec3<f32>, h: f32, r: f32) -> f32 {
    let d = abs(vec2<f32>(length(p.xz), p.y)) - vec2<f32>(r, h);
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let d = abs(p) - b;
    return length(max(d, vec3<f32>(0.0))) + min(max(d.x, max(d.y, d.z)), 0.0);
}

fn mapWings(p: vec3<f32>, audio_mod: f32) -> f32 {
    var p_w = p;
    let wing_freq = u.zoom_params.x;
    let time = u.config.x * wing_freq * (1.0 + audio_mod * 0.5);

    // Flapping
    p_w.y -= sin(time + abs(p_w.x) * 1.5) * 0.4 * abs(p_w.x);
    p_w.z += cos(time + abs(p_w.x) * 1.5) * 0.2 * abs(p_w.x);

    // Fractal Wing venation
    let fractal_density = u.zoom_params.y;
    var p_f = p_w;
    var scale = 1.0;
    for (var i = 0; i < 4; i = i + 1) {
        p_f = abs(p_f) - vec3<f32>(0.5, 0.1, 0.2) / scale;
        let r_mat = rot3y(0.5 * audio_mod) * rot3z(0.3);
        p_f = r_mat * p_f;
        p_f *= 1.8;
        scale *= 1.8;
    }

    let base_wing = sdBox(p_w, vec3<f32>(2.5, 0.02, 0.6));
    let venation = sdBox(p_f, vec3<f32>(1.5, 0.1, 1.0)) / scale;

    return max(base_wing, -venation * fractal_density * 0.5);
}

fn mapBody(p: vec3<f32>, audio_mod: f32) -> f32 {
    // Thorax
    var p_thorax = p;
    p_thorax.y += sin(p.z * 1.5) * 0.1;
    let thorax = sdCappedCylinder(p_thorax.xzy, 0.8, 0.3);

    // Head
    let head = sdSphere(p - vec3<f32>(0.0, 0.1, 1.0), 0.35);

    // Tail (Segmented)
    var p_tail = p;
    p_tail.z -= -1.0;
    p_tail.y += sin(p_tail.z * 2.0 + u.config.x * 2.0) * 0.2; // Wiggle
    let tail_base = sdCappedCylinder(p_tail.xzy, 1.5, 0.15 - p_tail.z * 0.05);
    let tail_segments = cos(p_tail.z * 15.0) * 0.05;
    let tail = tail_base + tail_segments;

    var body = smin(thorax, head, 0.2);
    body = smin(body, tail, 0.3);
    return body;
}

fn map(p: vec3<f32>) -> f32 {
    var p_mod = p;
    let time = u.config.x;
    let audio = u.config.y * 2.0;

    // Mouse Interaction (Gravity Vortex)
    let mx = (u.zoom_config.y / u.config.z - 0.5) * 10.0;
    let my = (0.5 - u.zoom_config.z / u.config.w) * 10.0;
    let mouse_pos = vec3<f32>(mx, my, 0.0);

    let dist_mouse = length(p_mod - mouse_pos);
    let vortex_strength = 2.0;
    if (dist_mouse > 0.001) {
        p_mod -= normalize(p_mod - mouse_pos) * exp(-dist_mouse * 2.0) * vortex_strength;
    }

    // Creature orientation
    p_mod = rot3x(-0.3 + sin(time * 0.5) * 0.1) * rot3y(sin(time * 0.2) * 0.2) * p_mod;

    let body = mapBody(p_mod, audio);

    // Wings
    var p_wings1 = p_mod;
    p_wings1.z -= 0.2;
    var p_wings2 = p_mod;
    p_wings2.z += 0.4;

    let wings1 = mapWings(p_wings1, audio);
    let wings2 = mapWings(p_wings2, audio * 0.8);

    return min(body, min(wings1, wings2));
}

fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let coord = vec2<f32>(f32(id.x), f32(id.y));
    if (coord.x >= res.x || coord.y >= res.y) { return; }

    let uv = (coord - 0.5 * res) / res.y;
    let time = u.config.x;
    let audio = u.config.y * 2.0;

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    // Volumetric Plasma Storm (Background)
    var fog_col = vec3<f32>(0.0);
    var t_fog = 0.0;
    let fog_steps = 30;
    for (var i = 0; i < fog_steps; i = i + 1) {
        let p_fog = ro + rd * t_fog;
        let d = fbm(p_fog * 0.5 + vec3<f32>(time * 0.2, 0.0, time * 0.1)) * 0.5 + 0.5;
        let fog_density = smoothstep(0.4, 0.8, d) * 0.05;

        let pollen = pow(abs(sin(p_fog.x * 5.0 + time) * cos(p_fog.y * 5.0) * sin(p_fog.z * 5.0 - time)), 20.0);
        let glow = vec3<f32>(0.1, 0.5, 0.8) * fog_density + vec3<f32>(0.8, 0.2, 0.9) * pollen * audio;

        fog_col += glow * exp(-t_fog * 0.1);
        t_fog += 0.5;
    }

    // Raymarching Object
    var t = 0.0;
    var d = 0.0;
    let max_steps = 80;
    var hit = false;
    var p = ro;

    for (var i = 0; i < max_steps; i = i + 1) {
        p = ro + rd * t;
        d = map(p);
        if (d < 0.001) { hit = true; break; }
        if (t > 15.0) { break; }
        t += d * 0.8;
    }

    var col = fog_col;

    if (hit) {
        let n = getNormal(p);
        let v = -rd;

        // Lighting
        let l1 = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let l2 = normalize(vec3<f32>(-1.0, -0.5, -0.5));

        let dif1 = max(dot(n, l1), 0.0);
        let dif2 = max(dot(n, l2), 0.0);
        let fre = pow(1.0 - max(dot(n, v), 0.0), 3.0);

        // Quantum Glass Shading
        let refr_idx = u.zoom_params.z;
        let refr_dir = refract(rd, n, 1.0 / refr_idx);
        let refr_col = vec3<f32>(
            fbm(p + refr_dir * 0.5 + vec3<f32>(time, 0.0, 0.0)),
            fbm(p + refr_dir * 0.6 + vec3<f32>(0.0, time, 0.0)),
            fbm(p + refr_dir * 0.7 + vec3<f32>(0.0, 0.0, time))
        );

        // Base color
        var mat_col = mix(vec3<f32>(0.05, 0.1, 0.2), vec3<f32>(0.2, 0.8, 0.9), fre);
        mat_col += refr_col * 0.5;

        // Specular
        let h1 = normalize(l1 + v);
        let spec = pow(max(dot(n, h1), 0.0), 64.0) * 2.0;

        // Bioluminescent Pulse (Tail / Body)
        let glow_int = u.zoom_params.w;
        let pulse = sin(p.z * 5.0 - time * 10.0) * 0.5 + 0.5;
        let lum = vec3<f32>(0.1, 0.8, 0.9) * pulse * audio * glow_int * smoothstep(0.5, 1.0, p.z);

        col = mat_col * (dif1 * vec3<f32>(1.0) + dif2 * vec3<f32>(0.2, 0.3, 0.5)) + spec + lum;

        // Distance fog
        col = mix(col, fog_col, smoothstep(5.0, 15.0, t));
    }

    col = pow(col, vec3<f32>(0.4545)); // Gamma correction

    let prev_col = textureLoad(readTexture, vec2<i32>(id.xy), 0).rgb;
    let final_col = mix(prev_col, col, 0.5); // Temporal smoothing

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(final_col, 1.0));
}
