// ----------------------------------------------------------------
// Ethereal Cyber-Aurora Mantis-Shrine
// Category: generative
// ----------------------------------------------------------------
#include "_prelude.wgsl"

const MAX_STEPS = 100;
const SURF_DIST = 0.001;
const MAX_DIST = 20.0;

// Palette function for auroral colors
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

// 2D Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Smooth minimum
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Capsule SDF
fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

// Torus SDF
fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

// Noise for mist and filaments
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(q) * 43758.5453) * 2.0 - 1.0;
}

fn noise3(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let u = f * f * (3.0 - 2.0 * f);

    return mix(mix(mix(dot(hash3(p + vec3<f32>(0.0, 0.0, 0.0)), f - vec3<f32>(0.0, 0.0, 0.0)),
                       dot(hash3(p + vec3<f32>(1.0, 0.0, 0.0)), f - vec3<f32>(1.0, 0.0, 0.0)), u.x),
                   mix(dot(hash3(p + vec3<f32>(0.0, 1.0, 0.0)), f - vec3<f32>(0.0, 1.0, 0.0)),
                       dot(hash3(p + vec3<f32>(1.0, 1.0, 0.0)), f - vec3<f32>(1.0, 1.0, 0.0)), u.x), u.y),
               mix(mix(dot(hash3(p + vec3<f32>(0.0, 0.0, 1.0)), f - vec3<f32>(0.0, 0.0, 1.0)),
                       dot(hash3(p + vec3<f32>(1.0, 0.0, 1.0)), f - vec3<f32>(1.0, 0.0, 1.0)), u.x),
                   mix(dot(hash3(p + vec3<f32>(0.0, 1.0, 1.0)), f - vec3<f32>(0.0, 1.0, 1.0)),
                       dot(hash3(p + vec3<f32>(1.0, 1.0, 1.0)), f - vec3<f32>(1.0, 1.0, 1.0)), u.x), u.y), u.z);
}

// Map function returning (distance, material_id)
// material_id: 1.0 for mist, 2.0 for mantis, 3.0 for lotus, 4.0 for heart/filaments
fn map(p: vec3<f32>) -> vec2<f32> {
    var d = MAX_DIST;
    var mat = 0.0;

    let time = u.config.x;

    // Mouse Interaction
    var q = p;
    let mouse_uv = u.zoom_config.yz * 2.0 - 1.0;
    let mouse_pos = vec3<f32>(mouse_uv.x * 5.0, -mouse_uv.y * 5.0, 0.0);

    if (u.zoom_config.w > 0.5) { // Click triggered burst
        let dist = length(q - mouse_pos);
        let ripple = sin(dist * 10.0 - time * 5.0) * exp(-dist * 0.5) * 0.2;
        q += normalize(q - mouse_pos) * ripple;
    }

    // --- 1. Mist (FBM) ---
    let mist_fbm = noise3(q * 0.5 + vec3<f32>(time * 0.1)) * 0.5 + noise3(q * 1.0 - vec3<f32>(time * 0.2)) * 0.25;
    let mist_d = -p.y + 2.0 - mist_fbm * u.zoom_params.z * 5.0; // Ground mist

    // --- 2. Mantis ---
    var mantis_d = MAX_DIST;
    let m_scale = u.zoom_params.x;
    var mp = q / m_scale;
    mp.y -= 1.0 + sin(time) * 0.2; // Hovering

    // Thorax
    mantis_d = sdCapsule(mp, vec3<f32>(0.0, 0.5, 0.0), vec3<f32>(0.0, -0.5, -0.2), 0.3);
    // Head
    let head = length(vec3<f32>(abs(mp.x), mp.y - 0.7, mp.z + 0.1) * vec3<f32>(1.0, 1.2, 0.8)) - 0.2;
    mantis_d = smin(mantis_d, head, 0.1);

    // Arms
    var amp = mp;
    amp.x = abs(amp.x); // symmetry
    let arm1 = sdCapsule(amp, vec3<f32>(0.3, 0.4, 0.0), vec3<f32>(0.8, 0.6, 0.5), 0.05);
    let arm2 = sdCapsule(amp, vec3<f32>(0.8, 0.6, 0.5), vec3<f32>(0.5, -0.2, 0.8), 0.03);
    mantis_d = smin(mantis_d, smin(arm1, arm2, 0.1), 0.1);

    mantis_d *= m_scale;

    // --- 3. Lotus ---
    var lotus_d = MAX_DIST;
    var lp = q;
    lp.y += 1.0;

    let lotus_comp = u.zoom_params.y;
    for(var i=0; i<4; i++) {
        if(f32(i) > lotus_comp) { break; }
        var a = atan2(lp.x, lp.z);
        var r = length(lp.xz);
        let num_petals = 6.0 + f32(i) * 2.0;
        let p_angle = 6.28318 / num_petals;
        a = (fract(a / p_angle) - 0.5) * p_angle;
        lp.x = cos(a) * r;
        lp.z = sin(a) * r;

        let rot_mat = rot(0.5 + sin(time * 0.5 + f32(i)) * 0.2);
        let lp_xy_1 = rot_mat * lp.xy;
        lp.x = lp_xy_1.x;
        lp.y = lp_xy_1.y;
        lp.y -= 0.5 * pow(0.7, f32(i));

        let petal = sdCapsule(lp, vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(1.0, 0.0, 0.0), 0.05 + 0.1 * (1.0 - lp.x));
        lotus_d = smin(lotus_d, petal, 0.2);
    }

    // --- 4. Heart Pulse & Filaments ---
    let audio_sample = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).x;
    let pulse = u.zoom_params.w * (1.0 + audio_sample * 5.0);

    // Heart
    var hp = mp;
    hp.y -= 0.2;
    let rot_h = rot(time);
    let hp_xz_2 = rot_h * hp.xz;
    hp.x = hp_xz_2.x;
    hp.z = hp_xz_2.y;
    let hp_xy_3 = rot_h * hp.xy;
    hp.x = hp_xy_3.x;
    hp.y = hp_xy_3.y;
    let heart = (length(hp) - 0.15) * m_scale;

    // Filaments (Connecting arms to lotus)
    let f_disp = noise3(q * 5.0 - vec3<f32>(0.0, time * 2.0, 0.0)) * 0.02;
    let filaments = sdCapsule(amp, vec3<f32>(0.5, -0.2, 0.8), vec3<f32>(1.0, -1.0, 0.0), 0.01) * m_scale + f_disp;

    let emissive_d = smin(heart, filaments, 0.1) - pulse * 0.01;

    // Combine
    if (mist_d < d) { d = mist_d; mat = 1.0; }
    if (lotus_d < d) { d = lotus_d; mat = 3.0; }
    if (mantis_d < d) { d = mantis_d; mat = 2.0; }
    if (emissive_d < d) { d = emissive_d; mat = 4.0; }

    // Smooth blending between lotus and mantis
    if (mat == 2.0 || mat == 3.0) {
        d = smin(mantis_d, lotus_d, 0.5);
        mat = select(3.0, 2.0, mantis_d < lotus_d); // Approximate material
    }

    return vec2<f32>(d * 0.5, mat); // Distance under-relaxation for fractals/noise
}

// Raymarching
fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec3<f32> {
    var dO = 0.0;
    var mat = 0.0;
    var mist_dens = 0.0;

    for (var i = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * dO;
        let res = map(p);
        let dS = res.x;

        if(res.y == 1.0 && dS < 0.1) {
            mist_dens += 0.05 * (0.1 - dS); // Accumulate mist
        }

        dO += max(dS, 0.01); // Prevent getting stuck
        mat = res.y;

        if (dO > MAX_DIST || (dS < SURF_DIST && res.y != 1.0)) { break; }
    }
    return vec3<f32>(dO, mat, mist_dens);
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

    // Mouse orbit
    let mouse_uv = u.zoom_config.yz * 2.0 - 1.0;

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, -5.0);

    let cam_rot_x = rot(-mouse_uv.y * 1.5);
    let cam_rot_y = rot(mouse_uv.x * 3.14 + time * 0.1);

    let ro_yz_4 = cam_rot_x * ro.yz;
    ro.y = ro_yz_4.x;
    ro.z = ro_yz_4.y;
    let ro_xz_5 = cam_rot_y * ro.xz;
    ro.x = ro_xz_5.x;
    ro.z = ro_xz_5.y;

    let lookat = vec3<f32>(0.0, 0.0, 0.0);
    let zoom = 1.0;

    let f = normalize(lookat - ro);
    let r = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), f));
    let u_cam = cross(f, r);
    var rd = normalize(uv.x * r + uv.y * u_cam + f * zoom);

    // Raymarch
    let rm = raymarch(ro, rd);
    let d = rm.x;
    let mat = rm.y;
    let mist = rm.z;

    var col = vec3<f32>(0.0);

    if (d < MAX_DIST && mat != 1.0) {
        let p = ro + rd * d;
        let n = calcNormal(p);
        let viewDir = normalize(ro - p);

        // Lighting
        let lightDir = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let spec = pow(max(dot(reflect(-lightDir, n), viewDir), 0.0), 32.0);
        let fresnel = pow(1.0 - max(dot(n, viewDir), 0.0), 5.0);

        if (mat == 2.0) { // Mantis (Liquid Chrome)
            let base = vec3<f32>(0.1, 0.15, 0.2);
            col = base * diff + vec3<f32>(1.0) * spec + vec3<f32>(0.4, 0.8, 1.0) * fresnel;
        } else if (mat == 3.0) { // Lotus (Auroral Plasma)
            let base = palette(length(p) * 0.5 - time,
                               vec3<f32>(0.5), vec3<f32>(0.5),
                               vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(0.3, 0.1, 0.6));
            col = base * (diff * 0.5 + 0.5) + base * fresnel * 2.0;
        } else if (mat == 4.0) { // Heart/Filaments (Emissive)
            let audio_sample = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).x;
            let intensity = u.zoom_params.w * (1.0 + audio_sample * 2.0);
            col = vec3<f32>(0.1, 0.9, 1.0) * intensity * 2.0;
        }
    }

    // Add Mist Volumetrics
    col += vec3<f32>(0.1, 0.3, 0.5) * mist;

    // Background (Nebula)
    if (d >= MAX_DIST) {
        let bg_noise = noise3(rd * 3.0);
        col += vec3<f32>(0.02, 0.05, 0.1) * bg_noise;
    }

    // Gamma correction
    col = pow(max(col, vec3<f32>(0.0)), vec3<f32>(0.4545));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(select(0.0, 1.0 - clamp(d / MAX_DIST, 0.0, 1.0), d < MAX_DIST), 0.0, 0.0, 0.0));
}
