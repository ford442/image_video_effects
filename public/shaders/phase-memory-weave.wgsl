// ═══════════════════════════════════════════════════════════════════
//  Phase Memory Weave
//  Category: generative
//  Features: temporal-memory, phase-transitions, audio-driven, viscous, history-rich
//  Complexity: High
//  Chunks From: feedback techniques + phase field simulation
//  Created: 2026-05-31
//  By: Grok (creative technical artist)
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x * 0.5;
    
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    
    // Read history
    let current = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let prev1 = textureSampleLevel(dataTextureA, u_sampler, uv, 0.0);
    let prev2 = textureSampleLevel(dataTextureB, u_sampler, uv, 0.0);
    
    // Audio seasons drive phase
    let phase = bass * 0.4 + mids * 0.3; // 0 = fluid, 1 = crystalline
    
    // Memory blend (stronger memory = more crystalline)
    let memory = mix(0.2, 0.85, phase + treble * 0.2);
    
    // Base evolution
    let diffusion = 0.08 + (1.0 - phase) * 0.12;
    let lap = (prev1.r + prev1.g + prev1.b + prev1.a - current.r * 4.0) * diffusion;
    
    var val = current.r + lap * 0.6;
    
    // Phase-dependent behavior
    if (phase < 0.4) {
        // Fluid phase - flowing and mixing
        val = mix(val, sin(val * 3.0 + time) * 0.5 + 0.5, 0.15);
    } else {
        // Crystalline phase - locking in structure
        val = mix(val, round(val * 6.0) / 6.0, phase * 0.7);
    }
    
    // Mouse disturbance
    let mouseDist = length(uv - mouse);
    let disturbance = smoothstep(0.12, 0.02, mouseDist) * mouseDown * 1.8;
    val = mix(val, 0.5 + sin(time * 8.0) * 0.3, disturbance);
    
    // Store history
    textureStore(dataTextureA, gid.xy, vec4<f32>(val, prev1.r, prev1.g, 0.0));
    textureStore(dataTextureB, gid.xy, vec4<f32>(prev1.r, prev1.g, prev1.b, 0.0));
    
    // Visualization - phase determines aesthetic
    let crystal = step(0.5, phase);
    let fluidCol = vec3<f32>(0.2, 0.4, 0.7);
    let crystalCol = vec3<f32>(0.9, 0.85, 0.6);
    
    let base = mix(fluidCol, crystalCol, crystal);
    let detail = sin(val * 12.0 + time * 2.0) * 0.15 + 0.85;
    
    let col = base * detail * (0.7 + val * 0.6);
    
    // Alpha carries both density and "crystallinity"
    let alpha = clamp(val * 0.8 + crystal * 0.3, 0.15, 1.15);
    let a = clamp(alpha, 0.0, 1.0);
    
    textureStore(writeTexture, gid.xy, vec4<f32>(col * a, a));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(phase * 0.5 + val * 0.3, 0.0, 0.0, 0.0));
}