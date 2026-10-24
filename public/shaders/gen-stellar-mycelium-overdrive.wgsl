#include "_prelude.wgsl"

// SDF Gyroid
fn sdGyroid(p: vec3<f32>, scale: f32, thickness: f32, bias: f32) -> f32 {
    let p_scaled = p * scale;
    return abs(dot(sin(p_scaled), cos(p_scaled.zxy)) - bias) / scale - thickness;
}

fn rotate3D(axis: vec3<f32>, angle: f32) -> mat3x3<f32> {
    let s = sin(angle);
    let c = cos(angle);
    let oc = 1.0 - c;
    let ax = normalize(axis);

    return mat3x3<f32>(
        oc * ax.x * ax.x + c,           oc * ax.x * ax.y - ax.z * s,  oc * ax.z * ax.x + ax.y * s,
        oc * ax.x * ax.y + ax.z * s,  oc * ax.y * ax.y + c,           oc * ax.y * ax.z - ax.x * s,
        oc * ax.z * ax.x - ax.y * s,  oc * ax.y * ax.z + ax.x * s,  oc * ax.z * ax.z + c
    );
}

// 3D Noise for branching logic/distortion
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(q) * 43758.5453123) * 2.0 - 1.0;
}

// Map function
fn map(pos: vec3<f32>) -> f32 {
    var p = pos;
    // Mouse Interaction: Gravity well
    if (u.zoom_config.w > 0.5) {
        let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 2.0 - 1.0;
        let mouse_3d = vec3<f32>(mouse_pos.x * 2.0, -mouse_pos.y * 2.0, 0.0);
        let dist = length(p - mouse_3d);
        let pull = exp(-dist * 2.0) * 1.5;
        p = mix(p, mouse_3d, pull * 0.3);
    }

    // Add distortion here based on audio (plasma buffer bass)
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    p = p + hash3(p * 2.0) * (0.1 + bass * 0.2);

    let density = u.zoom_params.x; // Density

    // Basic structure: domain warped Gyroid
    var d = sdGyroid(p, density * 2.0, 0.05 + bass * 0.02, 0.0);
    d = min(d, sdGyroid(p * rotate3D(vec3<f32>(1., 1., 1.), u.config.x * 0.5), density * 3.5, 0.02, 0.1));
    return d;
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let h = 0.001;
    let k = vec2<f32>(1.0, -1.0);
    return normalize(
        k.xyy * map(p + k.xyy * h) +
        k.yyx * map(p + k.yyx * h) +
        k.yxy * map(p + k.yxy * h) +
        k.xxx * map(p + k.xxx * h)
    );
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) {
        return;
    }

    let uv = (vec2<f32>(id.xy) * 2.0 - resolution) / min(resolution.x, resolution.y);
    let time = u.config.x;

    let pulse_speed = u.zoom_params.y;
    let glow_intensity = u.zoom_params.z;
    let color_shift = u.zoom_params.w;

    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, 3.0);
    ro = ro * rotate3D(vec3<f32>(0.0, 1.0, 0.0), time * 0.2);
    let target = vec3<f32>(0.0, 0.0, 0.0);
    let cz = normalize(target - ro);
    let cx = normalize(cross(cz, vec3<f32>(0.0, 1.0, 0.0)));
    let cy = normalize(cross(cx, cz));
    let rd = normalize(uv.x * cx + uv.y * cy + 1.5 * cz);

    // Raymarching
    var p = ro;
    var t = 0.0;
    var d = 0.0;
    var glow = 0.0;

    for (var i = 0; i < 80; i++) {
        p = ro + rd * t;
        d = map(p);
        if (d < 0.001 || t > 10.0) { break; }
        t += d * 0.5;
        // Volumetric glow
        glow += 0.02 / (0.01 + abs(d));
    }

    var col = vec3<f32>(0.0);

    if (d < 0.001) {
        let n = calcNormal(p);
        let l = normalize(vec3<f32>(1.0, 1.0, 1.0));
        let diff = max(dot(n, l), 0.0);
        let view = normalize(ro - p);
        let rim = pow(1.0 - max(dot(n, view), 0.0), 3.0);

        let base_col = vec3<f32>(0.3, 0.1, 0.6) + vec3<f32>(0.1, 0.6, 0.5) * color_shift;
        let pulse = sin(length(p) * 5.0 - time * pulse_speed * 10.0 + mids * 5.0) * 0.5 + 0.5;

        col = base_col * diff + vec3<f32>(1.0, 0.2, 0.8) * rim * (0.5 + treble) + vec3<f32>(0.1, 0.8, 1.0) * pulse * 2.0;
    }

    // Add glow
    let glow_col = vec3<f32>(0.2, 0.05, 0.4) * glow * glow_intensity * 0.1;
    col += glow_col;

    // Tonemapping
    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(0.4545)); // Gamma correction

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}