// ----------------------------------------------------------------
// Bioluminescent Neural-Coral Matrix
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
#include "_prelude.wgsl"


// --- Helper Functions ---
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// SDF for the Neural Coral
fn map(pos: vec3<f32>) -> f32 {
    var p = pos;

    // Mouse Interaction: Gravity well
    if (u.zoom_config.w > 0.5) {
        let mouse_pos = vec3<f32>((u.zoom_config.y - 0.5) * 5.0, (0.5 - u.zoom_config.z) * 5.0, 0.0);
        let dist = length(p - mouse_pos);
        let pull = 1.0 / (1.0 + dist * dist);
        p = p - normalize(p - mouse_pos) * pull * u.zoom_params.y;
    }

    // Audio reactivity
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let pulse = sin(u.config.x * 2.0 + p.z * 0.5) * bass;

    // Gyroid structure
    let scale = u.zoom_params.x; // Scale param
    var d = (dot(sin(p * scale), cos(p.zxy * scale)) + 0.5) / scale;

    // Organic fBM distortion
    d += sin(p.x * 3.0 + u.config.x) * 0.1;

    return d - (0.1 + pulse * 0.05); // Thickness based on audio
}

// Raymarching
fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32> {
    var t = 0.0;
    var glow = 0.0;
    for(var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let d = map(p);
        if (d < 0.001) { break; }
        if (t > 20.0) { t = -1.0; break; }
        t += d * 0.5;
        glow += 0.01 / (0.01 + d * d);
    }
    return vec2<f32>(t, glow);
}

// Compute normal
fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) { return; }

    let uv = (vec2<f32>(id.xy) - 0.5 * resolution) / resolution.y;

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, u.config.x * u.zoom_params.z); // Move forward over time
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Slight camera roll
    let rxy = rd.xy * rot2D(sin(u.config.x * 0.2) * 0.1);
    rd = vec3<f32>(rxy, rd.z);

    let result = raymarch(ro, rd);
    let t = result.x;
    let glow = result.y;

    var color = vec3<f32>(0.0);
    var out_depth = 1.0;
    var n = vec3<f32>(0.0);

    if (t > 0.0) {
        let p = ro + rd * t;
        n = getNormal(p);

        let lightDir = normalize(vec3<f32>(sin(u.config.x), 1.0, cos(u.config.x)));
        let diff = max(dot(n, lightDir), 0.0);
        let sss = clamp(map(p + lightDir * 0.2) / 0.2, 0.0, 1.0);
        let baseColor = mix(vec3<f32>(0.02, 0.1, 0.15), vec3<f32>(0.1, 0.05, 0.1), clamp(p.y, 0.0, 1.0));

        color = baseColor * (diff * 0.5 + 0.5) * sss;
        let emission = vec3<f32>(0.0, 0.8, 1.0) * glow * u.zoom_params.w;
        color += emission;
        color = mix(color, vec3<f32>(0.0, 0.01, 0.03), 1.0 - exp(-0.05 * t));
        out_depth = t / 20.0;
    } else {
        color = vec3<f32>(0.0, 0.02, 0.05) * glow * 0.1;
    }

    textureStore(writeTexture, id.xy, vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(out_depth, out_depth, out_depth, 1.0));
    textureStore(dataTextureA, id.xy, vec4<f32>(n, 1.0));
}