// ----------------------------------------------------------------
// Chromodynamic Plasma-Collider
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
    zoom_params: vec4<f32>,  // x=Ring Density, y=Collision Rate, z=Anomaly Pull, w=Tunnel Warp
    ripples: array<vec4<f32>, 50>,
};

fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D Noise for FBM
fn hash(p: vec3<f32>) -> f32 {
    let q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    return fract(dot(q, q + 33.33));
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn map(p_in: vec3<f32>, time: f32, audio: f32, ring_density: f32, warp: f32) -> f32 {
    var p = p_in;
    // Tunnel Warp (4D relativistic speed distortion)
    p.x += sin(p.z * 0.1 * warp + time) * 2.0 * warp;
    p.y += cos(p.z * 0.15 * warp - time * 0.5) * 1.5 * warp;

    // Magnetic containment tunnel
    let tunnel_radius = 3.0;
    let base_tunnel = length(p.xy) - tunnel_radius;

    // Domain repetition for obsidian magnetic rings
    let ring_spacing = 30.0 / ring_density;
    let p_z_mod = (fract(p.z / ring_spacing + 0.5) - 0.5) * ring_spacing;
    let rings = max(base_tunnel, abs(p_z_mod) - 0.2);

    // High-frequency SDF streams (particle streaks)
    var d = rings;
    return d;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }

    let uv = (vec2<f32>(global_id.xy) - 0.5 * res) / res.y;
    let time = u.config.x;
    let audio = u.config.y;

    let ring_density = u.zoom_params.x;
    let collision_rate = u.zoom_params.y;
    let anomaly_pull = u.zoom_params.z;
    let tunnel_warp = u.zoom_params.w;

    // Camera setup for high-speed journey
    let speed = 10.0 + audio * 5.0;
    var ro = vec3<f32>(0.0, 0.0, time * speed);

    // Apply tunnel warp to camera
    ro.x -= sin(ro.z * 0.1 * tunnel_warp + time) * 2.0 * tunnel_warp;
    ro.y -= cos(ro.z * 0.15 * tunnel_warp - time * 0.5) * 1.5 * tunnel_warp;

    var rd = normalize(vec3<f32>(uv, 1.0));

    // Mouse interaction (Magnetic Anomaly)
    let mouse = u.zoom_config.yz;
    if (mouse.x > 0.0 || mouse.y > 0.0) {
        let mouse_ndc = (mouse - 0.5 * res) / res.y;
        let pull_dir = normalize(vec3<f32>(mouse_ndc, 1.0) - rd);
        rd = normalize(rd + pull_dir * anomaly_pull * 0.5);
    }

    var t = 0.0;
    var d = 0.0;
    var hit = false;
    var p = ro;

    // Raymarching loop
    for (var i = 0; i < 100; i++) {
        p = ro + rd * t;
        d = map(p, time, audio, ring_density, tunnel_warp);
        if (abs(d) < 0.001) { hit = true; break; }
        t += d * 0.8;
        if (t > 100.0) { break; }
    }

    var col = vec3<f32>(0.0);

    if (hit) {
        let depth = t / 100.0;
        // Obsidian ring color
        let base_col = vec3<f32>(0.05, 0.05, 0.08);
        col = base_col * (1.0 - depth);

        // Specular highlight approximation
        let n = normalize(p - vec3<f32>(0.0, 0.0, p.z));
        let spec = pow(max(dot(reflect(rd, n), vec3<f32>(0.0, 0.0, -1.0)), 0.0), 32.0);
        col += vec3<f32>(0.8, 0.9, 1.0) * spec * (1.0 - depth);
    }

    // Plasma & Particle Collisions Pass (Volumetric accumulation)
    var plasma = vec3<f32>(0.0);
    var t_vol = 0.0;
    for (var i = 0; i < 30; i++) {
        let vp = ro + rd * t_vol;
        // Particle streams intersecting
        let particle_phase = fract(vp.z * collision_rate * 0.1 - time * 5.0);
        let dist_to_center = length(vp.xy);

        if (dist_to_center < 1.0 && particle_phase < 0.1) {
             let burst = (0.1 - particle_phase) * 10.0;
             let chromatic = vec3<f32>(1.0, 0.2, 0.8) * burst; // Magenta/Cyan dispersion
             plasma += chromatic * (1.0 + audio * 2.0) * 0.05;
        }

        // Glowing containment fields
        if (dist_to_center > 2.5 && dist_to_center < 3.0) {
             plasma += vec3<f32>(0.1, 0.3, 0.8) * (1.0 + audio) * 0.02;
        }

        t_vol += 3.3; // Step size
    }

    col += plasma;

    // Tonemapping
    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(1.0 / 2.2));

    textureStore(writeTexture, global_id.xy, vec4<f32>(col, 1.0));
}