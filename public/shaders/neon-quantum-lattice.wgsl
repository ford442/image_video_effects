// ═══════════════════════════════════════════════════════════════════
//  Neon Quantum Lattice
//  Category: generative
//  Features: neon, quantum-lattice, bloom, mouse-reactive, audio-reactive
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
    
    // Quantum lattice grid
    let grid = fract(uv * 12.0 + sin(t * 0.4) * 0.3);
    let lattice = smoothstep(0.45, 0.55, abs(grid.x - 0.5)) * 
                  smoothstep(0.45, 0.55, abs(grid.y - 0.5));
    
    // Bloom layers
    let bloom1 = sin(uv.x * 7.0 + t) * cos(uv.y * 5.5 + t * 0.9);
    let bloom2 = sin(uv.x * 11.3 - t * 0.6) * cos(uv.y * 9.8 + t * 1.2);
    let bloom = (bloom1 + bloom2 * 0.7) * 0.5 + 0.5;
    
    // Plasma energy
    let plasma = plasmaBuffer[u32(t * 0.11) % 50u].xyz;
    
    let base = mix(vec3(0.1, 0.3, 0.9), vec3(0.9, 0.2, 0.6), lattice);
    var color = vec4<f32>(base * bloom + plasma * 0.35, 1.0);
    
    // Mouse attraction
    let attract = 1.0 - smoothstep(0.0, 0.4, length(uv - mouse));
    color += vec4(0.4, 0.9, 1.0, 0.0) * attract * 0.4;
    
    // Depth rim lighting
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    color += vec4(0.6, 0.8, 1.0, 0.0) * (1.0 - depth) * 0.25;
    
    textureStore(writeTexture, gid.xy, clamp(color, vec4(0.0), vec4(1.0)));
}
