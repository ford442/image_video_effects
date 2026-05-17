// ═══════════════════════════════════════════════════════════════════
//  Neural Network Glow - Synaptic Pulse
//  Category: generative
//  Features: audio-reactive, mouse-driven, temporal-feedback
//  Complexity: Medium
//  Created: 2026-05-10
//  By: Phase A Upgrade Agent
// ═══════════════════════════════════════════════════════════════════

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

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

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var q = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
    return fract(sin(q) * 43758.5453);
}

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    let k = select(release, attack, bass > prev);
    return mix(prev, bass, k);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) coords: vec3<u32>) {
    let res = textureDimensions(writeTexture);
    if (coords.x >= res.x || coords.y >= res.y) { return; }
    let uv = vec2<f32>(coords.xy) / vec2<f32>(res);

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coords.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));

    // Read previous frame state from feedback texture
    let prev = textureLoad(dataTextureC, coords.xy, 0);
    let prev_env = prev.r;
    let prev_mx = prev.g;
    let prev_my = prev.b;
    let prev_trail = prev.a;

    // Attack/release bass envelope
    let bass_raw = plasmaBuffer[0].x;
    let env = bass_env(prev_env, bass_raw, 0.8, 0.15);

    // Spring-damper mouse follow
    let mouse_target = u.zoom_config.yz;
    let mouse_current = vec2<f32>(prev_mx, prev_my);
    let mouse_delta = length(mouse_target - mouse_current);
    let spring_k = select(0.12, 0.03, mouse_delta > 0.02);
    let smooth_mouse = mix(mouse_current, mouse_target, spring_k);

    // Gravity well: mouse warps neural UV space
    let to_mouse = smooth_mouse - uv;
    let dist2 = dot(to_mouse, to_mouse) + 0.005;
    let dlen = length(to_mouse);
    let gravity = select(vec2<f32>(0.0), to_mouse * (0.5 + u.zoom_config.w * 3.0) / (dlen * dist2) * 0.002, dlen > 0.0001);
    let displaced_uv = uv + gravity;

    // Video input influence
    let input_luma = dot(textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Neural network layout
    let p = displaced_uv * (4.0 + env);
    let i = floor(p);
    let f = fract(p);
    var min_dist = 1.0;
    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let pt = hash22(i + neighbor);
            let dist = length(neighbor + pt - f);
            min_dist = select(min_dist, dist, dist < min_dist);
        }
    }

    // Parameters
    let pulse_speed = u.zoom_params.x;
    let glow_intensity = u.zoom_params.y;
    let trail_decay = u.zoom_params.z;
    let pulse_ring = fract(min_dist * 5.0 - u.config.x * pulse_speed * 0.1 + input_luma * 0.3);
    let edge_intensity = smoothstep(0.05, 0.0, min_dist);
    let wave = smoothstep(0.9, 1.0, pulse_ring) * (1.0 + env * 2.5);
    let intensity = (edge_intensity + wave) * glow_intensity;

    let color_idx = u32(clamp(intensity * 128.0, 0.0, 255.0));
    var col = plasmaBuffer[color_idx].rgb;

    // Mouse click ripples (second mouse parameter)
    for(var k = 0; k < 50; k++) {
        let r = u.ripples[k];
        if(r.w > 0.0) {
            let d = length(uv - r.xy);
            let in_range = d < r.z * 0.5;
            let ripple_falloff = 1.0 - d / (r.z * 0.5);
            col += select(vec3<f32>(0.0), vec3<f32>(1.0, 0.5, 0.2) * ripple_falloff * r.w * 0.5, in_range);
        }
    }

    // Temporal feedback trails
    let trail = max(intensity * 0.5, prev_trail * trail_decay);
    col = mix(col, col * 1.3, trail);

    // Alpha encodes trail age / interaction intensity
    let alpha = clamp(trail + intensity * 0.3, 0.0, 1.0);

    // Write output and persistent state
    textureStore(writeTexture, coords.xy, vec4<f32>(col, alpha));
    textureStore(dataTextureA, coords.xy, vec4<f32>(env, smooth_mouse.x, smooth_mouse.y, trail));
}
