// ----------------------------------------------------------------
// Neon Plasma Chrono-Bloom
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
  zoom_params: vec4<f32>,  // .x = Point Density, .y = Rotation Speed, .z = Point Size, .w = Color Shift
  ripples: array<vec4<f32>, 50>,
};

const PI = 3.14159265359;

// Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D hash
fn hash3(p: vec3<f32>) -> f32 {
    var p2 = p;
    p2 = fract(p2 * vec3<f32>(0.1031, 0.1030, 0.0973));
    p2 += dot(p2, p2.yxz + 33.33);
    return fract((p2.x + p2.y) * p2.z);
}

// 3D Simplex noise approximation
fn snoise3(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f2 = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(hash3(p), hash3(p + vec3<f32>(1.,0.,0.)), f2.x),
            mix(hash3(p + vec3<f32>(0.,1.,0.)), hash3(p + vec3<f32>(1.,1.,0.)), f2.x), f2.y),
        mix(mix(hash3(p + vec3<f32>(0.,0.,1.)), hash3(p + vec3<f32>(1.,0.,1.)), f2.x),
            mix(hash3(p + vec3<f32>(0.,1.,1.)), hash3(p + vec3<f32>(1.,1.,1.)), f2.x), f2.y), f2.z
    ) * 2.0 - 1.0;
}

// Palette mapping
fn palette(t: f32, hue_shift: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    // Base palette: electric pinks to deep cyans, shifted by hue_shift
    let d = vec3<f32>(0.263, 0.416, 0.557) + hue_shift;
    return a + b * cos(6.28318 * (c * t + d));
}

// Smooth min
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

// Map function for raymarching
fn map(p_in: vec3<f32>, time: f32, dist_speed: f32, intensity: f32) -> f32 {
    var p = p_in;
    let t = time * dist_speed;

    // Domain repetition with distortion
    p.y += sin(p.x * 2.0 + t) * 0.5 * intensity;
    p.z += cos(p.y * 2.0 + t) * 0.5 * intensity;

    // Core structure
    let q = fract(p * 0.5) * 2.0 - 1.0;

    var d1 = length(q.xy) - 0.2;
    var d2 = length(q.yz) - 0.2;
    var d3 = length(q.zx) - 0.2;

    var d = smin(d1, smin(d2, d3, 0.5), 0.5);

    // Multi-octave noise to break up the shape and act like plasma
    d += snoise3(p * 2.0 - vec3<f32>(0.0, 0.0, t * 2.0)) * 0.3 * intensity;
    d += snoise3(p * 4.0 + vec3<f32>(t, 0.0, 0.0)) * 0.15 * intensity;

    return d;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) {
        return;
    }

    // Parameters
    let intensity = u.zoom_params.x;
    let dist_speed = u.zoom_params.y;
    let bloom_threshold = u.zoom_params.z;
    let hue_shift = u.zoom_params.w;

    // Time and audio
    var time = u.config.x;
    let bass = extraBuffer[0];
    let treble = extraBuffer[133];

    // Audio reactivity - modulates time and intensity
    time += bass * 0.01;
    let current_intensity = intensity * (1.0 + treble * 0.5);

    let pixel = vec2<i32>(global_id.xy);
    let uv_frag = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let uv = (uv_frag * 2.0 - 1.0) * vec2<f32>(resolution.x / resolution.y, 1.0);

    // Mouse Interaction
    let mouse = (u.zoom_config.yz * 2.0 - 1.0) * vec2<f32>(resolution.x / resolution.y, -1.0);
    let mouse_dist = length(uv - mouse);

    // Local time dilation based on mouse
    let time_dilation = smoothstep(0.5, 0.0, mouse_dist);
    time -= time_dilation * 2.0 * u.zoom_config.w; // Slows down or shifts phase heavily on click

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, -3.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Mouse orbit
    let rx = rot(mouse.y * 1.5);
    let ry = rot(mouse.x * 1.5);

    ro.y = ro.y * rx[0][0] + ro.z * rx[0][1];
    ro.z = ro.y * rx[1][0] + ro.z * rx[1][1];

    ro.x = ro.x * ry[0][0] + ro.z * ry[0][1];
    ro.z = ro.x * ry[1][0] + ro.z * ry[1][1];

    rd.y = rd.y * rx[0][0] + rd.z * rx[0][1];
    rd.z = rd.y * rx[1][0] + rd.z * rx[1][1];

    rd.x = rd.x * ry[0][0] + rd.z * ry[0][1];
    rd.z = rd.x * ry[1][0] + rd.z * ry[1][1];

    // Gravity well distortion around mouse ray
    if (u.zoom_config.w > 0.0) {
        let rd_mouse = normalize(vec3<f32>(mouse, 1.0));
        let m_dot = dot(rd, rd_mouse);
        if (m_dot > 0.9) {
            let pull = smoothstep(0.9, 1.0, m_dot);
            rd = normalize(mix(rd, rd_mouse, pull * 0.5));
        }
    }

    // Volumetric Raymarching
    var p = ro;
    var t_dist = 0.0;
    var accum_density = 0.0;
    var glow = vec3<f32>(0.0);

    for (var i = 0; i < 64; i++) {
        let d = map(p, time, dist_speed, current_intensity);

        // Volumetric accumulation
        if (d < 0.1) {
            let density = 0.1 - d;
            accum_density += density;

            // Artificial subsurface scattering/glowing edges
            let p_offset = p + vec3<f32>(0.05);
            let d_offset = map(p_offset, time, dist_speed, current_intensity);
            let grad = abs(d_offset - d);

            let color_val = palette(length(p) * 0.2 + time * 0.1, hue_shift);

            // Bloom threshold logic
            var lum = dot(color_val, vec3<f32>(0.299, 0.587, 0.114));
            var bloom_factor = 1.0;
            if (lum > bloom_threshold) {
               bloom_factor = 2.0;
            }

            glow += color_val * density * bloom_factor * (1.0 + grad * 5.0) * 0.05;
        }

        let step_size = max(abs(d) * 0.5, 0.02);
        t_dist += step_size;
        p = ro + rd * t_dist;

        if (t_dist > 10.0 || accum_density > 2.0) {
            break;
        }
    }

    // Background
    var bg = vec3<f32>(0.02, 0.01, 0.03); // Deep space purple/black

    // Add procedural particle scattering (glowing pollen)
    let particle_noise = snoise3(vec3<f32>(uv * 20.0, time * 0.5));
    if (particle_noise > 0.95) {
       bg += palette(time, hue_shift) * (particle_noise - 0.95) * 20.0 * (1.0 + bass);
    }

    var col = mix(bg, glow, clamp(accum_density, 0.0, 1.0));

    // Contrast and vignette
    col = smoothstep(vec3<f32>(0.0), vec3<f32>(1.2), col);
    let vignette = 1.0 - length(uv) * 0.5;
    col *= vignette;

    let prev = textureLoad(readTexture, pixel, 0);
    col = mix(prev.rgb, col, 0.15); // Temporal smoothing

    textureStore(writeTexture, pixel, vec4<f32>(col, 1.0));
}
