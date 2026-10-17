#include "_prelude.wgsl"

// ----------------------------------------------------------------
// Synaptic Void-Weaver
// Category: generative
// ----------------------------------------------------------------

// Helper: 3D Rotation Matrix
fn rot3D(axis: vec3<f32>, angle: f32) -> mat3x3<f32> {
    let s = sin(angle);
    let c = cos(angle);
    let oc = 1.0 - c;
    return mat3x3<f32>(
        oc * axis.x * axis.x + c,           oc * axis.x * axis.y - axis.z * s,  oc * axis.z * axis.x + axis.y * s,
        oc * axis.x * axis.y + axis.z * s,  oc * axis.y * axis.y + c,           oc * axis.y * axis.z - axis.x * s,
        oc * axis.z * axis.x - axis.y * s,  oc * axis.y * axis.z + axis.x * s,  oc * axis.z * axis.z + c
    );
}

// Helper: Smooth Min
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Map function (SDF)
fn map(p_in: vec3<f32>) -> vec2<f32> {
    var p = p_in;

    // Mouse Interaction (Gravity Well)
    if (u.zoom_config.w > 0.5) {
        let mouse_pos = vec3<f32>(u.zoom_config.y * 2.0 - 1.0, u.zoom_config.z * 2.0 - 1.0, 0.0);
        let dist = length(p - mouse_pos);
        p -= normalize(p - mouse_pos) * (0.5 / (dist * dist + 0.1));
    }

    // Audio Reactivity
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);

    // Domain Warping / Fractal
    var d = 100.0;
    let iterations = i32(u.zoom_params.y);
    let thickness = u.zoom_params.z;
    let rot_speed = u.zoom_params.w;

    for(var i = 0; i < iterations; i++) {
        p = abs(p) - 1.0;
        p = p * rot3D(normalize(vec3<f32>(1.0, 1.0, 1.0)), u.config.x * rot_speed);

        let tube = length(p.xy) - thickness - (bass * 0.05);
        d = smin(d, tube, 0.5);
    }

    return vec2<f32>(d, 1.0);
}

// Compute Normals
fn get_normal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(id.x) >= res.x || f32(id.y) >= res.y) {
        return;
    }

    let uv = (vec2<f32>(id.xy) * 2.0 - res) / res.y;

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, -3.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Slight rotation over time
    let cam_rot = rot3D(vec3<f32>(0.0, 1.0, 0.0), u.config.x * 0.05);
    ro = ro * cam_rot;
    rd = rd * cam_rot;

    // Raymarching
    var t = 0.0;
    var col = vec3<f32>(0.0);
    var glow = 0.0;

    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    for(var i = 0; i < 80; i++) {
        let p = ro + rd * t;
        let d = map(p);

        if (d.x < 0.001) {
            let n = get_normal(p);
            let light_dir = normalize(vec3<f32>(1.0, 1.0, -1.0));
            let diff = max(dot(n, light_dir), 0.0);

            // Base color: dark obsidian with high specularity
            let base_color = vec3<f32>(0.05, 0.05, 0.08);
            let spec = pow(max(dot(reflect(-light_dir, n), -rd), 0.0), 32.0);

            // Emissive layer: bright cyan and magenta bioluminescence
            let emissive = mix(vec3<f32>(0.0, 1.0, 1.0), vec3<f32>(1.0, 0.0, 1.0), sin(p.z * 5.0 + u.config.x) * 0.5 + 0.5);
            let pulse = sin(p.x * 10.0 - u.config.x * 5.0) * 0.5 + 0.5;

            col = base_color + diff * vec3<f32>(0.2) + spec * vec3<f32>(1.0) + emissive * pulse * (0.5 + treble * 2.0);
            break;
        }

        t += d.x;
        glow += 0.02 / (0.01 + d.x * d.x);

        if (t > 10.0) {
            // Background: subtle deep purple glow
            col = vec3<f32>(0.1, 0.0, 0.2) * (1.0 - length(uv) * 0.5);
            break;
        }
    }

    col += vec3<f32>(0.0, 0.5, 1.0) * glow * u.zoom_params.x * 0.01;

    // Tone mapping
    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(0.4545)); // Gamma correction

    textureStore(writeTexture, id.xy, vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(t / 10.0, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, id.xy, vec4<f32>(0.0));
}
