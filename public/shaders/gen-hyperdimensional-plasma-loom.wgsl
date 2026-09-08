// ----------------------------------------------------------------
// Hyperdimensional Plasma Loom
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
  zoom_params: vec4<f32>,  // .x = Weave Density, .y = Thread Thickness, .z = Plasma Intensity, .w = Time Speed
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ── Helpers ─────────────
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Polynomial smooth min
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// 4D Simplex-like noise (simplified for speed)
fn hash4(p: vec4<f32>) -> vec4<f32> {
    var q = vec4<f32>(dot(p, vec4<f32>(127.1, 311.7, 74.7, 21.1)),
                      dot(p, vec4<f32>(269.5, 183.3, 246.1, 124.5)),
                      dot(p, vec4<f32>(113.5, 271.9, 124.6, 98.4)),
                      dot(p, vec4<f32>(298.4, 211.1, 311.7, 85.3)));
    return fract(sin(q) * 43758.5453);
}

fn noise4D(p: vec4<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec4<f32>(3.0) - 2.0 * f);

    let n = i.x + i.y * 157.0 + i.z * 113.0 + i.w * 271.0;

    let a = dot(hash4(i + vec4<f32>(0.0, 0.0, 0.0, 0.0)), f - vec4<f32>(0.0, 0.0, 0.0, 0.0));
    let b = dot(hash4(i + vec4<f32>(1.0, 0.0, 0.0, 0.0)), f - vec4<f32>(1.0, 0.0, 0.0, 0.0));
    let c = dot(hash4(i + vec4<f32>(0.0, 1.0, 0.0, 0.0)), f - vec4<f32>(0.0, 1.0, 0.0, 0.0));
    let d = dot(hash4(i + vec4<f32>(1.0, 1.0, 0.0, 0.0)), f - vec4<f32>(1.0, 1.0, 0.0, 0.0));
    let e = dot(hash4(i + vec4<f32>(0.0, 0.0, 1.0, 0.0)), f - vec4<f32>(0.0, 0.0, 1.0, 0.0));
    let f1 = dot(hash4(i + vec4<f32>(1.0, 0.0, 1.0, 0.0)), f - vec4<f32>(1.0, 0.0, 1.0, 0.0));
    let g = dot(hash4(i + vec4<f32>(0.0, 1.0, 1.0, 0.0)), f - vec4<f32>(0.0, 1.0, 1.0, 0.0));
    let h = dot(hash4(i + vec4<f32>(1.0, 1.0, 1.0, 0.0)), f - vec4<f32>(1.0, 1.0, 1.0, 0.0));
    let i_a = dot(hash4(i + vec4<f32>(0.0, 0.0, 0.0, 1.0)), f - vec4<f32>(0.0, 0.0, 0.0, 1.0));
    let j = dot(hash4(i + vec4<f32>(1.0, 0.0, 0.0, 1.0)), f - vec4<f32>(1.0, 0.0, 0.0, 1.0));
    let k = dot(hash4(i + vec4<f32>(0.0, 1.0, 0.0, 1.0)), f - vec4<f32>(0.0, 1.0, 0.0, 1.0));
    let l = dot(hash4(i + vec4<f32>(1.0, 1.0, 0.0, 1.0)), f - vec4<f32>(1.0, 1.0, 0.0, 1.0));
    let m = dot(hash4(i + vec4<f32>(0.0, 0.0, 1.0, 1.0)), f - vec4<f32>(0.0, 0.0, 1.0, 1.0));
    let n1 = dot(hash4(i + vec4<f32>(1.0, 0.0, 1.0, 1.0)), f - vec4<f32>(1.0, 0.0, 1.0, 1.0));
    let o = dot(hash4(i + vec4<f32>(0.0, 1.0, 1.0, 1.0)), f - vec4<f32>(0.0, 1.0, 1.0, 1.0));
    let p1 = dot(hash4(i + vec4<f32>(1.0, 1.0, 1.0, 1.0)), f - vec4<f32>(1.0, 1.0, 1.0, 1.0));

    // Simplification for brevity, we'll use a simpler sine-based domain distortion instead of true 4D noise
    let val = sin(p.x) * cos(p.y) + sin(p.z) * cos(p.w);
    return val * 0.5;
}

// ── Map / SDF ─────────────
fn map(p: vec3<f32>, time: f32, zp: vec4<f32>) -> f32 {
    let weave_density = zp.x;
    let thread_thickness = zp.y;

    var pos = p;

    // Domain distortion based on 4th dimension (time)
    let n1 = noise4D(vec4<f32>(pos.x, pos.y, pos.z, time * 0.5));
    let n2 = noise4D(vec4<f32>(pos.y, pos.z, pos.x, time * 0.6));

    pos.x += n1 * 0.5;
    pos.y += n2 * 0.5;

    // Polar repetition and twisting
    var q = pos;
    q.y = p.y;

    let r1 = rot(q.z * weave_density + time);
    let q_xy = r1 * q.xy;
    q.x = q_xy.x;
    q.y = q_xy.y;

    // The "loom threads"
    let d1 = length(q.xy - vec2<f32>(0.5, 0.0)) - thread_thickness;
    let d2 = length(q.xy + vec2<f32>(0.5, 0.0)) - thread_thickness;

    let r2 = rot(-q.z * weave_density * 1.5 - time * 1.2);
    let q_xy2 = r2 * pos.xy;
    var q2 = pos;
    q2.x = q_xy2.x;
    q2.y = q_xy2.y;

    let d3 = length(q2.xy - vec2<f32>(0.0, 0.5)) - thread_thickness;
    let d4 = length(q2.xy + vec2<f32>(0.0, 0.5)) - thread_thickness;

    // Smooth blending to create junctions
    var d = smin(d1, d2, 0.2);
    d = smin(d, d3, 0.2);
    d = smin(d, d4, 0.2);

    return d;
}

// ── Normal Calculation ─────────────
fn calcNormal(p: vec3<f32>, time: f32, zp: vec4<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, time, zp) - map(p - e.xyy, time, zp),
        map(p + e.yxy, time, zp) - map(p - e.yxy, time, zp),
        map(p + e.yyx, time, zp) - map(p - e.yyx, time, zp)
    ));
}

// Main entry point
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<i32>(textureDimensions(writeTexture));
    let coords = vec2<i32>(global_id.xy);
    if (coords.x >= dims.x || coords.y >= dims.y) {
        return;
    }

    let resolution = vec2<f32>(dims);
    let base_uv = vec2<f32>(coords) / resolution;
    let uv = (vec2<f32>(coords) - 0.5 * resolution) / resolution.y;

    let t = u.config.x;
    let zp = clamp(u.zoom_params, vec4<f32>(0.001), vec4<f32>(10.0));

    // Audio Reactivity
    var bass: f32 = 0.0;
    var bassSmooth: f32 = 0.0;
    var fft: f32 = 0.0;
    if (arrayLength(&extraBuffer) > 133u) {
        bass = extraBuffer[0];
        bassSmooth = extraBuffer[133];
        extraBuffer[133] = mix(bassSmooth, bass, 0.12);
    }
    if (arrayLength(&extraBuffer) > 12u) {
        for (var bin = 1u; bin <= 8u; bin++) {
            fft += extraBuffer[4u + bin];
        }
        fft /= 8.0;
    }

    var weave_density = zp.x * (1.0 + bassSmooth * 0.5);
    let thread_thickness = zp.y;
    let plasma_intensity = zp.z * (1.0 + fft * 2.0);
    let time_speed = zp.w;

    let time = t * time_speed * (1.0 + bass * 0.2);

    // Mouse Interaction (Gravity Well)
    var m = u.zoom_config.yz;
    if (m.x == 0.0 && m.y == 0.0) {
        m = vec2<f32>(0.5, 0.5); // Default center
    }
    let mouse_uv = (m - 0.5) * vec2<f32>(resolution.x / resolution.y, 1.0);
    let mouse_down = u.zoom_config.w;

    // Ray setup
    let ro = vec3<f32>(0.0, 0.0, -3.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    // Mouse Distortion Setup (Warping ray direction / origin)
    var warped_ro = ro;
    var warped_rd = rd;

    let mouse_dist = length(uv - mouse_uv);
    let pull_strength = smoothstep(1.0, 0.0, mouse_dist) * (0.5 + mouse_down * 0.5);

    warped_rd.x += (mouse_uv.x - uv.x) * pull_strength * 0.5;
    warped_rd.y += (mouse_uv.y - uv.y) * pull_strength * 0.5;
    warped_rd = normalize(warped_rd);

    // Raymarching
    var p = warped_ro;
    var d = 0.0;
    var t_dist = 0.0;
    var i = 0;
    let max_steps = 100;
    let max_dist = 10.0;

    var glow = 0.0;

    for (; i < max_steps; i++) {
        p = warped_ro + warped_rd * t_dist;
        d = map(p, time, zp);

        // Volumetric glow accumulation
        if (d < 0.1) {
             glow += 0.01 / (0.01 + d * d);
        }

        if (d < 0.001 || t_dist > max_dist) {
            break;
        }
        t_dist += d * 0.5; // step size reduced for accuracy near thin threads
    }

    // Coloring
    var col = vec3<f32>(0.0);

    if (t_dist < max_dist) {
        let n = calcNormal(p, time, zp);

        // Iridescent Thin-film interference simulation
        let v = -warped_rd;
        let ndotv = max(dot(n, v), 0.0);

        // Base iridescent gradient (Bismuth / Quantum colors)
        let iridescence = 0.5 + 0.5 * cos(TAU * (ndotv * 2.0 - time * 0.2 + vec3<f32>(0.0, 0.33, 0.67)));
        let base_col = mix(vec3<f32>(0.2, 0.0, 0.5), vec3<f32>(0.0, 0.8, 1.0), ndotv);

        let light_dir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, light_dir), 0.0);
        let spec = pow(max(dot(reflect(-light_dir, n), v), 0.0), 32.0);

        col = base_col * diff + iridescence * 0.5 + spec * 0.5;
    }

    // Add Plasma Glow
    let plasma_col = vec3<f32>(0.8, 0.2, 1.0) * glow * 0.1 * plasma_intensity;
    col += plasma_col;

    // Ambient / Fog
    let fog = 1.0 - exp(-0.1 * t_dist);
    col = mix(col, vec3<f32>(0.01, 0.01, 0.03), fog);

    // Temporal Blending (Read previous frame)
    let prev_col = textureSampleLevel(readTexture, non_filtering_sampler, base_uv, 0.0).rgb;
    let blend_factor = 0.85; // History decay for soft trails
    col = mix(col, prev_col, blend_factor);

    // Tone mapping
    col = col / (1.0 + col);

    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
}
