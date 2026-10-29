#include "_prelude.wgsl"

// ----------------------------------------------------------------
// Aetherial Chromatic Tesseract
// Category: generative
// ----------------------------------------------------------------

// 3D rotation function
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Distance function for the Tesseract
fn map(p_in: vec3<f32>, time: f32, bass: f32, mids: f32, fold_complexity: f32) -> f32 {
    var p = p_in;

    // Domain repetition (folding)
    for (var i = 0; i < 4; i++) {
        p.x = abs(p.x) - 1.0;
        let p_yz = p.yz * rot(time * 0.2 + f32(i) * 0.5);
        p.y = p_yz.x;
        p.z = p_yz.y;

        let p_xz = p.xz * rot(time * 0.3 + mids * 0.5);
        p.x = p_xz.x;
        p.z = p_xz.y;
    }

    // Scale mod based on audio and complexity
    let scale = 1.0 + bass * 0.2;
    p = p / scale;

    // Basic Box SDF
    let b = vec3<f32>(1.0 * fold_complexity);
    let q = abs(p) - b;
    let d = length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);

    return d * scale;
}

// Calculate normal
fn calcNormal(p: vec3<f32>, time: f32, bass: f32, mids: f32, fold_complexity: f32) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize(
        e.xyy * map(p + e.xyy, time, bass, mids, fold_complexity) +
        e.yyx * map(p + e.yyx, time, bass, mids, fold_complexity) +
        e.yxy * map(p + e.yxy, time, bass, mids, fold_complexity) +
        e.xxx * map(p + e.xxx, time, bass, mids, fold_complexity)
    );
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) {
        return;
    }

    var uv = (vec2<f32>(id.xy) - 0.5 * resolution) / resolution.y;
    let time = u.config.x;

    // Parameters
    let fold_complexity = u.sliderA; // 1.0
    let iridescence_shift = u.sliderB; // 0.5
    let gravity_strength = u.sliderC; // 1.0
    let glow_intensity = u.sliderD; // 1.0

    // Audio Reactivity
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);

    // Mouse Interaction
    if (u.zoom_config.w > 0.5) {
        var mouse_uv = (u.zoom_config.yz - 0.5 * resolution) / resolution.y;
        mouse_uv.y = -mouse_uv.y; // Correct Y inversion if necessary

        let dist = length(uv - mouse_uv);
        let warp = normalize(uv - mouse_uv) * exp(-dist * 5.0) * 0.1 * gravity_strength;
        uv += warp;
    }

    // Raymarching Setup
    let ro = vec3<f32>(0.0, 0.0, -5.0); // Ray Origin
    let rd = normalize(vec3<f32>(uv, 1.0)); // Ray Direction

    var dO = 0.0; // Total distance traveled
    var p = ro;
    var d = 0.0;

    var glow = 0.0;

    // Raymarching Loop
    for (var i = 0; i < 100; i++) {
        p = ro + rd * dO;
        d = map(p, time, bass, mids, fold_complexity);

        // Accumulate glow based on proximity to surface and audio
        glow += (0.01 * glow_intensity * (1.0 + bass)) / (0.01 + abs(d));

        if (d < 0.001 || dO > 20.0) {
            break;
        }
        dO += d;
    }

    var col = vec3<f32>(0.0);

    // Hit object
    if (dO < 20.0) {
        let n = calcNormal(p, time, bass, mids, fold_complexity);
        let v = -rd;
        let ndotv = max(dot(n, v), 0.0);

        // Iridescence (thin-film interference)
        let iridescence = 0.5 + 0.5 * cos(time * 0.5 + ndotv * 3.0 + vec3<f32>(0.0, 2.0, 4.0) * iridescence_shift * 5.0);

        // Basic lighting (diffuse + spec)
        let lightDir = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);

        let h = normalize(lightDir + v);
        let spec = pow(max(dot(n, h), 0.0), 32.0);

        // Soft shadow (ambient occlusion proxy)
        let ao = clamp(dO / 10.0, 0.0, 1.0);

        col = (iridescence * diff * 0.8 + vec3<f32>(spec) * 0.2) * (1.0 - ao * 0.5);
    }

    // Add glow
    col += vec3<f32>(0.2, 0.4, 0.8) * glow * 0.1;

    // Gamma correction
    col = pow(col, vec3<f32>(1.0 / 2.2));

    textureStore(writeTexture, id.xy, vec4<f32>(col, 1.0));
}
