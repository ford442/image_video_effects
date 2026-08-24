// ----------------------------------------------------------------
// Void Harmonic Cymatic Resonator
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
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

// ... (Constants, Math Helpers, SDF logic, Audio Sampling, Main Compute Shader)
const PI: f32 = 3.14159265359;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

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
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
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

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}