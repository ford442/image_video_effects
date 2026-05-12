// ----------------------------------------------------------------
// Eldritch Tesseract-Hive Mind
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
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

// 3D rotation helper
fn rot3D(axis: vec3<f32>, angle: f32) -> mat3x3<f32> {
    let a = normalize(axis);
    let s = sin(angle);
    let c = cos(angle);
    let r = 1.0 - c;
    return mat3x3<f32>(
        a.x * a.x * r + c,       a.x * a.y * r - a.z * s, a.x * a.z * r + a.y * s,
        a.y * a.x * r + a.z * s, a.y * a.y * r + c,       a.y * a.z * r - a.x * s,
        a.z * a.x * r - a.y * s, a.z * a.y * r + a.x * s, a.z * a.z * r + c
    );
}

// Map function evaluating the 4D Tesseract SDF
fn map(p_in: vec3<f32>, time: f32, audio_intensity: f32, mouse: vec2<f32>, rot_speed: f32, voxel_tear: f32) -> vec2<f32> {
    // Gravitational Anomaly from mouse
    let mouse_world = vec3<f32>((mouse.x - 0.5) * 4.0, (mouse.y - 0.5) * 4.0, 0.0);
    let dist_to_mouse = length(p_in.xy - mouse_world.xy);
    let gravity_pull = 0.5 / (1.0 + dist_to_mouse * dist_to_mouse * 5.0);
    var p = p_in - vec3<f32>(mouse_world.xy * gravity_pull, 0.0);

    // 4D coordinate initialization (using gravity pull on 4th dim)
    var p4 = vec4<f32>(p, gravity_pull * 2.0);

    // Rotate in 4D space
    let t = time * rot_speed;
    let r1 = rot4D(t * 0.5);
    let x_new = r1[0][0]*p4.x + r1[0][1]*p4.z;
    let z_new = r1[1][0]*p4.x + r1[1][1]*p4.z;
    p4.x = x_new;
    p4.z = z_new;

    let r2 = rot4D(t * 0.7);
    let y_new = r2[0][0]*p4.y + r2[0][1]*p4.w;
    let w_new = r2[1][0]*p4.y + r2[1][1]*p4.w;
    p4.y = y_new;
    p4.w = w_new;

    // Core tesseract SDF evaluation
    let d1 = length(max(abs(p4) - vec4<f32>(1.0), vec4<f32>(0.0))) - 0.1;

    // Add voxel tearing based on audio
    let tear = audio_intensity * voxel_tear;
    let voxel_scale = vec3<f32>(10.0 + tear * 20.0);
    let voxel_p = floor(p * voxel_scale) / voxel_scale;
    let d2 = length(p - voxel_p) - 0.05;

    // Boolean Carving using pseudo-Voronoi
    let q = p * 2.0;
    let noise = sin(q.x)*cos(q.y)*sin(q.z) + sin(q.x*2.0)*cos(q.y*2.0)*sin(q.z*2.0)*0.5;
    let d3 = d1 + noise * 0.2;

    // Material ID mix
    var mat_id = 1.0;
    var d = max(d3, -d2); // Subtract voxels from structure
    if (d2 < d3) {
        d = d2;
        mat_id = 2.0; // Voxel material
    }

    return vec2<f32>(d, mat_id);
}

fn getNormal(p: vec3<f32>, time: f32, audio_intensity: f32, mouse: vec2<f32>, rot_speed: f32, voxel_tear: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p, time, audio_intensity, mouse, rot_speed, voxel_tear).x;
    let n = d - vec3<f32>(
        map(p - e.xyy, time, audio_intensity, mouse, rot_speed, voxel_tear).x,
        map(p - e.yxy, time, audio_intensity, mouse, rot_speed, voxel_tear).x,
        map(p - e.yyx, time, audio_intensity, mouse, rot_speed, voxel_tear).x
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let texSize = vec2<i32>(i32(u.config.z), i32(u.config.w));
    let coord = vec2<i32>(id.xy);
    if (coord.x >= texSize.x || coord.y >= texSize.y) { return; }

    let uv = (vec2<f32>(coord) - 0.5 * vec2<f32>(texSize)) / vec2<f32>(texSize).y;
    let time = u.config.x;
    let audio = u.zoom_config.x;
    let mouse = u.zoom_params.xy;

    // Parameters
    let rot_speed = u.config.y; // Slider 1
    let swarm_density = u.config.z; // Slider 2
    let voxel_tear = u.zoom_config.y; // Slider 3
    let iridescence = u.zoom_config.z; // Slider 4

    let ro = vec3<f32>(0.0, 0.0, -4.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var d0 = 0.0;
    var m = 0.0;
    var p = vec3<f32>(0.0);
    var glow = 0.0;
    for (var i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * d0;
        let dS = map(p, time, audio, mouse, rot_speed, voxel_tear);
        d0 += dS.x;
        m = dS.y;

        // Accumulate glow from swarm
        if (dS.x > 0.0) {
            glow += 0.01 * swarm_density / (dS.x * dS.x + 0.01);
        }

        if (dS.x < SURF_DIST || d0 > MAX_DIST) { break; }
    }

    var col = vec3<f32>(0.0);
    if (d0 < MAX_DIST) {
        let n = getNormal(p, time, audio, mouse, rot_speed, voxel_tear);
        let view_dir = normalize(-rd);
        let ndotv = max(dot(n, view_dir), 0.0);

        // Thin-film interference
        let interference_color = cos(vec3<f32>(0.0, 2.0, 4.0) + (1.0 - ndotv) * 5.0 * iridescence) * 0.5 + 0.5;

        if (m == 1.0) {
            col = interference_color * 0.5 + vec3<f32>(0.1, 0.2, 0.3) * ndotv;
        } else {
            // Voxel material: Simple procedural neon glow
            let plasma_col = vec3<f32>(1.0, 0.0, 1.0); // Magenta
            col = plasma_col * 2.0 + vec3<f32>(1.0) * pow(ndotv, 4.0);
        }
    }

    // Add swarm glow
    col += vec3<f32>(0.0, 1.0, 1.0) * glow * 0.05 * audio;

    // Output final color
    textureStore(writeTexture, coord, vec4<f32>(col, 1.0));
}
