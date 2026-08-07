// ----------------------------------------------------------------
// Quantum-Fluorescent Aether-Moth Swarm
// Category: generative
// Features: swarm-field, curl-flow, temporal-feedback (textureLoad),
//           hdr-feedback, aces-tone-map, semantic-alpha, generated-depth,
//           audio-reactive, interactive-mouse
// Optimizer pass (Batch 37): 18-tap 3D curlNoise replaced by a 4-tap
//           curl of a scalar potential (~4.5x noise-eval reduction),
//           dead-code removal, named constants, HDR feedback chain,
//           fixed mouse/audio uniform truth, clamped advection fetch.
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
  config: vec4<f32>,       // .x = time (seconds), .y = rippleCount (0-50 active ripples), .zw = resolution (width, height)
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (0–1 canvas: y=0 top), .w = mouse_down (>0.5 = pressed)
  zoom_params: vec4<f32>,  // .xyzw = user params p1…p4 (mapped from UI sliders)
  ripples: array<vec4<f32>, 50>,  // .xy = ripple uv, .z = startTime (seconds), .w = padding (0)
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ── Named field constants ───────────────────────────────────────
const FIELD_SCALE: f32 = 3.0;      // flow-field domain scale
const FLOW_DRIFT: f32 = 0.5;       // temporal drift of the flow domain
const CURL_EPS: f32 = 0.12;        // finite-difference step for curl
const SPAWN_FREQ: f32 = 20.0;      // moth spawn field frequency
const SPAWN_LO: f32 = 0.7;         // spawn threshold low
const SPAWN_HI: f32 = 0.9;         // spawn threshold high
const TRAIL_DECAY: f32 = 0.92;     // advected trail persistence
const ADVECT_SCALE: f32 = 0.02;    // trail advection step
const MOUSE_FORCE: f32 = 0.05;     // gravity-node strength
const MOUSE_SOFT: f32 = 0.1;       // force softening (1/(d²+soft))
const SCATTER_PUSH: f32 = -2.5;    // repulsion on mouse-down
const MANDALA_RINGS: f32 = 20.0;
const MANDALA_ARMS: f32 = 8.0;
const HDR_CEIL: f32 = 6.0;         // keep HDR feedback bounded

// ── 3D simplex noise (canonical Ashima form) ────────────────────
fn mod289(x: vec3<f32>) -> vec3<f32> {
    return x - floor(x * (1.0 / 289.0)) * 289.0;
}
fn mod289_4(x: vec4<f32>) -> vec4<f32> {
    return x - floor(x * (1.0 / 289.0)) * 289.0;
}
fn permute(x: vec4<f32>) -> vec4<f32> {
    return mod289_4(((x * 34.0) + 1.0) * x);
}
fn taylorInvSqrt(r: vec4<f32>) -> vec4<f32> {
    return 1.79284291400159 - 0.85373472095314 * r;
}

fn snoise(v: vec3<f32>) -> f32 {
    let C = vec2<f32>(1.0/6.0, 1.0/3.0);
    let D = vec4<f32>(0.0, 0.5, 1.0, 2.0);

    var i = floor(v + dot(v, vec3<f32>(C.y)));
    var x0 = v - i + dot(i, vec3<f32>(C.x));

    var g = step(x0.yzx, x0.xyz);
    var l = 1.0 - g;
    var i1 = min(g.xyz, l.zxy);
    var i2 = max(g.xyz, l.zxy);

    var x1 = x0 - i1 + vec3<f32>(C.x);
    var x2 = x0 - i2 + vec3<f32>(C.y);
    var x3 = x0 - 0.5;

    i = mod289(i);
    var p = permute(permute(permute(
                i.z + vec4<f32>(0.0, i1.z, i2.z, 1.0))
            + i.y + vec4<f32>(0.0, i1.y, i2.y, 1.0))
        + i.x + vec4<f32>(0.0, i1.x, i2.x, 1.0));

    var n_ = 0.142857142857;
    var ns = n_ * D.wyz - D.xzx;

    var j = p - 49.0 * floor(p * ns.z * ns.z);

    var x_ = floor(j * ns.z);
    var y_ = floor(j - 7.0 * x_);

    var x = x_ * ns.x + ns.yyyy;
    var y = y_ * ns.x + ns.yyyy;
    var h = 1.0 - abs(x) - abs(y);

    var b0 = vec4<f32>(x.xy, y.xy);
    var b1 = vec4<f32>(x.zw, y.zw);

    var s0 = floor(b0) * 2.0 + 1.0;
    var s1 = floor(b1) * 2.0 + 1.0;
    var sh = -step(h, vec4<f32>(0.0));

    var a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    var a1 = b1.xzyw + s1.xzyw * sh.zzww;

    var p0 = vec3<f32>(a0.xy, h.x);
    var p1 = vec3<f32>(a0.zw, h.y);
    var p2 = vec3<f32>(a1.xy, h.z);
    var p3 = vec3<f32>(a1.zw, h.w);

    var norm = taylorInvSqrt(vec4<f32>(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
    p0 = p0 * norm.x;
    p1 = p1 * norm.y;
    p2 = p2 * norm.z;
    p3 = p3 * norm.w;

    var m = max(0.6 - vec4<f32>(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), vec4<f32>(0.0));
    m = m * m;
    return 42.0 * dot(m * m, vec4<f32>(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

// ── Cheap divergence-free 2D flow: curl of a scalar potential ───
// 4 snoise taps instead of the old 18-tap 3D curlNoise (6 × snoiseVec3).
fn curl2(p: vec3<f32>) -> vec2<f32> {
    let dx = vec3<f32>(CURL_EPS, 0.0, 0.0);
    let dy = vec3<f32>(0.0, CURL_EPS, 0.0);
    let dndx = (snoise(p + dx) - snoise(p - dx)) / (2.0 * CURL_EPS);
    let dndy = (snoise(p + dy) - snoise(p - dy)) / (2.0 * CURL_EPS);
    return vec2<f32>(dndy, -dndx); // perpendicular gradient = divergence-free
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res   = vec2<f32>(u.config.zw);
    // bounds guard — mandatory
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let aspect = vec2<f32>(res.x / res.y, 1.0);
    let uv = (vec2<f32>(pixel) / res) * 2.0 - vec2<f32>(1.0);
    let uv_scaled = uv * aspect;

    let time = u.config.x;

    // Audio — ONLY plasmaBuffer[0].xyz + guarded FFT bins 1–8
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    var fft = 0.0;
    if (arrayLength(&extraBuffer) > 13u) {
        for (var k = 1u; k <= 8u; k = k + 1u) {
            fft += extraBuffer[4u + k];
        }
        fft *= 0.125;
    }

    // Mouse: zoom_config.yz is already 0–1 uv (y=0 top) — no /res divide, no y-flip
    // (uv.y is -1 at the top of the frame, so top-down mouse maps 1:1).
    let mouse01 = u.zoom_config.yz;
    let mouse = mouse01 * 2.0 - vec2<f32>(1.0);
    let mouse_scaled = mouse * aspect;
    let mouse_down = u.zoom_config.w > 0.5;

    // Live sliders
    let swarm_density  = u.zoom_params.x;
    let curl_intensity = u.zoom_params.y;
    let glow_strength  = u.zoom_params.z;
    let audio_sens     = u.zoom_params.w;

    // ── Flow field (4-tap curl; 1 extra tap for z-wobble) ───────
    let flow_p = vec3<f32>(uv_scaled * FIELD_SCALE, time * 0.2)
               * max(curl_intensity, 0.05)
               + vec3<f32>(0.0, 0.0, time * FLOW_DRIFT);
    let flow = curl2(flow_p) * (0.6 + curl_intensity * 0.8);
    let wobble = snoise(flow_p * 1.7 + vec3<f32>(11.3, 7.9, 3.1));

    // Attraction to mouse gravity node; scatter (repel) on mouse-down
    let to_mouse = mouse_scaled - uv_scaled;
    let dist_sq = dot(to_mouse, to_mouse) + MOUSE_SOFT;
    let force_dir = to_mouse * inverseSqrt(dist_sq);
    let force_mag = MOUSE_FORCE / dist_sq;
    let scatter = select(1.0, SCATTER_PUSH, mouse_down);

    let vel = vec3<f32>(flow + force_dir * force_mag * scatter, wobble * 0.25);

    // ── Advected trails (textureLoad feedback, clamped fetch) ───
    let advect_uv = (uv + vel.xy * ADVECT_SCALE) * 0.5 + vec2<f32>(0.5);
    let advect_px = clamp(vec2<i32>(advect_uv * res), vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1));
    let trail = textureLoad(dataTextureC, advect_px, 0).rgb;

    // ── Moth spawn field (noise threshold, density slider) ──────
    let particle_noise = snoise(vec3<f32>(uv_scaled * SPAWN_FREQ * swarm_density, time));
    var spawn = smoothstep(SPAWN_LO, SPAWN_HI, particle_noise);

    // Audio-driven mandala assembly (branchless gate, bass+mids energy)
    let audio_energy = bass + mids * 0.5;
    let gate = smoothstep(0.15, 0.7, audio_energy) * audio_sens;
    let mandala = sin(length(uv_scaled) * MANDALA_RINGS - time * 5.0)
                * cos(atan2(uv_scaled.y, uv_scaled.x) * MANDALA_ARMS);
    spawn += smoothstep(0.8, 1.0, mandala) * gate;

    // ── Fluorescent color mapping ───────────────────────────────
    let col1 = vec3<f32>(0.0, 1.0, 1.0); // Cyan
    let col2 = vec3<f32>(1.0, 0.0, 1.0); // Magenta
    let col3 = vec3<f32>(0.2, 0.0, 0.8); // Indigo

    let speed = length(vel);
    let vel_color = mix(col3, mix(col1, col2, saturate(speed)), saturate(speed * 2.0));
    let shimmer = 1.0 + treble * 0.6 + fft * 0.4; // quantum fluorescence flicker

    // ── HDR compose + bounded feedback ──────────────────────────
    var hdr = trail * TRAIL_DECAY;
    hdr += vel_color * spawn * glow_strength * shimmer;
    hdr = min(hdr, vec3<f32>(HDR_CEIL));

    // ── Real generated depth: dense moth clusters sit closer ────
    let depth_val = clamp(1.0 - spawn * 0.85 - saturate(luma(hdr)) * 0.15, 0.0, 1.0);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth_val, 0.0, 0.0, 0.0));

    // ── Semantic alpha: swarm intensity ─────────────────────────
    let alpha = clamp(spawn * 0.7 + luma(hdr) * 0.4, 0.03, 0.95);

    // HDR history for next frame's feedback (A = primary state)
    textureStore(dataTextureA, pixel, vec4<f32>(hdr, alpha));

    // Presentation-only: ACES tone map at the end of the chain
    let ldr = acesToneMap(hdr * (0.9 + mids * 0.2));
    textureStore(writeTexture, pixel, vec4<f32>(ldr, alpha));
}
