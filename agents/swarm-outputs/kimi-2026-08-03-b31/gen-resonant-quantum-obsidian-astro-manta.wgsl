// ----------------------------------------------------------------
// Resonant Quantum-Obsidian Astro-Manta
// Category: generative
// Upgraded: 2026-08-03 - Interactivist b31: orbit cam, ripples, FFT folds.
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
  zoom_params: vec4<f32>,  // x=Time Scale, y=Audio Reactivity, z=Brightness, w=Evolution Speed
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const MAX_DIST: f32 = 20.0;
fn rot(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
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
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
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
            let wave = d - age * 0.5;
            acc += exp(-wave * wave * 70.0) * exp(-age * 1.2);
        }
    }
    return min(acc, 1.5);
}
// 2D kaleidoscopic symmetry fold for the obsidian-shard tessellation layer.
fn kaleido(uv: vec2<f32>, folds: f32) -> vec2<f32> {
    let ang = atan2(uv.y, uv.x);
    let rad = length(uv);
    let fa = abs(fract(ang / TAU * folds + 0.5) - 0.5) / folds * TAU;
    return vec2<f32>(cos(fa), sin(fa)) * rad;
}
// snd = (bass, mids, treble, fftVeinBand); rip = click-ripple displacement
fn map(p_in: vec3<f32>, t: f32, snd: vec4<f32>, rip: f32) -> f32 {
    var p_mod = p_in;

    // Symmetry fold: mirror the wing plane, then twist each half into a
    // biomechanical fin-helix driven by the vein FFT band and click ripples.
    p_mod.x = abs(p_mod.x);
    let fin_twist = p_mod.x * (0.35 + snd.w * 0.9 + snd.x * 0.25) + rip * 2.0;
    let fin_yz = p_mod.yz * rot(fin_twist * 0.4);
    p_mod = vec3<f32>(p_mod.x, fin_yz.x, fin_yz.y);

    // Bass resonance breathes the obsidian hull
    p_mod = p_mod / (1.0 + snd.x * 0.1);

    // Manta body (flattened ellipsoid core)
    let body = length(p_mod * vec3<f32>(1.0, 3.0, 0.5)) - 1.0;

    // Wing undulation (Time Scale slider speeds the stroke)
    let wing_wave = sin(p_mod.x * 2.0 - t * 3.0) * 0.5 * p_mod.x * (1.0 + snd.y * 0.3);
    p_mod.y += wing_wave;
    let wings = length(p_mod * vec3<f32>(0.2, 10.0, 1.0)) - 0.5;

    // Tail spike: tapered chord trailing behind the hull
    var p_tail = p_mod;
    p_tail.z += 1.2;
    p_tail.x *= 1.0 + max(p_tail.z, 0.0) * 1.5;
    let tail = length(p_tail * vec3<f32>(1.0, 4.0, 0.6)) - 0.25;

    var d = smin(body, wings, 0.8);
    d = smin(d, tail, 0.3);
    // Click ripples buckle the obsidian plates
    d -= rip * 0.15 * (1.0 + snd.x * 0.5);

    return d;
}
fn calcNormal(p: vec3<f32>, t: f32, snd: vec4<f32>, rip: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, t, snd, rip) - map(p - e.xyy, t, snd, rip),
        map(p + e.yxy, t, snd, rip) - map(p - e.yxy, t, snd, rip),
        map(p + e.yyx, t, snd, rip) - map(p - e.yyx, t, snd, rip)
    ));
}
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) {
        return;
    }

    let coord = vec2<i32>(global_id.xy);
    let uv01 = vec2<f32>(global_id.xy) / res;
    let uv = (uv01 - 0.5) * vec2<f32>(res.x / res.y, 1.0);

    // Time Scale slider drives the creature clock
    let time_scale = u.zoom_params.x;
    let t = u.config.x * time_scale;

    // Real audio: bands + engine FFT (read-only)
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let fft_vein = (fftBin(14u) + fftBin(22u) + fftBin(30u)) / 3.0;
    let fft_air = (fftBin(88u) + fftBin(104u) + fftBin(120u)) / 3.0;
    let snd = vec4<f32>(bass, mids, treble, fft_vein);

    // Click ripples deform the geometry
    let rip = rippleField(uv01, u.config.x);

    // Mouse-orbit camera (mouse uv is 0-1, y=0 top — used directly, no flip)
    let yaw = (u.zoom_config.y - 0.5) * PI * 1.5 + u.config.x * 0.05;
    let pitch = (u.zoom_config.z - 0.5) * PI * 0.7;
    let cam = rotY(yaw) * rotX(pitch);

    let ro = cam * vec3<f32>(0.0, 0.0, -5.0);
    let rd = cam * normalize(vec3<f32>(uv, 1.0));

    // Raymarching
    var dist = 0.0;
    var p = ro;
    var hit = false;

    for (var i = 0; i < 100; i++) {
        p = ro + rd * dist;
        let d = map(p, t, snd, rip);
        if (d < 0.001) {
            hit = true;
            break;
        }
        if (dist > MAX_DIST) { break; }
        dist += d;
    }

    // Shading
    let evolution = u.zoom_params.w;
    var col = vec3<f32>(0.05, 0.0, 0.1); // Void background
    var depth = textureLoad(readDepthTexture, coord, 0).r; // passthrough for misses

    // 2D obsidian-shard tessellation sea behind the manta; Evolution Speed
    // scrolls it, mids set the fold count, the air band lights the seams.
    let folds = 7.0 + floor(mids * 5.0);
    let kuv = kaleido(rd.xy * 1.7 + vec2<f32>(u.config.x * 0.02 * evolution, 0.0), folds);
    let shard = fract(kuv * 3.5 + vec2<f32>(0.0, u.config.x * 0.05 * evolution)) - 0.5;
    let seam = 1.0 - smoothstep(0.02, 0.08, abs(length(shard) - 0.26));
    col += vec3<f32>(0.08, 0.25, 0.4) * seam * (0.3 + fft_air * 1.2 + rip * 0.8);

    if (hit) {
        let n = calcNormal(p, t, snd, rip);
        let light = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, light), 0.0);
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

        // Audio reactivity from plasma buffer (Audio Reactivity slider = gain)
        let audio_gain = u.zoom_params.y;
        let glow_drive = (bass + fft_vein + treble * 0.4) * audio_gain;

        // Obsidian base + glowing veins
        let baseColor = vec3<f32>(0.1);
        let glowColor = vec3<f32>(0.2, 0.8, 1.0) * glow_drive * 2.0;

        // Vein lattice etched across the hull; FFT band shifts the etch phase
        let veins = smoothstep(0.8, 1.0, sin(p.x * 10.0 + snd.w * 4.0) * sin(p.z * 10.0 - t));

        col = baseColor * diff + glowColor * veins + vec3<f32>(0.1, 0.4, 0.6) * fresnel * (0.5 + mids);

        // Real depth: near = 1, far = 0
        depth = clamp(1.0 - dist / MAX_DIST, 0.0, 1.0);
    }

    // Volumetric fog/bloom overlay (Brightness slider = emission strength)
    col += vec3<f32>(0.1, 0.3, 0.5) * (1.0 - exp(-0.05 * dist)) * u.zoom_params.z * max(0.5, evolution);

    // Tonemap + gentle gamma
    col = col / (1.0 + col * 0.5);
    col = pow(col, vec3<f32>(1.0 / 2.2));

    // Semantic alpha from luma
    let luma = dot(clamp(col, vec3<f32>(0.0), vec3<f32>(1.0)), vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(luma * 0.7 + 0.25, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(col, alpha));
}
