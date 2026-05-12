// ═══════════════════════════════════════════════════════════════════
//  Kimi Ripple Touch
//  Category: interactive-mouse
//  Features: mouse-driven, interactive, ripple, water, audio-reactive
//  Complexity: Medium
//  Chunks From: (original)
//  Created: 2026-05-10
//  By: Phase A Upgrade Swarm
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=RippleCount, y=Speed, z=Strength, w=Decay
  ripples: array<vec4<f32>, 50>,
};

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let coords = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    var mouse = u.zoom_config.yz;
    let mouseDown = clamp(u.zoom_config.w, 0.0, 1.0);

    let aspect = resolution.x / max(resolution.y, 0.001);
    var p = uv;
    p.x *= aspect;
    var mousePos = mouse;
    mousePos.x *= aspect;

    let dist = length(p - mousePos);

    let rippleSpeed = max(u.zoom_params.y * 5.0 + 1.0, 0.001);
    let rippleStrength = u.zoom_params.z * 0.1 * (1.0 + bass * 0.3);
    let rippleDecay = max(u.zoom_params.w * 2.0 + 0.5, 0.001);

    var ripple = 0.0;
    for (var i = 0; i < 5; i++) {
        let fi = f32(i);
        let wavePhase = time * rippleSpeed - dist * 10.0 + fi * 1.5;
        let waveAmp = exp(-dist * rippleDecay) * (1.0 - fi / 5.0);
        ripple += sin(wavePhase) * waveAmp;
    }

    let clickBurst = mouseDown * exp(-dist * 5.0) * sin(dist * 20.0 - time * 10.0);
    ripple += clickBurst * 0.5;

    let dir = normalize(p - mousePos + vec2<f32>(0.0001));
    var sampleUV = uv - dir * ripple * rippleStrength;
    sampleUV = clamp(sampleUV, vec2<f32>(0.0), vec2<f32>(1.0));

    let caStrength = abs(ripple) * 0.01;
    let r = textureSampleLevel(readTexture, u_sampler, sampleUV + vec2<f32>(caStrength, 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, sampleUV - vec2<f32>(caStrength, 0.0), 0.0).b;

    var color = vec3<f32>(r, g, b);
    let glow = max(0.0, ripple) * 0.3;
    color += vec3<f32>(0.2, 0.5, 1.0) * glow;

    let vignette = smoothstep(0.8, 0.2, dist);
    color = mix(color * 0.9, color, vignette * mouseDown);

    // Alpha encodes ripple peak glow — active ripple zones blend more strongly
    let ripple_norm = clamp(abs(ripple) * 2.0 + glow, 0.0, 1.0);
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(0.45 + ripple_norm * 0.35 + luma * 0.2, 0.0, 1.0);

    textureStore(writeTexture, coords, vec4<f32>(color, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
