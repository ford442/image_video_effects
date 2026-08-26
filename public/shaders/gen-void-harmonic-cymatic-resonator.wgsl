// ----------------------------------------------------------------
// Void Harmonic Cymatic Resonator
// Category: generative
// ----------------------------------------------------------------
<<<<<<< HEAD
// --- COPY PASTE THIS HEADER ---
=======
>>>>>>> origin/main
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Frequency, .y = Amplitude, .z = Glow Intensity, .w = Complexity
  ripples: array<vec4<f32>, 50>,
};

<<<<<<< HEAD
// ... (Constants, Math Helpers, SDF logic, Audio Sampling, Main Compute Shader)
=======
const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 20.0;
const SURF_DIST: f32 = 0.005;
>>>>>>> origin/main
const PI: f32 = 3.14159265359;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

<<<<<<< HEAD
fn map(pos: vec3<f32>, freq: f32, amp: f32, comp: f32) -> f32 {
    var p = pos;
    // Mouse warp
    let mousePos = vec3<f32>((u.zoom_config.y - 0.5) * 4.0, (0.5 - u.zoom_config.z) * 4.0, 0.0);
    let warp = 1.0 / (1.0 + pow(length(p - mousePos), 2.0));
    p = mix(p, mousePos, warp * 0.5 * u.zoom_config.w);

    var d = 10.0;

    // Domain repetition
    let c = vec3<f32>(4.0);
    var rp = p - c * round(p / c);

    var res = length(rp) - 1.0;

    var f = 1.0;
    var a = 1.0;

    for(var i = 0.0; i < comp; i = i + 1.0) {
        let x = sin(rp.x * freq * f + u.config.x) * cos(rp.y * freq * f);
        let y = sin(rp.y * freq * f + u.config.x) * cos(rp.z * freq * f);
        let z = sin(rp.z * freq * f + u.config.x) * cos(rp.x * freq * f);

        res = res + (x + y + z) * amp * a;
        f = f * 1.5;
        a = a * 0.5;

        let rot_mat = rot(u.config.x * 0.1 * f);
        let yz = rot_mat * vec2<f32>(rp.y, rp.z);
        rp.y = yz.x;
        rp.z = yz.y;
    }

    return res * 0.5;
}

fn calcNormal(p: vec3<f32>, freq: f32, amp: f32, comp: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, freq, amp, comp) - map(p - e.xyy, freq, amp, comp),
        map(p + e.yxy, freq, amp, comp) - map(p - e.yxy, freq, amp, comp),
        map(p + e.yyx, freq, amp, comp) - map(p - e.yyx, freq, amp, comp)
    ));
=======
// 3D noise for complexity
fn hash31(p: vec3<f32>) -> f32 {
    let p1 = fract(p * 0.1031);
    let p2 = p1 + dot(p1, p1.yzx + 33.33);
    return fract((p2.x + p2.y) * p2.z);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

fn sdf(p_in: vec3<f32>, audio_level: f32) -> f32 {
    var p = p_in;

    // Mouse Gravity Warp
    let mouse_uv = u.zoom_config.yz * 2.0 - 1.0;
    // Map mouse UV to somewhat sensible 3D coordinates on XY plane at Z=0
    let mouse_pos = vec3<f32>(mouse_uv.x * 2.0, -mouse_uv.y * 2.0, 0.0);

    // Warp space based on mouse distance if mouse is down
    if (u.zoom_config.w > 0.5) {
        let warp = 1.0 / (1.0 + pow(length(p - mouse_pos), 2.0));
        p = mix(p, mouse_pos, warp * 0.5); // Pull space towards mouse
    }

    let t = u.config.x * 0.5;

    // Domain rotation
    let r1 = rot(t * 0.2);
    let temp1 = r1 * p.xz;
    p.x = temp1.x; p.z = temp1.y;
    let r2 = rot(t * 0.3);
    let temp2 = r2 * p.xy;
    p.x = temp2.x; p.y = temp2.y;

    let freq = u.zoom_params.x * (1.0 + audio_level * 2.0); // Frequency influenced by audio
    let amp = u.zoom_params.y * (0.5 + audio_level * 0.5); // Amplitude influenced by audio
    let comp = u.zoom_params.w;

    // Core cymatic structure: intersecting standing waves
    let waveX = sin(p.x * freq) * cos(p.y * freq * 0.5);
    let waveY = sin(p.y * freq) * cos(p.z * freq * 0.5);
    let waveZ = sin(p.z * freq) * cos(p.x * freq * 0.5);

    let base_shape = (waveX + waveY + waveZ) * amp;

    // Add spherical envelope so it doesn't stretch to infinity
    let d_sphere = length(p) - 3.0;

    // Fractal displacement for complexity
    var disp = 0.0;
    var f = 1.0;
    var a = 0.5;
    for (var i = 0; i < i32(comp) && i < 5; i = i + 1) {
        disp = disp + a * sin(dot(p, vec3<f32>(f)) + t);
        f = f * 2.0;
        a = a * 0.5;
    }

    return smin(d_sphere, base_shape + disp * 0.5, 0.5);
}

fn getNormal(p: vec3<f32>, audio_level: f32) -> vec3<f32> {
    let d = sdf(p, audio_level);
    let e = vec2<f32>(0.01, 0.0);
    let n = d - vec3<f32>(
        sdf(p - e.xyy, audio_level),
        sdf(p - e.yxy, audio_level),
        sdf(p - e.yyx, audio_level)
    );
    return normalize(n);
>>>>>>> origin/main
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
<<<<<<< HEAD
    let resolution = u.config.zw;
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) {
        return;
    }

    let uv = (vec2<f32>(f32(id.x), f32(id.y)) - 0.5 * resolution) / resolution.y;

    // Audio input
    let audio_val = textureSampleLevel(dataTextureC, non_filtering_sampler, vec2<f32>(abs(uv.x), 0.5), 0.0).r;

    let freq = u.zoom_params.x * (1.0 + audio_val * 2.0);
    let amp = u.zoom_params.y * (1.0 + audio_val * 0.5);
    let glow_intensity = u.zoom_params.z;
    let comp = u.zoom_params.w;

    let ro = vec3<f32>(0.0, 0.0, 5.0);
    let ta = vec3<f32>(0.0, 0.0, 0.0);
    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = normalize(cross(cu, cw));
    let rd = normalize(uv.x * cu + uv.y * cv + 1.5 * cw);

    var t = 0.0;
    var d = 0.0;
    var p = ro;

    var glow = 0.0;

    for (var i = 0; i < 100; i = i + 1) {
        p = ro + rd * t;
        d = map(p, freq, amp, comp);

        if (d < 0.001) { break; }
        if (t > 20.0) { break; }

        t = t + d;
        glow = glow + 0.02 / (0.02 + abs(d)); // Accumulate glow
    }

    var col = vec3<f32>(0.0);

    if (d < 0.001) {
        let n = calcNormal(p, freq, amp, comp);
        let l = normalize(vec3<f32>(1.0, 1.0, 2.0));
        let dif = max(dot(n, l), 0.0);
        let amb = 0.1;

        // Base color based on position
        let baseCol = vec3<f32>(0.1, 0.5, 0.9) + sin(p * 2.0) * 0.2;

        col = baseCol * (dif + amb);

        // Audio reactive nodal points
        let nodeFactor = sin(length(p) * 10.0 - u.config.x * 5.0) * 0.5 + 0.5;
        let nodeColor = vec3<f32>(0.9, 0.1, 0.5); // Neon magenta
        col = mix(col, nodeColor, nodeFactor * audio_val * 2.0);

    }

    // Volumetric glow
    let glowCol = vec3<f32>(0.1, 0.3, 0.8) * glow * glow_intensity * 0.1;
    col = col + glowCol;

    // Fog
    col = mix(col, vec3<f32>(0.01, 0.01, 0.02), 1.0 - exp(-0.02 * t * t));

=======
    let res = u.config.zw;
    if (f32(id.x) >= res.x || f32(id.y) >= res.y) {
        return;
    }

    let uv = (vec2<f32>(f32(id.x), f32(id.y)) - 0.5 * res) / res.y;

    // Sample audio
    // We sample from dataTextureC across the X axis.
    // We'll use a few samples to get an average or specific freq band.
    let audio_low = textureSampleLevel(dataTextureC, non_filtering_sampler, vec2<f32>(0.1, 0.5), 0.0).r;
    let audio_mid = textureSampleLevel(dataTextureC, non_filtering_sampler, vec2<f32>(0.5, 0.5), 0.0).r;
    let audio_high = textureSampleLevel(dataTextureC, non_filtering_sampler, vec2<f32>(0.9, 0.5), 0.0).r;

    let audio_avg = (audio_low + audio_mid + audio_high) * 0.333;
    let dynamic_audio = mix(0.0, audio_avg, 0.5); // smooth it a bit

    // Camera setup
    let ro = vec3<f32>(0.0, 0.0, -5.0);
    let ta = vec3<f32>(0.0, 0.0, 0.0);
    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = cross(cu, cw);
    let rd = normalize(uv.x * cu + uv.y * cv + 1.5 * cw);

    // Raymarching
    var p = ro;
    var dO = 0.0;
    var i = 0;
    var glow = 0.0;

    for (i = 0; i < MAX_STEPS; i = i + 1) {
        let dS = sdf(p, dynamic_audio);
        dO = dO + dS;
        p = ro + rd * dO;

        // Accumulate glow based on distance to surface, influenced by audio
        glow = glow + (0.05 / (0.01 + abs(dS))) * (1.0 + dynamic_audio * 5.0);

        if (abs(dS) < SURF_DIST || dO > MAX_DIST) {
            break;
        }
    }

    // Coloring
    let glow_intensity = u.zoom_params.z;
    var col = vec3<f32>(0.0);

    if (dO < MAX_DIST) {
        let n = getNormal(p, dynamic_audio);
        let lightDir = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let ambient = 0.1;

        // Base color based on position
        let base_col = 0.5 + 0.5 * cos(u.config.x + p.xyx + vec3<f32>(0.0, 2.0, 4.0));
        col = base_col * (diff + ambient);

        // Fresnel
        let f = pow(1.0 - max(dot(n, -rd), 0.0), 4.0);
        col = col + f * vec3<f32>(0.0, 1.0, 1.0) * audio_mid; // Cyan fresnel on audio mid
    }

    // Add Volumetric Glow (Subsurface scattering proxy)
    // Abyssal blues, hot neon magentas, electric cyans
    let glow_col = vec3<f32>(0.1, 0.2, 0.8) * audio_low
                 + vec3<f32>(0.9, 0.1, 0.5) * audio_mid
                 + vec3<f32>(0.1, 0.8, 0.9) * audio_high;

    col = col + glow_col * glow * 0.005 * glow_intensity;

    // Fog
    col = mix(col, vec3<f32>(0.0, 0.0, 0.05), 1.0 - exp(-0.02 * dO * dO));

    // Tonemapping
    col = col / (1.0 + col);

    // Output
>>>>>>> origin/main
    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}