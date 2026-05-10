// ═══════════════════════════════════════════════════════════════════
//  Neural Network Glow - Synaptic Pulse
//  Category: generative
//  Features: audio-reactive, mouse-driven
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) coords: vec3<u32>) {
    let res = textureDimensions(writeTexture);
    if (coords.x >= res.x || coords.y >= res.y) { return; }
    let uv = vec2<f32>(coords.xy) / vec2<f32>(res);

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coords.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));

    // Neural network layout
    let p = uv * 5.0;
    let i = floor(p);
    let f = fract(p);

    var min_dist = 1.0;

    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let pt = hash22(i + neighbor);
            let dist = length(neighbor + pt - f);
            if (dist < min_dist) {
                min_dist = dist;
            }
        }
    }

    // Audio driven pulsing using bass from plasmaBuffer
    let bass = plasmaBuffer[0].x;
    let audio_pulse = 1.0 + bass * 2.0;
    let pulse_speed = u.zoom_params.x;
    let glow_intensity = u.zoom_params.y;
    let pulse_ring = fract(min_dist * 5.0 - u.config.x * pulse_speed * 0.1);

    let edge_intensity = smoothstep(0.05, 0.0, min_dist);
    let wave = smoothstep(0.9, 1.0, pulse_ring) * audio_pulse;

    let intensity = (edge_intensity + wave) * glow_intensity;

    let color_idx = u32(clamp(intensity * 128.0, 0.0, 255.0));
    var col = plasmaBuffer[color_idx].rgb;

    // Mouse interaction via ripples
    for(var k = 0; k < 50; k++) {
        let r = u.ripples[k];
        if(r.w > 0.0) {
            let d = length(uv - r.xy);
            if(d < r.z * 0.5) {
                col += vec3<f32>(1.0, 0.5, 0.2) * (1.0 - d / (r.z * 0.5)) * r.w * u.zoom_config.y;
            }
        }
    }

    // Meaningful alpha based on luminance and intensity
    let luminance = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(max(luminance * 2.0, intensity * 0.5), 0.0, 1.0);
    textureStore(writeTexture, coords.xy, vec4<f32>(col, alpha));
}
