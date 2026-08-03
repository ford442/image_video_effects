// ----------------------------------------------------------------
// Luminescent Aether-Plasma Astro-Axolotl
// Category: generative
// Upgraded: 2026-08-03 — Interactivist b31: orbit cam, ripples, FFT gill fold.
// ----------------------------------------------------------------
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

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, yz=MouseUV (0-1, y=0 top), w=MouseDown
    zoom_params: vec4<f32>,  // x=Gill Expansion, y=Current Warp, z=Nebula Density, w=Bioluminescence
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const MAX_DIST: f32 = 10.0;

fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn rotY(a: f32) -> mat3x3<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}

fn rotX(a: f32) -> mat3x3<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

fn hash(p: vec3<f32>) -> f32 {
    let q = fract(p * vec3<f32>(17.1, 31.7, 47.9));
    return fract(sin(dot(q, vec3<f32>(12.9898, 78.233, 37.719))) * 43758.5453);
}

fn noise(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f_pow = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash(p + vec3<f32>(0.0, 0.0, 0.0)), hash(p + vec3<f32>(1.0, 0.0, 0.0)), f_pow.x),
                   mix(hash(p + vec3<f32>(0.0, 1.0, 0.0)), hash(p + vec3<f32>(1.0, 1.0, 0.0)), f_pow.x), f_pow.y),
               mix(mix(hash(p + vec3<f32>(0.0, 0.0, 1.0)), hash(p + vec3<f32>(1.0, 0.0, 1.0)), f_pow.x),
                   mix(hash(p + vec3<f32>(0.0, 1.0, 1.0)), hash(p + vec3<f32>(1.0, 1.0, 1.0)), f_pow.x), f_pow.y), f_pow.z);
}

// Engine FFT bins live at extraBuffer[5..132] (bin 0 at [5]) — read-only.
fn fftBin(i: u32) -> f32 {
    let idx = clamp(5u + i, 5u, 132u);
    if (idx < arrayLength(&extraBuffer)) {
        return extraBuffer[idx];
    }
    return 0.0;
}

// Click-ripple deformation field (0-1 uv space, y=0 top — matches engine ripples).
fn rippleField(uv01: vec2<f32>, time: f32) -> f32 {
    var acc = 0.0;
    let n = min(u32(u.config.y), 50u);
    for (var i = 0u; i < n; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age > 0.0 && age < 4.0) {
            let d = distance(uv01, rp.xy);
            let wave = d - age * 0.4;
            acc += exp(-wave * wave * 80.0) * exp(-age * 1.3);
        }
    }
    return min(acc, 1.5);
}

// 2D kaleidoscopic symmetry fold for the aether-caustic tessellation layer.
fn kaleido(uv: vec2<f32>, folds: f32) -> vec2<f32> {
    let ang = atan2(uv.y, uv.x);
    let rad = length(uv);
    let fa = abs(fract(ang / TAU * folds + 0.5) - 0.5) / folds * TAU;
    return vec2<f32>(cos(fa), sin(fa)) * rad;
}

// snd = (bass, mids, treble, fftGillBand); rip = click-ripple displacement
fn map(p_in: vec3<f32>, snd: vec4<f32>, rip: f32) -> vec2<f32> {
    var p = p_in;

    // Current Warp slider: aether-current domain twist along the body axis.
    // FFT gill band tightens the current; click ripples churn it.
    let current_warp = u.zoom_params.y;
    let twist = (p.y * 1.5 + u.config.x * 0.4) * current_warp * (0.4 + snd.w * 0.8) + rip * 2.5;
    let pw_xy = p.xy * rot2D(twist * 0.35);
    p = vec3<f32>(pw_xy.x, pw_xy.y, p.z);

    // Slowly translate Axolotl along the Z axis (swimming forward)
    let swim_time = u.config.x * 0.5;

    // Axolotl Body (Stretched sphere) — mids drive the swim wiggle
    var p_body = p;
    p_body.x += sin(p_body.y * 2.0 - swim_time * 3.0) * (0.1 + snd.y * 0.08);
    p_body /= (1.0 + snd.x * 0.08); // bass breathing
    let d_body = length(p_body * vec3<f32>(1.0, 0.3, 1.0)) - 0.4;
    var res = vec2<f32>(d_body, 1.0); // ID 1 = Body

    // Axolotl Tail
    var p_tail = p;
    p_tail.y += 0.5; // Offset tail position
    p_tail.x += sin(p_tail.y * 3.0 - swim_time * 5.0) * 0.15; // Faster wiggle
    let d_tail = length(p_tail * vec3<f32>(2.0, 1.0, 3.0)) - 0.1;

    res.x = smin(res.x, d_tail, 0.2); // Blend tail with body

    // External Gills (Fractal trees)
    var p_gills = p;
    p_gills.y -= 0.3; // Position near head
    p_gills.x = abs(p_gills.x) - 0.4; // Symmetry for left/right gills

    // Audio reaction (bass) for gill expansion and rotation
    let gill_expansion = u.zoom_params.x * (1.0 + snd.x * 0.5);

    var d_gills = 100.0;
    var scale = 1.0;
    var p_f = p_gills;

    // Fractal iterations for gills — FFT band folds each branch generation
    for (var i = 0; i < 4; i++) {
        let fi = f32(i);
        let grot_xy = p_f.xy * rot2D(0.5 + sin(swim_time + fi) * 0.2 * gill_expansion + snd.w * (0.3 + fi * 0.15));
        let grot_xz = p_f.xz * rot2D(0.3 * gill_expansion + rip * 1.5);
        p_f = vec3<f32>(grot_xy.x, grot_xy.y, grot_xz.y);
        p_f.y -= 0.15 * scale;

        let cylinder = max(length(p_f.xz) - 0.02 * scale, abs(p_f.y) - 0.15 * scale);
        d_gills = min(d_gills, cylinder);

        // Branching
        p_f = abs(p_f);
        p_f.x -= 0.05 * scale;
        scale *= 0.7;
    }

    // Click ripples ripple through the soft tissue
    res.x -= rip * 0.12;
    d_gills -= rip * 0.18;

    // Combine Gills with Body
    if (d_gills < res.x) {
        res = vec2<f32>(d_gills, 2.0); // ID 2 = Gills
    } else {
        res.x = smin(res.x, d_gills, 0.1);
    }

    return res;
}

fn calcNormal(p: vec3<f32>, snd: vec4<f32>, rip: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, snd, rip).x - map(p - e.xyy, snd, rip).x,
        map(p + e.yxy, snd, rip).x - map(p - e.yxy, snd, rip).x,
        map(p + e.yyx, snd, rip).x - map(p - e.yyx, snd, rip).x
    ));
}

fn raymarch(ro: vec3<f32>, rd: vec3<f32>, snd: vec4<f32>, rip: f32) -> vec2<f32> {
    var d0 = 0.0;
    var id_hit = 0.0;
    for (var i = 0; i < 80; i++) {
        let p = ro + rd * d0;
        let dS = map(p, snd, rip);
        d0 += dS.x;
        id_hit = dS.y;
        if (dS.x < 0.001 || d0 > MAX_DIST) { break; }
    }
    return vec2<f32>(d0, id_hit);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) {
        return;
    }

    let coord = vec2<i32>(gid.xy);
    let uv01 = vec2<f32>(gid.xy) / res;
    let uv = (uv01 - 0.5) * vec2<f32>(res.x / res.y, 1.0);

    let t = u.config.x;

    // Real audio: bands + engine FFT (read-only)
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let fft_gill = (fftBin(10u) + fftBin(18u) + fftBin(26u)) / 3.0;
    let fft_air = (fftBin(84u) + fftBin(100u) + fftBin(116u)) / 3.0;
    let snd = vec4<f32>(bass, mids, treble, fft_gill);

    // Click ripples deform the geometry
    let rip = rippleField(uv01, t);

    // Mouse-orbit camera (mouse uv is 0-1, y=0 top — used directly, no flip)
    let yaw = (u.zoom_config.y - 0.5) * PI * 1.4 + t * 0.06;
    let pitch = (u.zoom_config.z - 0.5) * PI * 0.6;
    let cam = rotY(yaw) * rotX(pitch);

    let ro = cam * vec3<f32>(0.0, 0.0, -3.0);
    let rd = cam * normalize(vec3<f32>(uv.x, uv.y, 1.0));

    // Background / Nebula
    var col = vec3<f32>(0.0);
    let nebula_density = u.zoom_params.z;
    var n_val = 0.0;
    var n_pos = ro + rd * 5.0;
    n_pos.z += t * 0.2; // Translate noise slowly
    for (var i = 0.0; i < 4.0; i += 1.0) {
        n_val += noise(n_pos * pow(2.0, i)) * pow(0.5, i);
    }

    let abyssal_blue = vec3<f32>(0.05, 0.1, 0.2);
    let quantum_purple = vec3<f32>(0.2, 0.0, 0.3);
    let bg_color = mix(abyssal_blue, quantum_purple, n_val) * nebula_density;
    col += bg_color;

    // 2D aether-caustic tessellation: kaleidoscopic ring lattice drifting
    // behind the axolotl; fold count follows mids, shimmer follows the air band.
    let folds = 5.0 + floor(mids * 5.0);
    let kuv = kaleido(rd.xy * 1.4 + vec2<f32>(0.0, sin(t * 0.2) * 0.1), folds);
    let ring = length(fract(kuv * 2.5 + t * 0.04) - 0.5);
    let caustic = 1.0 - smoothstep(0.02, 0.1, abs(ring - 0.3));
    col += vec3<f32>(0.05, 0.35, 0.4) * caustic * nebula_density * (0.3 + fft_air * 1.2 + rip * 0.8);

    // Raymarching Axolotl
    let rm = raymarch(ro, rd, snd, rip);
    let d = rm.x;
    let m_id = rm.y;

    var depth = textureLoad(readDepthTexture, coord, 0).r; // passthrough for misses

    if (d < MAX_DIST) {
        let p = ro + rd * d;
        let n = calcNormal(p, snd, rip);

        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

        let base_col = vec3<f32>(0.8, 0.2, 0.6); // Pinkish axolotl base

        if (m_id == 1.0) {
            // Body: subsurface scattering and refraction
            let sss = max(0.0, dot(rd, -lightDir));
            col = base_col * diff + vec3<f32>(0.1, 0.5, 0.8) * fresnel + vec3<f32>(0.5, 0.1, 0.4) * sss * 0.5;
            col = mix(col, bg_color, 0.3); // Pick up ambient nebula light
        } else if (m_id == 2.0) {
            // Gills: Bioluminescence synced to audio
            let biolum = u.zoom_params.w;
            let glow_color = vec3<f32>(0.0, 1.0, 0.8); // Cyan/Gold
            let emission = glow_color * (1.0 + (bass + fft_gill + treble * 0.5) * biolum);
            col = base_col * 0.5 + emission + vec3<f32>(1.0) * fresnel;
        }

        // Real depth: near = 1, far = 0
        depth = clamp(1.0 - d / MAX_DIST, 0.0, 1.0);
    }

    // Tonemap + gentle gamma
    col = col / (1.0 + col * 0.6);
    col = pow(col, vec3<f32>(1.0 / 2.2));

    // Semantic alpha from luma
    let luma = dot(clamp(col, vec3<f32>(0.0), vec3<f32>(1.0)), vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(luma * 0.7 + 0.25, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(col, alpha));
}
