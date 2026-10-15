// ----------------------------------------------------------------
// Neon Geode Crystallization
// Category: generative
// ----------------------------------------------------------------
#include "_prelude.wgsl"

fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn map(p_in: vec3<f32>) -> f32 {
    var p = p_in;

    // Twist based on zoom_params.w
    let twist = u.zoom_params.w;
    let a = twist * p.y;
    let r = rot2D(a);
    let qxy = p.xz * r;
    p = vec3<f32>(qxy.x, p.y, qxy.y);

    // Fold based on zoom_params.y
    let fold = u.zoom_params.y;
    p = abs(p) - vec3<f32>(fold);
    if (p.x < p.y) { let temp = p.x; p.x = p.y; p.y = temp; }
    if (p.x < p.z) { let temp = p.x; p.x = p.z; p.z = temp; }
    if (p.y < p.z) { let temp = p.y; p.y = p.z; p.z = temp; }

    // Domain repetition
    p = p - floor(p / 4.0) * 4.0 - 2.0;

    // Base Box SDF
    let d = length(max(abs(p) - vec3<f32>(1.0), vec3<f32>(0.0)));

    // Noise/Displacement for organic plasma veins
    let noise = sin(p.x * 5.0 + u.config.x) * sin(p.y * 5.0) * sin(p.z * 5.0) * 0.1;
    return d + noise;
}

fn get_normal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let coord = vec2<f32>(f32(id.x), f32(id.y));
    if (coord.x >= dims.x || coord.y >= dims.y) { return; }

    let uv = (coord - 0.5 * dims) / min(dims.x, dims.y);
    let time = u.config.x;

    // Audio reactivity
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    var ro = vec3<f32>(0.0, 0.0, -5.0 + u.config.x * 0.5);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Mouse Interaction
    if (u.zoom_config.w > 0.5) {
        let mouse_uv = u.zoom_config.yz;
        let diff = vec3<f32>(mouse_uv, 0.0) - ro;
        rd = normalize(rd + diff * 0.1);
    }

    var dO = 0.0;
    var steps: i32 = 0;
    var hit = false;

    for (var i = 0; i < 100; i = i + 1) {
        steps = i;
        let p = ro + rd * dO;
        let dS = map(p);
        if (dS < 0.001) { hit = true; break; }
        if (dO > 100.0) { break; }
        dO += dS;
    }

    var col = vec3<f32>(0.0);
    var out_n = vec3<f32>(0.0, 0.0, 1.0);

    if (hit) {
        let p = ro + rd * dO;
        out_n = get_normal(p);

        // Base metallic shading
        let intensity = u.zoom_params.x + bass * 0.5; // Plasma Intensity
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(out_n, lightDir), 0.0);

        // Fake bloom based on raymarch step counts
        let bloom = f32(steps) / 100.0 * u.zoom_params.z * treble; // Bloom Radius

        col = vec3<f32>(0.1, 0.5, 1.0) * diff * intensity + vec3<f32>(1.0, 0.2, 0.8) * bloom;
    }

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(dO, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(id.xy), vec4<f32>(out_n, 1.0));
}