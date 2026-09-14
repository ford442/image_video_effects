// ----------------------------------------------------------------
// Cybernetic Plasma-Orchid Nexus
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
  zoom_params: vec4<f32>,  // .x = Petal Complexity, .y = Plasma Intensity, .z = Distortion Strength, .w = Bloom Spread
  ripples: array<vec4<f32>, 50>,
};

// 2D Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D Rotation matrices
fn rotX(a: f32) -> mat3x3<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat3x3<f32>(
        1.0, 0.0, 0.0,
        0.0, c, -s,
        0.0, s, c
    );
}

fn rotY(a: f32) -> mat3x3<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat3x3<f32>(
        c, 0.0, s,
        0.0, 1.0, 0.0,
        -s, 0.0, c
    );
}

fn rotZ(a: f32) -> mat3x3<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat3x3<f32>(
        c, -s, 0.0,
        s, c, 0.0,
        0.0, 0.0, 1.0
    );
}

// Custom SDFs and Noise functions
fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

// Hash function for noise
fn hash(n: f32) -> f32 {
    return fract(sin(n) * 43758.5453);
}

fn hash3(p: vec3<f32>) -> f32 {
    return fract(sin(dot(p, vec3<f32>(12.9898, 78.233, 45.164))) * 43758.5453);
}

// Basic 3D noise
fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    return mix(
        mix(
            mix(hash3(i + vec3<f32>(0.0, 0.0, 0.0)), hash3(i + vec3<f32>(1.0, 0.0, 0.0)), u.x),
            mix(hash3(i + vec3<f32>(0.0, 1.0, 0.0)), hash3(i + vec3<f32>(1.0, 1.0, 0.0)), u.x), u.y
        ),
        mix(
            mix(hash3(i + vec3<f32>(0.0, 0.0, 1.0)), hash3(i + vec3<f32>(1.0, 0.0, 1.0)), u.x),
            mix(hash3(i + vec3<f32>(0.0, 1.0, 1.0)), hash3(i + vec3<f32>(1.0, 1.0, 1.0)), u.x), u.y
        ), u.z
    );
}

// fBm
fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var w = 0.5;
    var q = p;
    for (var i = 0; i < 4; i = i + 1) {
        f += w * noise(q);
        q *= 2.0;
        w *= 0.5;
    }
    return f;
}

// Smooth min
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Scene SDF
fn map(p: vec3<f32>, time: f32, petal_complexity: f32, distortion: f32, mouse_pos: vec2<f32>, bass: f32) -> vec2<f32> {
    var p_mod = p;

    // Magnetic gravity well from mouse
    let mouse_ndc = (mouse_pos * 2.0 - 1.0) * vec2<f32>(1.0, -1.0); // y=0 is top in u.zoom_config.yz
    let mouse_3d = vec3<f32>(mouse_ndc.x * 3.0, mouse_ndc.y * 3.0, 0.0);
    let dist_to_mouse = length(p - mouse_3d);
    let gravity_pull = distortion / (dist_to_mouse * dist_to_mouse + 0.1);

    p_mod += normalize(mouse_3d - p) * min(gravity_pull, 1.0);

    // Animate overall structure
    let rot_anim = rotY(time * 0.2 + bass * 0.1) * rotZ(time * 0.1);
    p_mod = p_mod * rot_anim;

    // Core (Plasma)
    let core_scale = 1.0 + bass * 0.2;
    let sphere = sdSphere(p_mod, 0.4 * core_scale);
    let torus = sdTorus(p_mod * rotX(time), vec2<f32>(0.5 * core_scale, 0.1));
    let core_dist = smin(sphere, torus, 0.2);

    // Petals
    var petal_p = p_mod;
    // Polar repetition
    let angle = atan2(petal_p.y, petal_p.x);
    let radius = length(petal_p.xy);

    let num_petals = floor(petal_complexity) * 2.0;
    let segment = 6.28318 / num_petals;
    let a_mod = (fract(angle / segment + 0.5) - 0.5) * segment;

    petal_p.x = radius * cos(a_mod);
    petal_p.y = radius * sin(a_mod);

    // Bend petals outwards
    let bend = radius * radius * 0.2 * sin(time + radius * 2.0);
    petal_p.z -= bend;

    // Petal shape
    let petal_width = 0.2 + 0.1 * sin(radius * 5.0 - time);
    let petal_length = 2.5;

    // Displace with fBm
    let disp = fbm(p_mod * 3.0 + time * 0.5) * 0.1;

    let q = abs(petal_p) - vec3<f32>(petal_width, petal_length, 0.02 + disp);
    let d_box = length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);

    // Mask by radius to make them petal shaped
    let petal_dist = max(d_box, radius - petal_length);

    // Return vec2: (distance, material_id)
    if (core_dist < petal_dist) {
        return vec2<f32>(core_dist, 1.0); // 1 = core
    } else {
        return vec2<f32>(petal_dist, 2.0); // 2 = petal
    }
}

// Normal calculation
fn calcNormal(p: vec3<f32>, time: f32, petal_complexity: f32, distortion: f32, mouse_pos: vec2<f32>, bass: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy, time, petal_complexity, distortion, mouse_pos, bass).x - map(p - e.xyy, time, petal_complexity, distortion, mouse_pos, bass).x,
        map(p + e.yxy, time, petal_complexity, distortion, mouse_pos, bass).x - map(p - e.yxy, time, petal_complexity, distortion, mouse_pos, bass).x,
        map(p + e.yyx, time, petal_complexity, distortion, mouse_pos, bass).x - map(p - e.yyx, time, petal_complexity, distortion, mouse_pos, bass).x
    );
    return normalize(n);
}

// Palette generation
fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557);
    return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    let coords = vec2<i32>(global_id.xy);

    if (coords.x >= i32(dimensions.x) || coords.y >= i32(dimensions.y)) {
        return;
    }

    let resolution = vec2<f32>(dimensions);
    var uv = (vec2<f32>(coords) + 0.5) / resolution;
    let base_uv = uv;
    uv = uv * 2.0 - 1.0;
    uv.x *= resolution.x / resolution.y;

    // Parameters
    let time = u.config.x;
    let petal_complexity = clamp(u.zoom_params.x, 1.0, 8.0);
    let plasma_intensity = clamp(u.zoom_params.y, 0.1, 3.0);
    let distortion = clamp(u.zoom_params.z, 0.0, 2.0);
    let bloom_spread = clamp(u.zoom_params.w, 0.1, 2.0);
    let mouse_pos = u.zoom_config.yz; // y=0 is top, range [0, 1]

    // Audio reactivity
    let bass = extraBuffer[0] * 2.0;

    // Raymarching setup
    var ro = vec3<f32>(0.0, 0.0, -5.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Core raymarching loop
    var t = 0.0;
    var d = 0.0;
    var m = 0.0;
    var p = ro;

    var glow = 0.0;
    var hit = false;

    for (var i = 0; i < 100; i = i + 1) {
        p = ro + rd * t;
        let res = map(p, time, petal_complexity, distortion, mouse_pos, bass);
        d = res.x;
        m = res.y;

        // Volumetric glow accumulation
        if (m == 1.0) {
            glow += 0.05 * plasma_intensity / (0.1 + abs(d));
        } else {
            glow += 0.01 * plasma_intensity / (0.1 + abs(d));
        }

        if (d < 0.001) {
            hit = true;
            break;
        }
        if (t > 20.0) {
            break;
        }
        t += d * 0.7; // step size multiplier to avoid artifacts with domain warping
    }

    // Color mapping and shading
    var col = vec3<f32>(0.0);

    if (hit) {
        let n = calcNormal(p, time, petal_complexity, distortion, mouse_pos, bass);

        if (m == 1.0) { // Core
            // Sub-surface scattering approximation
            let sss = smoothstep(0.0, 1.0, 0.5 + 0.5 * dot(n, -rd));
            let core_color = palette(p.z * 0.5 + time) * vec3<f32>(1.5, 0.5, 2.0); // Cyan/Magenta bias
            col = core_color * sss * plasma_intensity;

        } else { // Petal
            // Procedural iridescence via Fresnel
            let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
            let view_angle_color = palette(fresnel + time * 0.2); // shifts purple to gold

            // Basic lighting
            let light_dir = normalize(vec3<f32>(1.0, 1.0, -1.0));
            let diff = max(dot(n, light_dir), 0.0);
            let amb = 0.2;

            col = view_angle_color * (diff + amb) + fresnel * vec3<f32>(1.0, 0.8, 0.2);
            col *= 0.5; // Petals are slightly darker than the core
        }
    }

    // Add glow
    let glow_col = palette(time * 0.5) * vec3<f32>(0.8, 0.2, 1.0);
    col += glow_col * glow * 0.1;

    // Chromatic aberration / Bloom effect based on distance from center
    let center_dist = length(uv);
    let ca_strength = smoothstep(0.0, 1.5, center_dist) * bloom_spread * 0.05;

    // Simple RGB split based on normal rd if hit, or just uv if missed
    var col_r = col;
    var col_b = col;

    // For a true multi-tap CA, we'd need multiple raymarches.
    // Here we approximate CA on the final color based on radius
    col_r = col * vec3<f32>(1.0, 0.0, 0.0) * (1.0 + ca_strength) + col * vec3<f32>(0.0, 1.0, 1.0);
    col_b = col * vec3<f32>(0.0, 0.0, 1.0) * (1.0 + ca_strength) + col * vec3<f32>(1.0, 1.0, 0.0);

    // Reconstruct
    col = vec3<f32>(col_r.r, col.g, col_b.b);

    // Tone mapping
    col = col / (1.0 + col);

    // Gamma correction
    col = pow(col, vec3<f32>(1.0/2.2));

    let final_color = vec4<f32>(col, 1.0);
    textureStore(writeTexture, coords, final_color);
}
