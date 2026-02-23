// ═══════════════════════════════════════════════════════════════
//  Cosmic Jellyfish - A majestic, translucent jellyfish in a cosmic void.
//  Category: generative
//  Features: 3d, raymarching, bioluminescent, space, organic, calm
// ═══════════════════════════════════════════════════════════════

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

// Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// SDF for the Jellyfish
fn map(p: vec3<f32>, time: f32) -> f32 {
    // Pulse animation
    let pulse_speed = u.zoom_params.x * 2.0;
    let pulse = sin(time * pulse_speed) * 0.1;

    // Tentacle Activity
    let tentacle_amp = u.zoom_params.y;

    // Bell (Ellipsoid-ish)
    var p_bell = p;
    p_bell.y -= 0.5;

    // Stretch
    let d_bell = length(p_bell / vec3<f32>(1.0 + pulse, 0.8 - pulse, 1.0 + pulse)) * 0.8 - 0.5;

    // Hollow out bottom
    let d_hollow = length(p_bell + vec3<f32>(0.0, 0.5, 0.0)) - 0.4;
    let bell_final = max(d_bell, -d_hollow);

    // Tentacles
    var d_tentacles = 100.0;
    let num_tentacles = 8.0;
    for (var i = 0.0; i < num_tentacles; i = i + 1.0) {
        let angle = (i / num_tentacles) * 6.28318;
        let radius = 0.3;
        let tentacle_pos = vec3<f32>(cos(angle) * radius, 0.0, sin(angle) * radius);
        var p_t = p - tentacle_pos;

        // Waving motion
        p_t.x += sin(p_t.y * 3.0 + time * 2.0 + i) * 0.1 * tentacle_amp;
        p_t.z += cos(p_t.y * 3.0 + time * 2.0 + i) * 0.1 * tentacle_amp;

        // Capsule shape for tentacle
        p_t.y += 1.0; // Shift down
        let h = 2.0; // Length
        p_t.y = clamp(p_t.y, 0.0, h);
        let d_t = length(p_t) - 0.05 * (1.0 - p_t.y / h); // Taper

        d_tentacles = min(d_tentacles, d_t);
    }

    // Smooth blend bell and tentacles
    return smin(bell_final, d_tentacles, 0.2);
}

// Simple hash for stars
fn hash(n: f32) -> f32 {
    return fract(sin(n) * 43758.5453123);
}

fn stars(dir: vec3<f32>) -> f32 {
    let p = dir * 100.0;
    let cell = floor(p);
    let local = fract(p);
    let n = cell.x + cell.y * 57.0 + cell.z * 113.0;
    let h = hash(n);
    if (h > 0.95) {
        let star_pos = vec3<f32>(hash(n + 1.0), hash(n + 2.0), hash(n + 3.0));
        let d = length(local - star_pos);
        return smoothstep(0.1, 0.0, d);
    }
    return 0.0;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = (vec2<f32>(global_id.xy) - resolution * 0.5) / resolution.y;
    let time = u.config.x;

    // Camera
    let mouse = u.zoom_config.yz * 2.0 - 1.0;
    var ro = vec3<f32>(0.0, 0.0, -4.0);
    // Rotate camera based on mouse
    var cam_rot = rot(mouse.x * 2.0);
    ro.x = cam_rot[0][0] * ro.x + cam_rot[0][1] * ro.z;
    ro.z = cam_rot[1][0] * ro.x + cam_rot[1][1] * ro.z;

    cam_rot = rot(mouse.y * 2.0);
    ro.y = cam_rot[0][0] * ro.y + cam_rot[0][1] * ro.z;
    ro.z = cam_rot[1][0] * ro.y + cam_rot[1][1] * ro.z;

    let target = vec3<f32>(0.0, 0.0, 0.0);
    let f = normalize(target - ro);
    let r = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), f));
    let up = cross(f, r);
    let rd = normalize(f + r * uv.x + up * uv.y);

    // Raymarch loop
    var t = 0.0;
    var glow = 0.0;
    var hit = false;

    for(var i=0; i<64; i++) {
        let p = ro + rd * t;
        let d = map(p, time);

        // Accumulate glow near the surface
        glow += 1.0 / (1.0 + d * d * 20.0);

        if (d < 0.001) {
            hit = true;
            break;
        }
        if (t > 10.0) { break; }
        t += d;
    }

    // Coloring
    var col = vec3<f32>(0.0);

    // Starfield background
    col += vec3<f32>(stars(rd));

    if (hit) {
        let p = ro + rd * t;
        // Simple normal calculation
        let e = vec2<f32>(0.01, 0.0);
        let n = normalize(vec3<f32>(
            map(p + e.xyy, time) - map(p - e.xyy, time),
            map(p + e.yxy, time) - map(p - e.yxy, time),
            map(p + e.yyx, time) - map(p - e.yyx, time)
        ));

        let light_dir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, light_dir), 0.0);
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

        let base_color = vec3<f32>(0.2, 0.5, 0.8);
        col = base_color * diff * 0.5 + base_color * fresnel * 0.8;
    }

    // Add accumulated glow (bioluminescence)
    let hue_shift = u.zoom_params.z;
    var glowColor = vec3<f32>(0.1, 0.4, 0.9); // Base Blue

    // Simple hue shift logic (rotate RGB)
    let angle = hue_shift * 6.28;
    let k = vec3<f32>(0.57735, 0.57735, 0.57735);
    let cos_angle = cos(angle);
    glowColor = glowColor * cos_angle + cross(k, glowColor) * sin(angle) + k * dot(k, glowColor) * (1.0 - cos_angle);

    let glow_intensity = u.zoom_params.w;
    col += glow * glowColor * glow_intensity * 0.02;

    textureStore(writeTexture, global_id.xy, vec4<f32>(col, 1.0));
}
