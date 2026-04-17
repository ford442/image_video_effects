// ═══════════════════════════════════════════════════════════════════
//  Sim: Fluid Feedback Field (Pass 2 - Density Advection)
//  Category: simulation
//  Features: simulation, multi-pass-2, navier-stokes, density-advection
//  Complexity: Very High
//  Created: 2026-03-22
//  By: Agent 3B - Advanced Hybrid Creator
// ═══════════════════════════════════════════════════════════════════
//  Pass 2: Advect density through velocity field
//  Add new density from mouse/input
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

// ═══ MAIN: DENSITY ADVECTION ═══
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
    
    let uv = vec2<f32>(gid.xy) / resolution;
    let pixel = 1.0 / resolution;
    let time = u.config.x;
    
    // Parameters
    let fadeRate = mix(0.95, 0.995, u.zoom_params.z);  // z: Fade rate
    
    // Read velocity from dataTextureA (written by Pass 1)
    let vel = textureLoad(dataTextureC, gid.xy, 0).xy;
    
    // Backtrace for density advection
    let prevPos = uv - vel * pixel * 3.0;
    
    // Advect density from previous position (reads from dataTextureC for temporal feedback)
    // NOTE: This expects a B→C copy between frames. Without it, density starts fresh each frame.
    var density = textureSampleLevel(dataTextureC, u_sampler, clamp(prevPos, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    
    // Add source at mouse position
    let mousePos = u.zoom_config.yz;
    let dist = length(uv - mousePos);
    let mouseInfluence = smoothstep(0.1, 0.0, dist);
    
    // Colorful injection based on time
    let hue = fract(time * 0.1);
    let sourceColor = vec3<f32>(
        0.5 + 0.5 * cos(hue * 6.28),
        0.5 + 0.5 * cos(hue * 6.28 + 2.09),
        0.5 + 0.5 * cos(hue * 6.28 + 4.18)
    );
    
    density += sourceColor * mouseInfluence * 0.2;
    
    // Add ripple sources
    for (var i = 0; i < 50; i++) {
        let ripple = u.ripples[i];
        if (ripple.z > 0.0) {
            let rippleAge = time - ripple.z;
            if (rippleAge > 0.0 && rippleAge < 3.0) {
                let rippleDist = length(uv - ripple.xy);
                let rippleInfluence = smoothstep(0.08, 0.0, rippleDist) * (1.0 - rippleAge / 3.0);
                density += sourceColor * rippleInfluence * 0.3;
            }
        }
    }
    
    // Fade density
    density *= fadeRate;
    
    // Store density in dataTextureB
    textureStore(dataTextureB, gid.xy, vec4<f32>(density, 1.0));
    
    // Minimal output
    textureStore(writeTexture, gid.xy, vec4<f32>(density, 1.0));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(1.0 - length(density) * 0.3, 0.0, 0.0, 0.0));
}
