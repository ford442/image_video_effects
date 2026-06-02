// ----------------------------------------------------------------
// Chronodynamic Aether-Weaver Automata
// Category: generative
// Features: temporal, chromatic, depth-aware, audio-reactive, mouse-driven
// Complexity: High
// Upgraded: 2026-05-31
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Thread Count, y=Loom Rotation Speed, z=Aether Bloom, w=Temporal Decay
    ripples: array<vec4<f32>, 50>,
};

// Math and Hash Functions
fn hash12(p: vec2<f32>) -> f32 {
    let q = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
    return fract(sin(q.x) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec2<f32>(3.0) - vec2<f32>(2.0) * f);
    return mix(mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn rot2d(angle: f32) -> mat2x2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn sdGear(p: vec2<f32>, radius: f32, teeth: f32, toothDepth: f32) -> f32 {
    let r = length(p);
    let a = atan2(p.y, p.x);
    let f = radius + toothDepth * cos(a * teeth);
    return r - f;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coords = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.z, u.config.w);
    if (f32(coords.x) >= res.x || f32(coords.y) >= res.y) {
        return;
    }

    let uv = vec2<f32>(coords) / res;
    let aspect = res.x / res.y;
    var p = (uv - vec2<f32>(0.5)) * 2.0;
    p.x *= aspect;

    let time = u.config.x;
    let audio = u.config.y;

    // Mouse Interaction
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    var mouse_p = (mouse - vec2<f32>(0.5)) * 2.0;
    mouse_p.x *= aspect;

    // Temporal Decay parameter
    let temporal_decay = u.zoom_params.w;

    // Chrono-Distortion Ripples from Mouse
    var distorted_p = p;
    let dist_to_mouse = length(p - mouse_p);

    // Adjust distortion based on generic mouse click state (approximated)
    if (mouse.x > 0.0 && mouse.y > 0.0) {
        let pull = exp(-dist_to_mouse * 5.0) * 0.5 * sin(time * 5.0);
        distorted_p = mix(distorted_p, mouse_p, pull);
    } else {
        let bend = exp(-dist_to_mouse * 2.0) * 0.1;
        distorted_p += normalize(p - mouse_p + vec2<f32>(0.001)) * bend;
    }

    // Loom Architecture (Gears): Background massive slow-rotating gears
    let rotation_speed = u.zoom_params.y;
    var gear_uv = distorted_p * rot2d(time * rotation_speed * 0.1);
    let d1 = sdGear(gear_uv, 0.8, 12.0, 0.1);
    let d2 = sdGear(distorted_p * rot2d(-time * rotation_speed * 0.15 + 1.0) - vec2<f32>(1.2, 0.5), 0.5, 8.0, 0.08);
    let gear_d = min(d1, d2);

    // Metallic gear shading
    var bg_color = vec3<f32>(0.0);
    if (gear_d < 0.0) {
        bg_color = vec3<f32>(0.05, 0.05, 0.1) * (1.0 + 0.5 * sin(gear_d * 50.0));
    }
    // Glow on gear edges
    let gear_glow = exp(-abs(gear_d) * 10.0) * vec3<f32>(0.2, 0.4, 0.8) * 0.5;

    // Aether Threads: Mathatically braided strings that react to audio
    let thread_count = i32(u.zoom_params.x);
    let aether_bloom = u.zoom_params.z;
    var thread_glow = vec3<f32>(0.0);

    for (var i: i32 = 0; i < 500; i++) {
        if (i >= thread_count) { break; }
        let fi = f32(i);

        let freq = 1.0 + fi * 0.02;
        let phase = time * (0.1 + fi * 0.01) + hash12(vec2<f32>(fi, 1.0)) * 6.28;

        // Audio reactivity modifies thread positions
        let audio_mod = audio * 0.2 * sin(time * 5.0 + fi * 0.1);

        let spline_y = sin(distorted_p.x * freq + phase) * 0.5 + noise(distorted_p * 2.0 + vec2<f32>(time * 0.2, fi * 0.1)) * 0.3 + audio_mod;
        let dist_to_spline = abs(distorted_p.y - spline_y);

        // Iridescent Plasma Shading using plasmaBuffer
        let plasma_idx = min(u32((fi / 500.0 + time * 0.05) * 255.0) % 256u, 255u);
        let plasma_color = plasmaBuffer[plasma_idx].xyz;

        // Bioluminescent nodes mapped to audio reactivity where threads bend
        let node_glow = max(0.0, sin(distorted_p.x * 20.0 + time * 5.0) * sin(spline_y * 20.0 - time * 3.0)) * audio;

        let thickness = 0.005 + audio * 0.01;
        let intensity = exp(-dist_to_spline / thickness) * (0.2 + node_glow);

        thread_glow += plasma_color * intensity * aether_bloom * 0.5;
    }

    // Audio analysis
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Temporal Echo Trails (Feedback loop for time dilation trails)
    var back_uv = uv - vec2<f32>(0.5);
    back_uv *= 0.99; // Slight zoom in
    back_uv = back_uv * rot2d(0.01 * sin(time)); // Slight rotation
    back_uv += vec2<f32>(0.5);

    // Sample previous frame
    var prev_color = vec3<f32>(0.0);
    if (back_uv.x >= 0.0 && back_uv.x <= 1.0 && back_uv.y >= 0.0 && back_uv.y <= 1.0) {
        prev_color = textureLoad(readTexture, vec2<i32>(back_uv * res), 0).xyz;
    }

    // Combine everything
    var final_color = bg_color + gear_glow + thread_glow;

    // Tone mapping
    final_color = final_color / (vec3<f32>(1.0) + final_color);

    // Mix with temporal decay
    final_color = mix(final_color, max(final_color, prev_color * 0.95), temporal_decay);

    // ─── Chromatic dispersion ───
    let chrStrength = 0.004 + bass * 0.008;
    let chrR = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(chrStrength * (1.0 + mids * 0.5), 0.0), 0.0).r;
    let chrG = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, chrStrength * (1.0 + treble * 0.3)), 0.0).g;
    let chrB = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-chrStrength * 0.7 * (1.0 + bass * 0.4), chrStrength * 0.3), 0.0).b;
    let chrColor = vec3<f32>(chrR, chrG, chrB);
    final_color = mix(final_color, chrColor, 0.2 + bass * 0.15);

    // ─── Temporal feedback via dataTextureC ───
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    final_color = mix(final_color, prev.rgb * 0.9, 0.03 + bass * 0.01);

    let depthVal = length(thread_glow) * 0.5 + gear_glow.b * 0.3;
    textureStore(writeTexture, coords, vec4<f32>(final_color, 1.0));
    textureStore(writeDepthTexture, coords, vec4<f32>(depthVal, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coords, vec4<f32>(thread_glow.r, thread_glow.g, gear_glow.b, 1.0));
}