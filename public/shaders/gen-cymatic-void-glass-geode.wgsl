// ----------------------------------------------------------------
// Cymatic Void-Glass Geode
// Category: generative
// ----------------------------------------------------------------
#include "_prelude.wgsl"

const MAX_STEPS = 100;
const SURF_DIST = 0.001;
const MAX_DIST = 10.0;

// Palette function for iridescence
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

// 2D Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// SDF with Apollonian fractal and Cymatic displacement
fn map(p: vec3<f32>) -> vec2<f32> { // returns vec2(distance, orbit_trap)
    var q = p;
    let time = u.config.x * u.zoom_params.x; // Speed param

    // Mouse gravity well distortion
    let mouse_uv = u.zoom_config.yz * 2.0 - 1.0;
    let mouse_pos = vec3<f32>(mouse_uv.x, -mouse_uv.y, 0.0);
    if (u.zoom_config.w > 0.5) {
        let dir = mouse_pos - q;
        let dist = length(dir);
        q += normalize(dir) * (0.5 * u.zoom_params.w) / (dist + 0.1); // Gravity param
    }

    var scale = 1.0;
    var orb = 1000.0;

    // Apollonian folding
    for (var i = 0; i < 4; i++) {
        q = -1.0 + 2.0 * fract(0.5 * q + 0.5);
        let r2 = dot(q, q);
        orb = min(orb, r2);
        let k = 1.2 / r2;
        q *= k;
        scale *= k;

        let a = f32(i) * 0.5 + time * 0.1;
        let new_xy = rot(a) * q.xy;
        q.x = new_xy.x;
        q.y = new_xy.y;
    }

    let base_sdf = (length(q) - 0.25) / scale;

    // Audio reactivity mapping from dataTextureC
    let audio_sample = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).x;
    let audio_mod = 1.0 + audio_sample * 2.0; // Moderate effect

    // Cymatic displacement
    let freq = u.zoom_params.y * 10.0; // Frequency param
    let amp = u.zoom_params.z * 0.1 * audio_mod;   // Amplitude param mod with audio
    let disp = sin(length(p) * freq - time) * cos(atan2(p.y, p.x) * 4.0) * amp;

    return vec2<f32>(base_sdf + disp, orb);
}

// Raymarching
fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec3<f32> { // returns vec3(distance, steps, orbit_trap)
    var dO = 0.0;
    var min_orb = 1000.0;
    var i = 0;
    for (; i < MAX_STEPS; i++) {
        let p = ro + rd * dO;
        let res = map(p);
        let dS = res.x;
        min_orb = min(min_orb, res.y);
        dO += dS;
        if (dO > MAX_DIST || abs(dS) < SURF_DIST) { break; }
    }
    return vec3<f32>(dO, f32(i), min_orb);
}

// Normal calculation
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.zw);
    let fragCoord = vec2<f32>(id.xy);
    if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }

    var uv = (fragCoord - 0.5 * res) / res.y;
    let time = u.config.x;

    // Camera setup
    let ro = vec3<f32>(0.0, 0.0, -2.0 + sin(time*0.2)*0.5); // Slight dolly
    let lookat = vec3<f32>(0.0, 0.0, 0.0);
    let zoom = 1.0;

    let f = normalize(lookat - ro);
    let r = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), f));
    let u_cam = cross(f, r);
    var rd = normalize(uv.x * r + uv.y * u_cam + f * zoom);

    // Raymarch
    let rm = raymarch(ro, rd);
    let d = rm.x;
    let steps = rm.y;
    let orb = rm.z;

    var col = vec3<f32>(0.0);

    if (d < MAX_DIST) {
        let p = ro + rd * d;
        let n = calcNormal(p);

        // Lighting
        let lightDir = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let viewDir = normalize(ro - p);

        // Iridescence (Void-Glass effect)
        let fresnel = pow(1.0 - max(dot(n, viewDir), 0.0), 5.0);
        let iri_color = palette(fresnel + orb * 0.1,
                                vec3<f32>(0.5, 0.5, 0.5),
                                vec3<f32>(0.5, 0.5, 0.5),
                                vec3<f32>(1.0, 1.0, 1.0),
                                vec3<f32>(0.0, 0.33, 0.67));

        // Inner Glow (Veins)
        let glow = exp(-orb * 5.0) * vec3<f32>(0.2, 0.8, 1.0);

        col = (diff * 0.2 + iri_color * 0.8) * (1.0 - fresnel * 0.5) + glow;

        // Subsurface scattering approximation based on step count
        col += vec3<f32>(0.1, 0.05, 0.2) * (steps / f32(MAX_STEPS));
    } else {
        // Deep space background
        col = vec3<f32>(0.0, 0.0, 0.02) * (1.0 - length(uv));
    }

    // Gamma correction
    col = pow(col, vec3<f32>(0.4545));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
