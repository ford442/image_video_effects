// ----------------------------------------------------------------
// Ethereal Neon-Bismuth Origami
// Category: generative
// ----------------------------------------------------------------
#include "_prelude.wgsl"

// ----------------------------------------------------------------
// Shader Code
// ----------------------------------------------------------------

// 2D Rotation Matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Bismuth/Iridescent Color Palette based on Cosine Gradients
fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.3, 0.20, 0.20);
    return a + b * cos(6.28318 * (c * t + d));
}

// Kaleidoscopic Iterated Function System (KIFS) for Bismuth geometry
fn map(p_in: vec3<f32>, time: f32, mouse_pos: vec3<f32>) -> f32 {
    var p = p_in;

    // Mouse Interaction: Bloom effect
    let dist_to_mouse = length(p - mouse_pos);
    let bloom_factor = smoothstep(2.0, 0.0, dist_to_mouse) * u.zoom_params.y; // u.zoom_params.y is Bloom Strength

    let scale = 1.2 + sin(time * 0.5) * 0.1 + bloom_factor * 0.5;

    var d = 100.0;

    // Iterative space folding
    for (var i = 0; i < 4; i = i + 1) {
        // Fold 1
        p = abs(p) - vec3<f32>(1.0, 1.0, 1.0) * u.zoom_params.x; // u.zoom_params.x is Scale

        // Rotate
        p.x = p.x * cos(time * 0.2) - p.y * sin(time * 0.2);
        p.y = p.x * sin(time * 0.2) + p.y * cos(time * 0.2);

        p.y = p.y * cos(time * 0.3) - p.z * sin(time * 0.3);
        p.z = p.y * sin(time * 0.3) + p.z * cos(time * 0.3);

        // Scale
        p = p * scale;

        // Cube SDF
        let q = abs(p) - vec3<f32>(0.5);
        let current_d = length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);

        // Min distance, scaled back
        d = min(d, current_d * pow(scale, f32(-i - 1)));
    }

    return d;
}

// Calculate normal using finite differences
fn getNormal(p: vec3<f32>, time: f32, mouse_pos: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, time, mouse_pos) - map(p - e.xyy, time, mouse_pos),
        map(p + e.yxy, time, mouse_pos) - map(p - e.yxy, time, mouse_pos),
        map(p + e.yyx, time, mouse_pos) - map(p - e.yyx, time, mouse_pos)
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) {
        return;
    }

    // Normalized coordinates (-1 to 1)
    let uv = (vec2<f32>(id.xy) - 0.5 * resolution) / resolution.y;

    let time = u.config.x * u.zoom_params.w; // u.zoom_params.w is Time Speed

    // Mouse coordinates mapped to 3D space
    var mouse_uv = u.zoom_config.yz;
    if (u.zoom_config.w < 0.5) {
        // Default to center if mouse not pressed
        mouse_uv = vec2<f32>(0.5, 0.5);
    }
    let mouse_pos = vec3<f32>((mouse_uv - 0.5) * 4.0, 0.0);

    // Ray setup
    let ro = vec3<f32>(0.0, 0.0, -3.0); // Ray origin (camera)
    let rd = normalize(vec3<f32>(uv, 1.0)); // Ray direction

    var p = ro;
    var t = 0.0;
    var i = 0.0;
    var glow = 0.0;

    // Raymarching loop
    for (i = 0.0; i < 100.0; i = i + 1.0) {
        let d = map(p, time, mouse_pos);
        if (d < 0.001 || t > 10.0) {
            break;
        }
        t = t + d;
        p = ro + rd * t;

        // Volumetric glow accumulation
        glow = glow + 0.02 / (0.1 + d);
    }

    var col = vec3<f32>(0.0);

    if (t < 10.0) {
        // We hit the surface
        let n = getNormal(p, time, mouse_pos);

        // Lighting
        let light_dir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, light_dir), 0.0);
        let view_dir = normalize(ro - p);

        // Thin-film interference (iridescence) based on viewing angle
        let fresnel = 1.0 - max(dot(n, view_dir), 0.0);
        col = palette(fresnel * u.zoom_params.z + time * 0.1); // u.zoom_params.z is Iridescence Rate

        col = col * (diff * 0.8 + 0.2); // Apply diffuse lighting

        // Edge highlighting (neon effect)
        let edge = smoothstep(0.4, 0.5, fract(p.x * 5.0)) + smoothstep(0.4, 0.5, fract(p.y * 5.0));
        col = col + vec3<f32>(0.2, 0.8, 1.0) * edge * 0.5;

    }

    // Add volumetric glow
    col = col + vec3<f32>(0.8, 0.2, 0.9) * glow * 0.05;

    // Gamma correction
    col = pow(col, vec3<f32>(0.4545));

    textureStore(writeTexture, id.xy, vec4<f32>(col, 1.0));
}
