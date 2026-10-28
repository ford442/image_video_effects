// ----------------------------------------------------------------
// Aetherial Chromatic Tesseract
// Category: generative
// ----------------------------------------------------------------
#include "_prelude.wgsl"

// --- SDF Functions ---

// Rotate around arbitrary axis
fn rotate3D(axis: vec3<f32>, angle: f32) -> mat3x3<f32> {
    let a = normalize(axis);
    let s = sin(angle);
    let c = cos(angle);
    let oc = 1.0 - c;

    return mat3x3<f32>(
        oc * a.x * a.x + c,           oc * a.x * a.y - a.z * s,  oc * a.z * a.x + a.y * s,
        oc * a.x * a.y + a.z * s,  oc * a.y * a.y + c,           oc * a.y * a.z - a.x * s,
        oc * a.z * a.x - a.y * s,  oc * a.y * a.z + a.x * s,  oc * a.z * a.z + c
    );
}

// 4D Folding (Fractal fold)
fn fold4D(p: vec3<f32>, iter: i32, foldScale: f32, time: f32) -> vec3<f32> {
    var q = p;
    for(var i = 0; i < 5; i = i + 1) {
        if(i >= iter) { break; }

        // Dynamic rotation matrices based on time and iteration
        let rotX = rotate3D(vec3<f32>(1.0, 0.0, 0.0), time * 0.5 + f32(i));
        let rotY = rotate3D(vec3<f32>(0.0, 1.0, 0.0), time * 0.3 - f32(i));

        q = abs(q) - foldScale * 0.5;
        q = q * rotX;
        q = q * rotY;
        q = q * 1.5; // Scale space
    }
    return q;
}

// Scene SDF
fn map(p: vec3<f32>, params: vec4<f32>, time: f32, audio: vec3<f32>) -> f32 {
    let fold_complexity = mix(1.0, 5.0, params.x);
    let fold_iter = i32(fold_complexity);

    // Base object (cube)
    var d = length(max(abs(p) - vec3<f32>(1.0), vec3<f32>(0.0))) - 0.1;

    // Apply folding
    let folded_p = fold4D(p, fold_iter, 0.5 + audio.x * 0.2, time);

    // Tesseract inner structure
    let inner_d = length(folded_p) - (1.0 + audio.y * 0.5);

    // Combine
    return max(d, -inner_d * 0.2);
}

// Calculate normal
fn calcNormal(p: vec3<f32>, params: vec4<f32>, time: f32, audio: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, params, time, audio) - map(p - e.xyy, params, time, audio),
        map(p + e.yxy, params, time, audio) - map(p - e.yxy, params, time, audio),
        map(p + e.yyx, params, time, audio) - map(p - e.yyx, params, time, audio)
    ));
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    if (id.x >= u32(resolution.x) || id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(id.xy) / resolution;

    // Center UVs and fix aspect ratio
    var p = uv * 2.0 - 1.0;
    p.x *= resolution.x / resolution.y;

    let time = u.config.x;

    // Audio Reactivity (bass, mids, treble)
    let audio = vec3<f32>(
        clamp(plasmaBuffer[0].x, 0.0, 1.0),
        clamp(plasmaBuffer[0].y, 0.0, 1.0),
        clamp(plasmaBuffer[0].z, 0.0, 1.0)
    );

    // Params mapping
    let gravity_str = mix(0.0, 3.0, u.zoom_params.z);

    // Mouse Interaction (Gravity Well)
    var warp = vec2<f32>(0.0);
    if (u.zoom_config.w > 0.5) {
        let mouse_uv = u.zoom_config.yz;
        // Map mouse UV to centered space
        var mouse_p = mouse_uv * 2.0 - 1.0;
        mouse_p.x *= resolution.x / resolution.y;
        mouse_p.y = -mouse_p.y; // Invert Y

        let dist = length(p - mouse_p);
        warp = normalize(p - mouse_p) * exp(-dist * 5.0) * 0.5 * gravity_str;
    }

    // Apply warp
    let ray_dir_warp = normalize(vec3<f32>(p - warp, 1.5));

    // Raymarching setup
    var ro = vec3<f32>(0.0, 0.0, -3.0); // Ray origin
    let rd = ray_dir_warp; // Ray direction

    var t = 0.0;
    var d = 0.0;
    var max_dist = 20.0;

    // Raymarching loop
    for(var i = 0; i < 64; i = i + 1) {
        let p_current = ro + rd * t;
        d = map(p_current, u.zoom_params, time, audio);
        if(d < 0.001 || t > max_dist) { break; }
        t += d * 0.5; // Step size reduction for complex geometry
    }

    var col = vec3<f32>(0.0);

    // Hit object
    if (t < max_dist) {
        let p_hit = ro + rd * t;
        let n = calcNormal(p_hit, u.zoom_params, time, audio);

        // Iridescence / Color mapping
        let iri_shift = mix(0.0, 1.0, u.zoom_params.y);
        let view_dir = -rd;
        let ndotv = max(dot(n, view_dir), 0.0);

        // Thin-film interference simulation
        let phase = time * 0.2 + ndotv * 3.0 + iri_shift * 5.0;
        let iridescence = 0.5 + 0.5 * cos(phase + p_hit.xyx * 0.5 + vec3<f32>(0.0, 2.0, 4.0));

        // Basic lighting
        let light_dir = normalize(vec3<f32>(sin(time), 1.0, cos(time)));
        let diff = max(dot(n, light_dir), 0.0);
        let amb = 0.1;

        // Add it together
        col = iridescence * (diff + amb) * (1.0 + audio.x * 0.5);
    }

    // Add glow (subsurface / aura)
    let glow_int = mix(0.0, 2.0, u.zoom_params.w);
    let glow = max(0.0, 1.0 - t / max_dist);
    col += vec3<f32>(0.1, 0.3, 0.8) * pow(glow, 3.0) * glow_int * (1.0 + audio.y);

    // Output
    textureStore(writeTexture, id.xy, vec4<f32>(col, 1.0));
}
