// ----------------------------------------------------------------
// Stellar Cyber-Lotus Forge
// Category: generative
// ----------------------------------------------------------------
#include "_prelude.wgsl"

const PI = 3.14159265359;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn map(p_in: vec3<f32>) -> f32 {
    var p = p_in;

    // Mouse Interaction: Gravity well when clicked
    if (u.zoom_config.w > 0.5) {
        let mouse_pos = vec3<f32>((u.zoom_config.y - 0.5) * 5.0, (0.5 - u.zoom_config.z) * 5.0, 0.0);
        let dist_to_mouse = length(p - mouse_pos);
        if (dist_to_mouse < 3.0) {
            let pull = 1.0 - smoothstep(0.0, 3.0, dist_to_mouse);
            p = mix(p, mouse_pos, pull * 0.5);
        }
    }

    let time = u.config.x * u.zoom_params.y; // Rotation Speed

    // Rotate entire lotus
    let xz = rot(time * 0.2) * vec2<f32>(p.x, p.z);
    p.x = xz.x;
    p.z = xz.y;

    // Core sphere
    let core = length(p) - 1.0;

    // Petals (Polar repetition)
    var d = 100.0;
    let num_petals = u.zoom_params.z; // Petal Complexity
    for (var i = 0.0; i < 6.0; i = i + 1.0) { // Max petals, break early if needed based on num_petals, simplified here for structure
        let angle = (i / 6.0) * PI * 2.0;
        var pp = p;
        let xz_petal = rot(angle) * vec2<f32>(pp.x, pp.z);
        pp.x = xz_petal.x;
        pp.z = xz_petal.y;

        pp.x -= 1.2; // Offset from center

        // Fold/Curve the petal
        pp.y -= sin(pp.x * 2.0 + time) * 0.3;

        let petal = length(vec3<f32>(pp.x, max(0.0, abs(pp.y) - 0.05), pp.z)) - 0.5 + p.x * 0.2; // Tapering box-like shape
        d = smin(d, petal, 0.4);
    }

    return smin(core, d, 0.5);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) {
        return;
    }

    let uv = (vec2<f32>(id.xy) - 0.5 * resolution) / resolution.y;

    // Ray setup
    let ro = vec3<f32>(0.0, 2.0, -5.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var p = ro;
    var t = 0.0;
    var glow = 0.0;

    // Raymarching
    for (var i = 0; i < 64; i++) {
        p = ro + rd * t;
        let d = map(p);

        if (d < 0.01) { break; }
        if (t > 15.0) { break; }

        glow += 0.05 / (0.1 + d); // Simple bloom accumulation
        t += d * 0.8;
    }

    // Audio reactivity
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let bloom_intensity = u.zoom_params.x * (1.0 + bass * 2.0); // Bloom Intensity

    // Coloring
    var col = vec3<f32>(0.0);
    if (t < 15.0) {
        let baseColor = mix(vec3<f32>(0.1, 0.2, 0.5), vec3<f32>(0.8, 0.1, 0.6), clamp(length(p)*0.3, 0.0, 1.0));
        let veinGlow = vec3<f32>(1.0, 0.8, 0.2) * glow * 0.02 * u.zoom_params.w * (1.0 + bass); // Vein Glow
        col = baseColor + veinGlow;
    }

    col += vec3<f32>(0.2, 0.5, 0.8) * glow * 0.01 * bloom_intensity; // Ambient bloom

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
