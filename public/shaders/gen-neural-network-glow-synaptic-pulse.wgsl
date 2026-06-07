// ═══════════════════════════════════════════════════════════════════
//  Neural Network Glow - Synaptic Pulse
//  Category: generative
//  Features: audio-reactive, mouse-driven, temporal, upgraded-rgba,
//            chromatic-synapse, temporal-potentiation, depth-scaled-nodes
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-06-06
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};
fn applyGenerativePrimaryControls(color: vec4<f32>) -> vec4<f32> {
  let primaryIntensity = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
  let speedPulse = 0.92 + 0.16 * (0.5 + 0.5 * sin(u.config.x * mix(0.25, 5.0, clamp(u.zoom_params.y, 0.0, 1.0))));
  let detailContrast = mix(0.75, 1.6, clamp(u.zoom_params.z, 0.0, 1.0));
  let mouseDistance = length(u.zoom_config.yz - vec2<f32>(0.5));
  let mouseInfluence = mix(0.95, 1.15, clamp(u.zoom_params.w * mouseDistance * 2.0, 0.0, 1.0));
  let controlled = pow(max(color.rgb * primaryIntensity * speedPulse * mouseInfluence, vec3<f32>(0.0)), vec3<f32>(1.0 / detailContrast));
  return vec4<f32>(acesToneMap(controlled * 1.1), color.a);
}


fn hash22(p: vec2<f32>) -> vec2<f32> {
    var q = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
    return fract(sin(q) * 43758.5453);
}

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    let k = select(release, attack, bass > prev);
    return mix(prev, bass, k);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let coords = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / vec2<f32>(u.config.zw);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let prev = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    let prev_env = prev.r;
    let prev_mx = prev.g;
    let prev_my = prev.b;
    let prev_trail = prev.a;

    let bass_raw = plasmaBuffer[0].x;
    let env = bass_env(prev_env, bass_raw, 0.8, 0.15);

    let mouse_target = u.zoom_config.yz;
    let mouse_current = vec2<f32>(prev_mx, prev_my);
    let mouse_delta = length(mouse_target - mouse_current);
    let spring_k = select(0.12, 0.03, mouse_delta > 0.02);
    let smooth_mouse = mix(mouse_current, mouse_target, spring_k);

    let to_mouse = smooth_mouse - uv;
    let dist2 = dot(to_mouse, to_mouse) + 0.005;
    let dlen = length(to_mouse);
    let gravity = select(vec2<f32>(0.0), to_mouse * (0.5 + u.zoom_config.w * 3.0) / (dlen * dist2) * 0.002, dlen > 0.0001);
    let displaced_uv = uv + gravity;

    let input_luma = dot(textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));

    let p = displaced_uv * (4.0 + env);
    let i = floor(p);
    let f = fract(p);
    var min_dist = 1.0;
    for (var y = -1; y <= 1; y = y + 1) {
        for (var x = -1; x <= 1; x = x + 1) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let pt = hash22(i + neighbor);
            let dist = length(neighbor + pt - f);
            min_dist = select(min_dist, dist, dist < min_dist);
        }
    }

    let pulse_speed = u.zoom_params.x;
    let glow_intensity = u.zoom_params.y;
    let trail_decay = u.zoom_params.z;
    let pulse_ring = fract(min_dist * 5.0 - u.config.x * pulse_speed * 0.1 + input_luma * 0.3);
    let edge_intensity = smoothstep(0.05, 0.0, min_dist);
    let wave = smoothstep(0.9, 1.0, pulse_ring) * (1.0 + env * 2.5);
    let intensity = (edge_intensity + wave) * glow_intensity;

    let color_idx = u32(clamp(intensity * 128.0, 0.0, 255.0));
    var col = plasmaBuffer[color_idx].rgb;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Chromatic synapse separation: excitatory = warm, inhibitory = cool
    let excite = smoothstep(0.3, 0.8, bass);
    let inhibit = smoothstep(0.3, 0.8, treble);
    let warm = vec3<f32>(1.0, 0.6, 0.3) * excite * intensity;
    let cool = vec3<f32>(0.3, 0.6, 1.0) * inhibit * intensity;
    col = col + warm + cool;
    col = col + vec3<f32>(treble * 0.1, mids * 0.05, bass * 0.05);

    for(var k = 0; k < 50; k = k + 1) {
        let r = u.ripples[k];
        let rippleActive = r.w > 0.0;
        let d = length(uv - r.xy);
        let in_range = d < r.z * 0.5;
        let ripple_falloff = 1.0 - d / (r.z * 0.5);
        col = col + select(vec3<f32>(0.0), vec3<f32>(1.0, 0.5, 0.2) * ripple_falloff * r.w * 0.5, rippleActive && in_range);
    }

    // Temporal potentiation: previous trail strengthens with repeated activation
    let potentiation = max(intensity * 0.5, prev_trail * trail_decay * (1.0 + bass * 0.1));
    col = mix(col, col * 1.3, potentiation);

    // Depth-scaled node density: distant nodes appear smaller
    let depthScale = 0.5 + depth * 0.5;
    col = col * depthScale;
    let scaledIntensity = intensity * depthScale;

    let alpha = clamp(potentiation + scaledIntensity * 0.3 + mids * 0.05 + treble * 0.05, 0.0, 1.0);

    let finalColor = vec4<f32>(col, alpha);

    textureStore(writeTexture, coords, applyGenerativePrimaryControls(finalColor));
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
