// ═══════════════════════════════════════════════════════════════════
//  Quantum Mycelial Neural Web
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-27
//  Ideas: action-potential spikes along fibres; synaptic junction flares
//  A packing: ACES display RGBA (C unused)
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

struct Uniforms {
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Web Density, .y = Pulse Speed, .z = Bioluminescence, .w = Entanglement
  ripples: array<vec4<f32>, 50>,
};

// --- CORE UTILITIES ---
// Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// 3D Noise for organic structures
fn hash33(p3: vec3<f32>) -> vec3<f32> {
    var p = fract(p3 * vec3<f32>(0.1031, 0.1030, 0.0973));
    p = p + dot(p, p.yxz + vec3<f32>(33.33));
    return fract((p.xxy + p.yxx) * p.zyx);
}

// 3D Perlin noise
fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec3<f32>(3.0) - 2.0 * f);
    return mix(
        mix(mix(dot(hash33(i + vec3<f32>(0.0, 0.0, 0.0)), f - vec3<f32>(0.0, 0.0, 0.0)),
                dot(hash33(i + vec3<f32>(1.0, 0.0, 0.0)), f - vec3<f32>(1.0, 0.0, 0.0)), u.x),
            mix(dot(hash33(i + vec3<f32>(0.0, 1.0, 0.0)), f - vec3<f32>(0.0, 1.0, 0.0)),
                dot(hash33(i + vec3<f32>(1.0, 1.0, 0.0)), f - vec3<f32>(1.0, 1.0, 0.0)), u.x), u.y),
        mix(mix(dot(hash33(i + vec3<f32>(0.0, 0.0, 1.0)), f - vec3<f32>(0.0, 0.0, 1.0)),
                dot(hash33(i + vec3<f32>(1.0, 0.0, 1.0)), f - vec3<f32>(1.0, 0.0, 1.0)), u.x),
            mix(dot(hash33(i + vec3<f32>(0.0, 1.0, 1.0)), f - vec3<f32>(0.0, 1.0, 1.0)),
                dot(hash33(i + vec3<f32>(1.0, 1.0, 1.0)), f - vec3<f32>(1.0, 1.0, 1.0)), u.x), u.y), u.z);
}

// Distance estimation for mycelial network
// returns (sdf, axial coord along nearest fibre + fibre seed, junction closeness)
fn map(p: vec3<f32>, time: f32, audio: f32) -> vec3<f32> {
    let density = u.zoom_params.x; // Web Density
    let entanglement = u.zoom_params.w; // Entanglement

    var pos = p;
    var d = length(pos) - 1.0;

    // Add curl noise distortion based on entanglement
    var n = vec3<f32>(
        noise(pos * 2.0 + vec3<f32>(time * 0.1)),
        noise(pos * 2.0 + vec3<f32>(time * 0.1 + 100.0)),
        noise(pos * 2.0 + vec3<f32>(time * 0.1 + 200.0))
    ) * entanglement;

    pos = pos + n;

    // Create fibrous structures using a sine-based domain repetition and noise
    let spacing = max(0.1, 1.0 - density * 0.4);
    var q = pos / spacing;

    // Apply rotations for entanglement
    q = vec3<f32>(rot(q.z * entanglement * 0.5) * q.xy, q.z);
    q = vec3<f32>(q.x, rot(q.x * entanglement * 0.5) * q.yz);

    // Fibers
    let fiber_x = length(q.yz) - 0.1 * density;
    let fiber_y = length(q.xz) - 0.1 * density;
    let fiber_z = length(q.xy) - 0.1 * density;

    // Combine fibers
    let min_fiber = min(min(fiber_x, fiber_y), fiber_z);

    // Idea 1 support: axial coordinate of the nearest fibre (+ per-fibre seed
    // so the three axons fire out of phase).
    var axial = q.x;
    if (fiber_y <= fiber_x && fiber_y <= fiber_z) { axial = q.y + 17.0; }
    if (fiber_z < fiber_x && fiber_z < fiber_y) { axial = q.z + 41.0; }

    // Idea 2 support: second-nearest fibre almost as close = a crossing.
    let max_fiber = max(max(fiber_x, fiber_y), fiber_z);
    let second_fiber = fiber_x + fiber_y + fiber_z - min_fiber - max_fiber;
    let junction = 1.0 - smoothstep(0.0, 0.18, second_fiber - min_fiber);

    // Add some noise displacement for organic feel
    let disp = noise(q * 4.0) * 0.1 * (1.0 + audio);

    return vec3<f32>(min_fiber * spacing - disp, axial, junction);
}

// Calculate normal
fn getNormal(p: vec3<f32>, time: f32, audio: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, time, audio).x - map(p - e.xyy, time, audio).x,
        map(p + e.yxy, time, audio).x - map(p - e.yxy, time, audio).x,
        map(p + e.yyx, time, audio).x - map(p - e.yyx, time, audio).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let st = (uv - vec2<f32>(0.5)) * 2.0;
    let aspect = resolution.x / resolution.y;
    let st_aspect = vec2<f32>(st.x * aspect, st.y);

    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let time = u.config.x;

    // Live audio (binding 12): bass drives displacement/glow as the old
    // "audio" term did; mids tint the membrane, treble sharpens spikes.
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audio = bass;

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, -3.0);
    var rd = normalize(vec3<f32>(st_aspect, 1.5));

    // Mouse interaction - acts as an attractor point
    let mouse = u.zoom_config.yz;
    let mouse_world = vec3<f32>((mouse.x - 0.5) * 4.0 * aspect, (0.5 - mouse.y) * 4.0, -1.0);

    // Raymarching
    var t = 0.0;
    let max_d = 10.0;
    var d = 0.0;
    let iters = 64;
    var p = ro;

    var glow = 0.0;
    let pulse_speed = u.zoom_params.y;

    for (var i = 0; i < iters; i = i + 1) {
        p = ro + rd * t;

        // Warping space towards mouse interaction
        let dist_to_mouse = length(p - mouse_world);
        if (u.zoom_config.w > 0.5 && dist_to_mouse < 2.0) {
            let pull = (2.0 - dist_to_mouse) * 0.5;
            p = mix(p, mouse_world, pull * 0.1);
        }

        d = map(p, time, audio).x;

        // Accumulate glow based on proximity to surfaces and audio
        glow = glow + 0.01 / (0.01 + abs(d)) * (1.0 + audio * 2.0);

        if (d < 0.001 || t > max_d) {
            break;
        }
        t = t + d * 0.5; // step size factor for volumetric feel
    }

    var col = vec3<f32>(0.0);
    let hit = t < max_d;
    var spike = 0.0;
    var flare = 0.0;

    if (hit) {
        let n = getNormal(p, time, audio);
        let hitRes = map(p, time, audio);

        // Simple lighting
        let l = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, l), 0.0);
        let amb = 0.1;

        let bioluminescence = u.zoom_params.z;
        let pulse = sin(time * pulse_speed + length(p) * 2.0) * 0.5 + 0.5;

        // Base color based on depth and position
        let base_col = mix(vec3<f32>(0.1, 0.3, 0.5), vec3<f32>(0.6, 0.1, 0.4),
                           clamp(sin(p.z * 0.5) * 0.5 + 0.5 + mids * 0.15, 0.0, 1.0));

        // Emission color
        let emit_col = vec3<f32>(0.2, 0.8, 1.0) * bioluminescence * pulse * (1.0 + audio * 3.0);

        col = base_col * (diff + amb) + emit_col * 0.5;

        // Idea 1: action-potential spikes travel along each fibre's axis.
        let spikePhase = sin(hitRes.y * 3.0 - time * pulse_speed * 2.5);
        spike = pow(max(spikePhase, 0.0), 18.0 - treble * 8.0);
        col += vec3<f32>(0.55, 0.95, 1.0) * spike * bioluminescence * (1.6 + bass);

        // Idea 2: synaptic junction flares where fibres cross — they fire as
        // the spike train passes, tinted warmer by Entanglement.
        let arrival = pow(max(sin(-time * pulse_speed * 2.5 + hitRes.y * 0.35), 0.0), 6.0);
        flare = hitRes.z * (0.25 + 0.75 * max(arrival, spike));
        let synCol = mix(vec3<f32>(1.0, 0.62, 0.25), vec3<f32>(1.0, 0.3, 0.75), u.zoom_params.w);
        col += synCol * flare * bioluminescence * 1.4;
    }

    // Add volumetric glow
    let bioluminescence = u.zoom_params.z;
    let glow_col = vec3<f32>(0.1, 0.5, 0.8) * glow * 0.02 * bioluminescence;
    col = col + glow_col;

    // Attenuation based on distance
    col = mix(col, vec3<f32>(0.0, 0.0, 0.05), clamp(t / max_d, 0.0, 1.0));

    // Semantic alpha: fibre coverage + spike/flare emission, volumetric glow off-surface.
    let glowA = clamp(glow * 0.012 * bioluminescence, 0.0, 0.6);
    let alpha = select(glowA + 0.02, clamp(0.55 + spike * 0.25 + flare * 0.2, 0.0, 1.0), hit);
    let display = vec4<f32>(acesToneMap(max(col, vec3<f32>(0.0))), alpha);

    let coord = vec2<i32>(global_id.xy);
    let srcDepth = textureLoad(readDepthTexture, coord, 0).r;
    let depth = select(srcDepth, clamp(1.0 - t / max_d, 0.0, 1.0), hit);
    textureStore(writeTexture, coord, display);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, display);
}
