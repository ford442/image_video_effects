// ═══════════════════════════════════════════════════════════════════
//  Holographic Entropy Vortex
//  Category: generative
//  Features: holographic, vortex, entropy, plasma-reactive, mouse-interactive
//  Complexity: High
//  Chunks From: none (original)
//  Created: 2026-05-09
//  By: Grok (prepared for Raptor-mini)
// ═══════════════════════════════════════════════════════════════════

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
    zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
    ripples: array<vec4<f32>, 50>;
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let uv = vec2<f32>(gid.xy) / vec2<f32>(u.config.zw);
    let t = u.config.x;
    let mouse = u.zoom_config.yz;
    
    // Polar vortex
    let centered = uv - 0.5;
    let r = length(centered);
    let angle = atan2(centered.y, centered.x) + t * (0.6 + r * 3.0);
    let vortexUV = vec2<f32>(cos(angle), sin(angle)) * r + 0.5;
    
    // Layered entropy noise
    let n1 = sin(vortexUV.x * 9.3 + t * 1.1) * cos(vortexUV.y * 7.7 + t * 0.9);
    let n2 = sin(vortexUV.x * 14.2 - t * 0.8) * cos(vortexUV.y * 11.5 + t * 1.4);
    let entropy = (n1 + n2 * 0.65) * 0.5 + 0.5;
    
    // Plasma tint from audio buffer
    let plasma = plasmaBuffer[u32(t * 0.08) % 50u].xyz;
    let baseColor = vec3<f32>(0.4, 0.6, 1.0);
    let tint = mix(baseColor, plasma, 0.55);
    
    var color = vec4<f32>(entropy * tint, 1.0);
    
    // Mouse push effect
    let dist = length(uv - mouse);
    let push = smoothstep(0.05, 0.35, dist) * 0.22;
    color = mix(color, color * 0.7 + vec4(0.3, 0.8, 1.0, 0.0) * 0.3, push);
    
    // Subtle depth interaction
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    color = mix(color, color * (0.6 + depth * 0.8), 0.25);
    
    textureStore(writeTexture, gid.xy, clamp(color, vec4(0.0), vec4(1.0)));
}
