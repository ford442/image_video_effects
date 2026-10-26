// ----------------------------------------------------------------
// Stellar Mycelium Overdrive
// Category: generative
// ----------------------------------------------------------------
#include "_prelude.wgsl"

// SDF functions
fn sdGyroid(p: vec3<f32>, scale: f32, thickness: f32, bias: f32) -> f32 {
    let p_scaled = p * scale;
    return abs(dot(sin(p_scaled), cos(p_scaled.zxy)) - bias) / scale - thickness;
}

fn rotate(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Map function
fn map(pos: vec3<f32>) -> f32 {
    var p = pos;
    // Basic structure
    let density = u.zoom_params.x; // Density

    // Add distortion based on mouse
    if (u.zoom_config.w > 0.5) {
        let mouse_pos = u.zoom_config.yz * 10.0;
        let dist = length(p.xy - mouse_pos);
        let pull = exp(-dist * 0.5) * 2.0;
        p.x -= pull * normalize(p.xy - mouse_pos).x;
        p.y -= pull * normalize(p.xy - mouse_pos).y;
    }

    var d = sdGyroid(p, density, 0.05, 0.0);

    // Layer 2
    var pr = p * 2.0;
    pr.y += u.time * 0.5;
    d = max(d, sdGyroid(pr, density * 1.5, 0.03, 0.0) * 0.5);

    return d;
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = vec2<f32>(f32(u.resolution.x), f32(u.resolution.y));
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));

    if (fragCoord.x >= resolution.x || fragCoord.y >= resolution.y) {
        return;
    }

    var uv = (fragCoord - 0.5 * resolution) / resolution.y;
    let pulse_speed = u.zoom_params.y;
    let glow_intensity = u.zoom_params.z;
    let color_shift = u.zoom_params.w;

    // Audio reactivity
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    var ro = vec3<f32>(0.0, 0.0, -5.0 + u.time * 0.5);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Slight camera rotation
    var rot = rotate(u.time * 0.1);
    ro.x = ro.x * rot[0][0] + ro.z * rot[0][1];
    ro.z = ro.x * rot[1][0] + ro.z * rot[1][1];
    rd.x = rd.x * rot[0][0] + rd.z * rot[0][1];
    rd.z = rd.x * rot[1][0] + rd.z * rot[1][1];

    var t = 0.0;
    var max_t = 20.0;
    var glow = 0.0;
    var d = 0.0;

    for (var i = 0; i < 64; i++) {
        var p = ro + rd * t;
        d = map(p);

        if (d < 0.01 || t > max_t) {
            break;
        }

        glow += 0.05 * glow_intensity / (1.0 + d * d * 100.0) * (1.0 + bass * 2.0);
        t += d * 0.8;
    }

    var col = vec3<f32>(0.0);

    if (t < max_t) {
        var p = ro + rd * t;
        var n = calcNormal(p);

        var light = normalize(vec3<f32>(1.0, 1.0, -1.0));
        var diff = max(dot(n, light), 0.0);
        var amb = 0.5 + 0.5 * n.y;

        // Base color shifted by parameters and audio
        var baseColor = vec3<f32>(0.3, 0.1, 0.5) + vec3<f32>(mids, treble, 0.0) * 0.5;
        // Shift towards neon cyan/pink
        var targetColor = vec3<f32>(0.1, 0.8, 0.9) * color_shift + vec3<f32>(0.9, 0.2, 0.5) * (1.0 - color_shift);

        col = mix(baseColor, targetColor, diff) * (diff * 0.8 + amb * 0.2);

        // Pulse effect along the Z axis
        let pulse = sin(p.z * 2.0 - u.time * pulse_speed * 5.0) * 0.5 + 0.5;
        col += targetColor * pulse * (0.5 + bass * 0.5);
    }

    // Add volumetric bloom/glow
    col += vec3<f32>(0.1, 0.3, 0.8) * glow;

    // Gamma correction
    col = pow(col, vec3<f32>(0.4545));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
