// ----------------------------------------------------------------
// Luminescent Singularity Loom
// Category: generative
// ----------------------------------------------------------------

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// Helper: 2D Rotation
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Helper: Palette
fn palette(t: f32, shift: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557) + shift; // Shift this based on zoom_params.w
    return a + b * cos(TAU * (c * t + d));
}

// Map function (SDF)
fn map(p: vec3<f32>) -> vec2<f32> {
    // Loom distortion
    var q = p;
    let time = u.config.x * u.zoom_params.y;

    // Mouse Interaction: Gravity Well
    if (u.zoom_config.w > 0.0) {
        let mouse_pos = vec2<f32>(u.zoom_config.y - 0.5, (1.0 - u.zoom_config.z) - 0.5) * 5.0; // rough mapping
        let dist_to_mouse = length(q.xy - mouse_pos);
        let pull = exp(-dist_to_mouse * 2.0);

        let qxy = q.xy - mouse_pos * pull;
        q = vec3<f32>(qxy, q.z);
    }

    // Space folding
    let rot = rot2D(time * 0.2 + length(q) * 0.5);
    let qxz = q.xz * rot;
    q = vec3<f32>(qxz.x, q.y, qxz.y);

    // Threads (fractal cylinders)
    var d = 100.0;
    let density = u.zoom_params.x * 2.0 + 1.0;

    for (var i = 0; i < 4; i++) {
        let fi = f32(i);
        q = abs(q) - vec3<f32>(0.5, 0.5, 0.5) * density;
        let qr = q.xy * rot2D(time * 0.1 + fi);
        q = vec3<f32>(qr, q.z);
        let cyl = length(q.xy) - 0.05 * (fi + 1.0);
        d = min(d, cyl);
    }

    // Central Singularity
    let sphere = length(p) - 0.8;

    // Combine with smooth minimum
    let k = 0.5;
    let h = clamp(0.5 + 0.5 * (sphere - d) / k, 0.0, 1.0);
    let dist = mix(sphere, d, h) - k * h * (1.0 - h);

    // We return dist and a material ID for coloring
    let mat_id = mix(0.0, 1.0, h);
    return vec2<f32>(dist, mat_id);
}

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
    let resolution = vec2<f32>(u.config.zw);
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) {
        return;
    }

    let fragCoord = vec2<f32>(f32(id.x) + 0.5, f32(id.y) + 0.5);
    let uv = (fragCoord - 0.5 * resolution) / resolution.y;

    // Camera setup
    let ro = vec3<f32>(0.0, 0.0, -4.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var t: f32 = 0.0;
    var d: f32 = 0.0;
    var m: f32 = 0.0;
    var p: vec3<f32>;

    var i: i32 = 0;
    for (i = 0; i < 100; i++) {
        p = ro + rd * t;
        let res = map(p);
        d = res.x;
        m = res.y;
        if (d < 0.001 || t > 20.0) { break; }
        t += d;
    }

    var col = vec3<f32>(0.05, 0.0, 0.1); // Base void color
    var depth = 1.0;
    var normal = vec3<f32>(0.0);

    if (t < 20.0) {
        normal = get_normal(p);

        // Lighting
        let lightPos = vec3<f32>(2.0, 4.0, -3.0);
        let l = normalize(lightPos - p);

        let dif = max(dot(normal, l), 0.0);
        let amb = 0.1 + 0.9 * max(0.0, normal.y);

        // Subsurface scattering / inner glow approximation
        let sss = map(p + normal * 0.1).x;
        let sssGlow = max(0.0, 0.1 - sss) * 10.0 * u.zoom_params.z;

        // Color based on material ID and position
        let baseCol = palette(m + length(p) * 0.2 + u.config.x * 0.1, u.zoom_params.w);

        col = baseCol * (dif * 0.5 + amb * 0.5);
        col += baseCol * sssGlow; // Add subsurface glow

        // Add fake emission
        col += baseCol * u.zoom_params.z * smoothstep(0.8, 1.0, 1.0 - m);

        depth = t / 20.0;
    }

    // Fog / atmospheric scattering
    col = mix(col, vec3<f32>(0.05, 0.0, 0.1), 1.0 - exp(-0.02 * t * t));

    // Gamma correction
    col = pow(col, vec3<f32>(1.0 / 2.2));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(id.xy), vec4<f32>(normal, 1.0));
}
