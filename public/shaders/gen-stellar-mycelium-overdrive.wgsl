#include "_prelude.wgsl"

// SDF functions
fn sdGyroid(p: vec3<f32>, scale: f32, thickness: f32, bias: f32) -> f32 {
    let p_scaled = p * scale;
    return abs(dot(sin(p_scaled), cos(p_scaled.zxy)) - bias) / scale - thickness;
}

// 3D Noise (fBm)
fn hash3(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.3183099);
    p3 = p3 + dot(p3, p3.yxz + 50.0);
    return fract(p3.x * p3.y * p3.z);
}

fn noise(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f2 = f * f * (3.0 - 2.0 * f);

    return mix(
        mix(mix(hash3(p + vec3<f32>(0.0,0.0,0.0)), hash3(p + vec3<f32>(1.0,0.0,0.0)), f2.x),
            mix(hash3(p + vec3<f32>(0.0,1.0,0.0)), hash3(p + vec3<f32>(1.0,1.0,0.0)), f2.x), f2.y),
        mix(mix(hash3(p + vec3<f32>(0.0,0.0,1.0)), hash3(p + vec3<f32>(1.0,0.0,1.0)), f2.x),
            mix(hash3(p + vec3<f32>(0.0,1.0,1.0)), hash3(p + vec3<f32>(1.0,1.0,1.0)), f2.x), f2.y), f2.z
    );
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var w = 0.5;
    var p_curr = p;
    for(var i = 0; i < 4; i++) {
        f += w * noise(p_curr);
        w *= 0.5;
        p_curr *= 2.0;
    }
    return f;
}

// Map function
fn map(pos: vec3<f32>, mouse_grav: vec3<f32>, gravity_strength: f32) -> f32 {
    var p = pos;

    // Add distortion based on mouse gravity well
    let dist_to_mouse = length(p - mouse_grav);
    let gravity_effect = smoothstep(2.0, 0.0, dist_to_mouse) * gravity_strength;

    // Warp space towards mouse
    if (gravity_effect > 0.0) {
        let dir = normalize(mouse_grav - p);
        p += dir * gravity_effect * 0.5;
    }

    // Add fBm noise distortion
    p += fbm(p * 2.0 + u.config.x * 0.5) * 0.2;

    // Density parameter mapping
    let density = u.zoom_params.x; // mapped to Density slider (1.0 - 5.0)

    // Basic structure
    var d = sdGyroid(p, density, 0.05, 0.0);

    return d;
}

fn calcNormal(p: vec3<f32>, mouse_grav: vec3<f32>, grav_strength: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, mouse_grav, grav_strength) - map(p - e.xyy, mouse_grav, grav_strength),
        map(p + e.yxy, mouse_grav, grav_strength) - map(p - e.yxy, mouse_grav, grav_strength),
        map(p + e.yyx, mouse_grav, grav_strength) - map(p - e.yyx, mouse_grav, grav_strength)
    ));
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let coords = vec2<i32>(id.xy);

    if (f32(coords.x) >= resolution.x || f32(coords.y) >= resolution.y) {
        return;
    }

    let uv = (vec2<f32>(coords) - 0.5 * resolution) / resolution.y;

    // Mouse Interaction
    var mouse_grav = vec3<f32>(0.0);
    var grav_strength = 0.0;
    if (u.zoom_config.w > 0.5) {
        let mouse_uv = (u.zoom_config.yz - 0.5) * vec2<f32>(resolution.x/resolution.y, 1.0);
        mouse_grav = vec3<f32>(mouse_uv * 5.0, 0.0);
        grav_strength = 2.0; // Gravity well strength
    }

    // Audio Reactivity
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    // Camera setup
    let ro = vec3<f32>(0.0, 0.0, -3.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    // Raymarching
    var p = ro;
    var t = 0.0;
    var bloom = 0.0;
    var hit = false;

    for(var i = 0; i < 100; i++) {
        p = ro + rd * t;
        let d = map(p, mouse_grav, grav_strength);

        // Volumetric bloom accumulation
        bloom += exp(-d * (5.0 - u.zoom_params.z)) * 0.05; // u.zoom_params.z = Glow Intensity

        if (d < 0.001) {
            hit = true;
            break;
        }
        if (t > 10.0) {
            break;
        }
        t += d;
    }

    // Parameters
    let pulse_speed = u.zoom_params.y; // Pulse Speed
    let color_shift = u.zoom_params.w; // Color Shift

    // Shading
    var col = vec3<f32>(0.05, 0.0, 0.1); // Base space color

    if (hit) {
        let n = calcNormal(p, mouse_grav, grav_strength);
        let lightDir = normalize(vec3<f32>(sin(u.config.x), 1.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);

        let baseCol = vec3<f32>(0.2, 0.1, 0.5) + vec3<f32>(0.0, 0.5, 0.5) * color_shift;

        // Energy pulses
        let pulse = sin(p.z * 10.0 - u.config.x * pulse_speed * 5.0) * 0.5 + 0.5;
        let pulse_color = vec3<f32>(0.1, 0.8, 0.9) * pulse * (1.0 + bass);

        // Mouse highlight
        let dist_mouse = length(p - mouse_grav);
        let mouse_glow = smoothstep(1.5, 0.0, dist_mouse) * vec3<f32>(1.0, 0.2, 0.8) * grav_strength;

        col = baseCol * diff + pulse_color + mouse_glow;
    }

    // Add bloom
    let bloom_col = vec3<f32>(0.2, 0.5, 0.8) * bloom * (1.0 + mids * 0.5);
    col += bloom_col;

    // Output
    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
}
