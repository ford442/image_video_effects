// ----------------------------------------------------------------
// Sentient Plasma-Silk Nebula Forge
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
fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557);
    return a + b * cos(TAU * (c * t + d + u.zoom_params.w));
}

// SDF
fn map(p: vec3<f32>) -> vec2<f32> {
    var q = p;
    let time = u.config.x * u.zoom_params.y;

    if (u.zoom_config.w > 0.0) {
        let mouse_pos = vec2<f32>(u.zoom_config.y - 0.5, (1.0 - u.zoom_config.z) - 0.5) * 5.0;
        let dist = length(q.xy - mouse_pos);
        let pull = exp(-dist * 2.0);
        let qxy = q.xy - mouse_pos * pull;
        q = vec3<f32>(qxy, q.z);
    }

    let rot = rot2D(time * 0.3 + length(q) * 0.4);
    let qxz = q.xz * rot;
    q = vec3<f32>(qxz.x, q.y, qxz.y);

    var d = 100.0;
    let density = u.zoom_params.x * 2.0 + 1.0;

    for (var i = 0; i < 4; i++) {
        let fi = f32(i);
        q = abs(q) - vec3<f32>(0.5) * density;
        let qr = q.xy * rot2D(time * 0.15 + fi);
        q = vec3<f32>(qr, q.z);
        let cyl = length(q.xy) - 0.06 * (fi + 1.0);
        d = min(d, cyl);
    }

    let sphere = length(p) - 0.9;

    let k = 0.5;
    let h = clamp(0.5 + 0.5 * (sphere - d) / k, 0.0, 1.0);
    let d_res = mix(sphere, d, h) - k * h * (1.0 - h);
    return vec2<f32>(d_res, d_res);
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
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let coords = vec2<i32>(id.xy);
    if (f32(coords.x) >= resolution.x || f32(coords.y) >= resolution.y) {
        return;
    }

    let uv = (vec2<f32>(id.xy) - 0.5 * resolution) / resolution.y;
    let time = u.config.x;

    // Audio reactivity
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    let audio_mod = bass * 0.5 + mids * 0.3 + treble * 0.2;

    var ro = vec3<f32>(0.0, 0.0, -3.5);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0;
    var d = 0.0;
    var glow = 0.0;
    var hit = false;
    var steps: i32 = 0;
    var p = vec3<f32>(0.0);

    for (var i = 0; i < 80; i++) {
        steps = i;
        p = ro + rd * t;
        d = map(p).x;

        // Add core glow
        glow += 0.05 / (0.05 + abs(d)) * u.zoom_params.z * (1.0 + audio_mod);

        if (d < 0.001) {
            hit = true;
            break;
        }
        if (t > 10.0) {
            break;
        }
        t += d * 0.8; // conservative stepping
    }

    // Base background
    var col = vec3<f32>(0.02, 0.0, 0.08);
    var out_n = vec3<f32>(0.0);

    if (hit) {
        let n = get_normal(p);
        out_n = n;
        let l = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, l), 0.0);

        // Ambient occlusion based on step count
        let ao = 1.0 - f32(steps) / 80.0;

        let pal_t = length(p) * 0.2 + f32(steps) * 0.01 + time * 0.1;
        let objCol = palette(pal_t);

        col = objCol * diff * ao;
    }

    col += vec3<f32>(1.0, 0.4, 0.8) * glow * 0.1; // hot pink glow

    // Smooth bloom/tonemapping
    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(0.4545)); // gamma correction

    let depth = clamp(1.0 - t/10.0, 0.0, 1.0);

    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coords, vec4<f32>(col, 1.0));
}