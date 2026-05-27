// ----------------------------------------------------------------
// Eldritch Tesseract-Hive Mind
// Category: generative
// ----------------------------------------------------------------

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
  config: vec4<f32>, // x: resolution.x, y: resolution.y, z: time, w: aspect
  zoom_config: vec4<f32>, // x: mouse.x, y: mouse.y, z: is_clicking, w: audio_intensity
  zoom_params: vec4<f32>, // param1, param2, param3, param4
  ripples: array<vec4<f32>, 50>
};

// --- CONSTANTS & HELPERS ---
const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.001;

// 4D Rotation matrix helper
fn rot4D(theta: f32) -> mat2x2<f32> {
    let c = cos(theta);
    let s = sin(theta);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash33(p3_in: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p3_in * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + vec3<f32>(dot(p3, p3.yxz + vec3<f32>(33.33)));
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// 3D Value Noise for "boolean carving"
fn vnoise3(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f2 = f * f * (vec3<f32>(3.0) - vec3<f32>(2.0) * f);

    let n = p.x + p.y * 57.0 + 113.0 * p.z;

    let res = mix(
        mix(mix(hash33(p).x, hash33(p + vec3<f32>(1.0, 0.0, 0.0)).x, f2.x),
            mix(hash33(p + vec3<f32>(0.0, 1.0, 0.0)).x, hash33(p + vec3<f32>(1.0, 1.0, 0.0)).x, f2.x), f2.y),
        mix(mix(hash33(p + vec3<f32>(0.0, 0.0, 1.0)).x, hash33(p + vec3<f32>(1.0, 0.0, 1.0)).x, f2.x),
            mix(hash33(p + vec3<f32>(0.0, 1.0, 1.0)).x, hash33(p + vec3<f32>(1.0, 1.0, 1.0)).x, f2.x), f2.y), f2.z
    );
    return res;
}

// Map function evaluating the 4D Tesseract SDF
fn map(p: vec3<f32>, time: f32, audio_intensity: f32) -> vec2<f32> {
    // 4D coordinate initialization (w component dynamically adjusted by mouse)
    let w_offset = (u.zoom_config.y - 0.5) * 2.0; // Mouse Y drives 4th dimension
    var p4 = vec4<f32>(p, w_offset);

    let rotation_speed = u.zoom_params.x;

    // Rotate in 4D space
    let r1 = rot4D(time * rotation_speed);
    let x_new = r1[0][0]*p4.x + r1[0][1]*p4.z;
    let z_new = r1[1][0]*p4.x + r1[1][1]*p4.z;
    p4.x = x_new;
    p4.z = z_new;

    // Core tesseract SDF evaluation
    var d1 = length(max(abs(p4) - vec4<f32>(1.0), vec4<f32>(0.0))) - 0.1;

    // Boolean Carving using noise to create veins
    let carve = vnoise3(p * vec3<f32>(2.0) + vec3<f32>(time * 0.5)) * 0.3;
    d1 = max(d1, -carve);

    // Add voxel tearing based on audio
    let tearing_intensity = u.zoom_params.z;
    let voxel_scale = vec3<f32>(10.0 + (audio_intensity * tearing_intensity) * 20.0);
    let voxel_p = floor(p * voxel_scale) / voxel_scale;
    let d2 = length(p - voxel_p) - 0.05;

    // Material ID mix
    // 1.0: Structure, 2.0: Voxel Glitch
    if (d2 < d1 && audio_intensity > 0.1 * (1.0 - tearing_intensity)) {
        return vec2<f32>(d2, 2.0);
    }

    return vec2<f32>(d1, 1.0);
}

// Raymarching
fn raymarch(ro: vec3<f32>, rd: vec3<f32>, time: f32, audio_intensity: f32) -> vec2<f32> {
    var dO: f32 = 0.0;
    var mat_id: f32 = 0.0;
    for(var i = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * vec3<f32>(dO);
        let dS = map(p, time, audio_intensity);
        dO += dS.x;
        mat_id = dS.y;
        if(dS.x < SURF_DIST || dO > MAX_DIST) { break; }
    }
    return vec2<f32>(dO, mat_id);
}

// Normal Calculation
fn get_normal(p: vec3<f32>, time: f32, audio_intensity: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p, time, audio_intensity).x;
    let n = vec3<f32>(d) - vec3<f32>(
        map(p - e.xyy, time, audio_intensity).x,
        map(p - e.yxy, time, audio_intensity).x,
        map(p - e.yyx, time, audio_intensity).x
    );
    return normalize(n);
}

// Thin film iridescence helper
fn iridescence(view_dir: vec3<f32>, normal: vec3<f32>, shift: f32) -> vec3<f32> {
    let ndotv = max(dot(normal, view_dir), 0.0);
    let t = ndotv + shift;
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.00, 0.33, 0.67);
    return a + b * cos(vec3<f32>(6.28318) * (c * vec3<f32>(t) + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.x, u.config.y);
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) { return; }

    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    var uv = (fragCoord - vec2<f32>(0.5) * resolution) / resolution.y;
    let time = u.config.z;
    let audio_intensity = u.zoom_config.w;

    // Parameters
    let swarm_density = u.zoom_params.y;
    let iridescence_shift = u.zoom_params.w;

    // Mouse Interaction (Gravity Well)
    var mouse_uv = (vec2<f32>(u.zoom_config.x, u.zoom_config.y) - vec2<f32>(0.5)) * resolution / resolution.y;
    let mouse_dist = length(uv - mouse_uv);
    if (u.zoom_config.z > 0.5) { // If clicking, distort space
        let pull = 0.5 / (mouse_dist + 0.1);
        uv = uv - (uv - mouse_uv) * pull * 0.05;
    }

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, -3.0);
    let rd = normalize(vec3<f32>(uv.x, uv.y, 1.0));

    // Raymarch
    let rm = raymarch(ro, rd, time, audio_intensity);
    let d = rm.x;
    let mat_id = rm.y;

    var col = vec3<f32>(0.0);

    if (d < MAX_DIST) {
        let p = ro + rd * vec3<f32>(d);
        let n = get_normal(p, time, audio_intensity);

        if (mat_id == 1.0) {
            // Tesseract Structure - Iridescent Quantum-Slick
            col = iridescence(-rd, n, iridescence_shift);
            // Diffuse lighting
            let light_dir = normalize(vec3<f32>(1.0, 2.0, -1.0));
            let diff = max(dot(n, light_dir), 0.0);
            col = col * diff;

            // Neon cyan/magenta glow in the veins
            let glow_factor = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
            let glow_color = mix(vec3<f32>(0.0, 1.0, 1.0), vec3<f32>(1.0, 0.0, 1.0), sin(time + p.y)*0.5+0.5);
            col += glow_color * vec3<f32>(glow_factor * 2.0 * audio_intensity);

        } else if (mat_id == 2.0) {
            // Voxel Tearing
            col = vec3<f32>(1.0, 0.2, 0.5) * vec3<f32>(5.0 * audio_intensity); // Hot glowing glitch
        }
    }

    // Algorithmic Sentinel Swarms (Particles overlaid using fBm flow field visualization)
    let noise_val = vnoise3(vec3<f32>(uv * 10.0, time * 0.5));
    // High frequency thresholding for particle look
    var swarm_val = step(0.95 - (swarm_density * 0.05), noise_val);

    // Mask swarms to only appear near the structure using depth
    let depth_mask = 1.0 - smoothstep(0.0, 10.0, d);
    let swarm_color = vec3<f32>(0.0, 1.0, 0.5) * vec3<f32>(swarm_val * depth_mask * 3.0);
    col += swarm_color;

    // Atmospheric Fog
    col = mix(col, vec3<f32>(0.02, 0.0, 0.05), 1.0 - exp(-0.02 * d * d));

    // Gamma correction
    col = pow(col, vec3<f32>(1.0/2.2));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
