// ----------------------------------------------------------------
// Harmonic Ferrofluid Kinetics
// Category: generative
// ----------------------------------------------------------------
#include "_prelude.wgsl"

const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 50.0;
const SURF_DIST: f32 = 0.001;

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(q) * 43758.5453123);
}

fn voronoi(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    var res = 8.0;
    for (var k = -1; k <= 1; k++) {
        for (var j = -1; j <= 1; j++) {
            for (var i = -1; i <= 1; i++) {
                let b = vec3<f32>(f32(i), f32(j), f32(k));
                let r = vec3<f32>(b) - f + hash3(p + b);
                let d = dot(r, r);
                res = min(res, d);
            }
        }
    }
    return sqrt(res);
}

fn map(p: vec3<f32>) -> f32 {
    var pos = p;
    let time = u.config.x * u.zoom_params.y; // speed parameter

    // Domain distortion
    pos.x += sin(pos.z * 0.5 + time) * 0.5;
    pos.z += cos(pos.x * 0.5 + time * 0.8) * 0.5;

    // Base plane height
    var h = 0.0;

    // Magnetic fluid spikes (Voronoi)
    let spike_scale = u.zoom_params.x * 5.0;
    let spikes = voronoi(pos * spike_scale) * (2.0 / spike_scale);

    // Inverse spikes for ferrofluid look
    h += 1.0 - smoothstep(0.0, 0.5, spikes);

    // Mouse magnetic well
    let mouse = u.zoom_config.yz;
    let is_pressed = u.zoom_config.w;
    if (is_pressed > 0.5) {
        let mouse_pos = vec3<f32>((mouse.x - 0.5) * 10.0, 0.0, (mouse.y - 0.5) * 10.0);
        let dist_to_mouse = length(p.xz - mouse_pos.xz);
        h += exp(-dist_to_mouse * 2.0) * 1.5;
    }

    // Displacement
    let d = p.y - h;
    return d * 0.5;
}

fn get_normal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) { return; }

    var uv = vec2<f32>(id.xy) / resolution;
    uv = uv * 2.0 - 1.0;
    uv.x *= resolution.x / resolution.y;

    let ro = vec3<f32>(0.0, 3.0, -5.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var d0 = 0.0;
    var p = ro;
    var hit = false;

    for (var i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * d0;
        let dS = map(p);
        d0 += dS;
        if (dS < SURF_DIST) {
            hit = true;
            break;
        }
        if (d0 > MAX_DIST) { break; }
    }

    var col = vec3<f32>(0.05, 0.05, 0.08); // Background

    if (hit) {
        let n = get_normal(p);
        let light_dir = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let view_dir = normalize(ro - p);
        let half_vec = normalize(light_dir + view_dir);

        let diff = max(dot(n, light_dir), 0.0);

        // Anisotropic specular
        let spec_power = u.zoom_params.z * 100.0 + 10.0;
        var spec = pow(max(dot(n, half_vec), 0.0), spec_power);

        // Iridescence based on view angle
        let fresnel = 1.0 - max(dot(n, view_dir), 0.0);
        let iridescence = 0.5 + 0.5 * cos(u.config.x + fresnel * 5.0 + vec3<f32>(0.0, 2.0, 4.0));

        let base_color = vec3<f32>(0.1, 0.1, 0.12);

        col = base_color * diff + iridescence * spec;

        // Ambient occlusion (cheap)
        let ao = clamp(map(p + n * 0.5) * 2.0, 0.0, 1.0);
        col *= ao;

        // Subsurface scattering
        let subsurface = vec3<f32>(0.8, 0.3, 0.1) * fresnel * u.zoom_params.w * ao;
        col += subsurface;

        // Distance fog
        col = mix(col, vec3<f32>(0.05, 0.05, 0.08), 1.0 - exp(-0.02 * d0 * d0));
    }

    // Output
    let final_color = vec4<f32>(col, 1.0);
    textureStore(writeTexture, id.xy, final_color);
}