// ═══════════════════════════════════════════════════════════════════
//  Kryonic Quantum-Aether Fractal-Core
//  Category: generative
//  Features: generative, mouse-driven, audio-reactive, raymarched, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-13
//  Ideas: frost-rime orbit trap; aether shatter veins along fold mirror planes
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

fn fold(p: vec3<f32>) -> vec3<f32> {
    var p_mut = p;
    p_mut = abs(p_mut);
    if (p_mut.x < p_mut.y) { p_mut = p_mut.yxz; }
    if (p_mut.x < p_mut.z) { p_mut = p_mut.zyx; }
    if (p_mut.y < p_mut.z) { p_mut = p_mut.xzy; }
    return p_mut;
}

fn rot2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash31(p: f32) -> vec3<f32> {
    var p3 = fract(vec3<f32>(p) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + vec3<f32>(33.33));
    return fract((p3.xxy + p3.yzz) * p3.zyx);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

fn map(p: vec3<f32>, time: f32, scale: f32, melt: f32, audio: f32, shatter: f32) -> f32 {
    var q = p;
    let t = time * 0.2;

    let qxy = rot2D(t) * vec2<f32>(q.x, q.y);
    q.x = qxy.x; q.y = qxy.y;
    let qyz = rot2D(t * 0.7) * vec2<f32>(q.y, q.z);
    q.y = qyz.x; q.z = qyz.y;

    var scale_factor = 1.0;
    let s = scale * (1.0 + audio * 0.1);

    for (var i = 0; i < 5; i++) {
        q = fold(q);
        q = q * s - vec3<f32>(1.2, 1.2, 1.2);
        scale_factor *= s;

        let rot = rot2D(t + f32(i) * 0.5);
        let qxz = rot * vec2<f32>(q.x, q.z);
        q.x = qxz.x; q.z = qxz.y;
    }

    var d = length(q) / scale_factor - 0.02;

    let noise_offset = length(sin(p * 10.0 + vec3<f32>(time))) * 0.05 * shatter * audio;
    d += noise_offset;

    let melt_sphere = length(p) - (1.0 + melt);
    d = select(d, smin(d, melt_sphere, max(melt * 2.0, 0.0001)), melt > 0.0);

    return d;
}

// Idea 1 + 2: replay map()'s fold loop once at the hit and keep its orbit data.
// x = min orbit radius (rime trap), y = min distance to the sorted-abs mirror planes (shatter seams).
fn foldTraps(p: vec3<f32>, time: f32, scale: f32, audio: f32) -> vec2<f32> {
    var q = p;
    let t = time * 0.2;
    let qxy = rot2D(t) * vec2<f32>(q.x, q.y);
    q.x = qxy.x; q.y = qxy.y;
    let qyz = rot2D(t * 0.7) * vec2<f32>(q.y, q.z);
    q.y = qyz.x; q.z = qyz.y;

    let s = scale * (1.0 + audio * 0.1);
    var sf = 1.0;
    var orbit = 1e5;
    var seam = 1e5;
    for (var i = 0; i < 5; i++) {
        let a = abs(q);
        let plane = min(min(abs(a.x - a.y), abs(a.x - a.z)), abs(a.y - a.z)) * 0.7071;
        seam = min(seam, plane / sf);
        q = fold(q);
        q = q * s - vec3<f32>(1.2, 1.2, 1.2);
        sf *= s;
        orbit = min(orbit, length(q) / sf);
        let rot = rot2D(t + f32(i) * 0.5);
        let qxz = rot * vec2<f32>(q.x, q.z);
        q.x = qxz.x; q.z = qxz.y;
    }
    return vec2<f32>(orbit, seam);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn calcNormal(p: vec3<f32>, time: f32, scale: f32, melt: f32, audio: f32, shatter: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy, time, scale, melt, audio, shatter) - map(p - e.xyy, time, scale, melt, audio, shatter),
        map(p + e.yxy, time, scale, melt, audio, shatter) - map(p - e.yxy, time, scale, melt, audio, shatter),
        map(p + e.yyx, time, scale, melt, audio, shatter) - map(p - e.yyx, time, scale, melt, audio, shatter)
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let coords = vec2<i32>(i32(id.x), i32(id.y));
    if (f32(coords.x) >= res.x || f32(coords.y) >= res.y) { return; }

    let time = u.config.x;
    let audio = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z) * res;

    let scale_param = u.zoom_params.x; // default 1.5
    let shatter_param = u.zoom_params.y; // default 0.5
    let glow_param = u.zoom_params.z; // default 1.0
    let melt_param = u.zoom_params.w; // default 0.2

    let uv = (vec2<f32>(coords) - 0.5 * res) / res.y;
    let m_uv = (mouse - 0.5 * res) / res.y;

    var ro = vec3<f32>(0.0, 0.0, -3.0);
    let ta = vec3<f32>(0.0, 0.0, 0.0);
    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = normalize(cross(cu, cw));
    var rd = normalize(uv.x * cu + uv.y * cv + 1.5 * cw);

    // Mouse tracking rot
    let mouse_rot_x = rot2D(m_uv.x * PI);
    let rd_xz = mouse_rot_x * vec2<f32>(rd.x, rd.z);
    rd.x = rd_xz.x; rd.z = rd_xz.y;

    let ro_xz = mouse_rot_x * vec2<f32>(ro.x, ro.z);
    ro.x = ro_xz.x; ro.z = ro_xz.y;

    let mouse_dist = length(uv - m_uv);
    let active_melt = melt_param * smoothstep(0.5, 0.0, mouse_dist);

    var t = 0.0;
    var d = 0.0;
    var p = ro;
    var glow = vec3<f32>(0.0);

    for (var i = 0; i < 80; i++) {
        p = ro + rd * t;
        d = map(p, time, scale_param, active_melt, audio, shatter_param);

        if (d < 0.001 || t > 10.0) { break; }

        t += d * 0.5; // step small for volumetric effect

        // Volumetric aether-fog and shattering glow
        let glow_col = vec3<f32>(0.1, 0.4, 0.9) + vec3<f32>(0.8, 0.2, 0.9) * audio;
        glow += glow_col * 0.02 / (1.0 + d * d * 50.0) * glow_param;
    }

    var col = vec3<f32>(0.0);

    if (t < 10.0) {
        let n = calcNormal(p, time, scale_param, active_melt, audio, shatter_param);

        let l = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let dif = max(dot(n, l), 0.0);
        let reflectionDir = reflect(rd, n);
        let spec = pow(max(dot(reflectionDir, l), 0.0), 32.0);

        let base_col = vec3<f32>(0.05, 0.1, 0.2);
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 5.0);

        col = base_col * dif + spec * vec3<f32>(0.8, 0.9, 1.0) + fresnel * vec3<f32>(0.2, 0.8, 1.0);

        // Chromatic edges
        col += vec3<f32>(0.1, 0.5, 0.9) * (1.0 - n.z);

        let traps = foldTraps(p, time, scale_param, audio);

        // Idea 1: frost-rime orbit trap — tight fold tips crust white, recesses sink to glacial blue
        let rime = 1.0 - smoothstep(0.0, 0.06, traps.x);
        let frost = mix(vec3<f32>(0.02, 0.12, 0.35), vec3<f32>(0.85, 0.95, 1.0), rime);
        col = mix(col, col * 0.4 + frost * (0.35 + dif * 0.9), 0.55) + vec3<f32>(0.9, 0.97, 1.0) * rime * spec * 1.5;

        // Idea 2: aether shatter veins — plasma cracks along the fold mirror seams, thawed inside the melt
        let veinWidth = 0.004 + 0.012 * shatter_param * (1.0 + treble * 0.6);
        let vein = (1.0 - smoothstep(0.0, veinWidth, traps.y)) * (1.0 - smoothstep(0.0, 0.6, active_melt));
        let veinCol = mix(vec3<f32>(0.2, 0.9, 1.0), vec3<f32>(0.95, 0.25, 1.0), clamp(mids + 0.5 * sin(time * 1.3 + traps.x * 60.0) + 0.5, 0.0, 1.0));
        col += veinCol * vein * shatter_param * (1.2 + audio * 1.5);
    }

    col += glow;

    // deep cyan, glacial blue, void black
    col = mix(col, vec3<f32>(0.0, 0.05, 0.1), smoothstep(0.0, 10.0, t));
    col += vec3<f32>(0.05, 0.0, 0.1) * treble * 0.3;

    let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let semantic_alpha = clamp(luma * 1.6 + length(glow) * 0.3, 0.05, 0.98);
    let outDepth = clamp(t / 10.0, 0.0, 1.0);
    let display = acesToneMap(col * 1.2);

    textureStore(writeTexture, coords, vec4<f32>(display, semantic_alpha));
    textureStore(writeDepthTexture, coords, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coords, vec4<f32>(display, semantic_alpha));
}
