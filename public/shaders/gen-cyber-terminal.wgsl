// ═══════════════════════════════════════════════════════════════════════════════
//  gen-cyber-terminal.wgsl - Retro Terminal & Digital Rain
//  
//  Upgraded: 2026-08-21 (Batch 42)
//  Techniques:
//    - Falling digital rain (Matrix-style)
//    - Audio-reactive data stream speed and brightness
//    - CRT emulation (scanlines, phosphor decay, slight curvature)
//    - Temporal accumulation trails via dataTextureC
// ═══════════════════════════════════════════════════════════════════════════════

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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<u32>(global_id.xy);
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) { return; }
    
    let uvFull = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    let bass = plasmaBuffer[0].x;
    
    // CRT Curvature
    var uv = uvFull * 2.0 - 1.0;
    uv = uv * (1.0 + dot(uv, uv) * 0.1);
    uv = uv * 0.5 + 0.5;
    
    var col = vec3<f32>(0.0);
    
    if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
        // Digital Rain
        let cols = 80.0;
        let rows = 40.0;
        let gridUV = vec2<f32>(floor(uv.x * cols), floor(uv.y * rows));
        
        let speed = 2.0 + hash12(vec2<f32>(gridUV.x, 0.0)) * 5.0 + bass * 5.0;
        let dropPos = fract(time * speed + hash12(vec2<f32>(gridUV.x, 1.0)));
        let trail = fract(uv.y - dropPos);
        
        let intensity = (1.0 - trail) * step(trail, 0.3) * hash12(gridUV + floor(time * 10.0));
        col = vec3<f32>(0.1, 1.0, 0.2) * intensity * (1.0 + bass * 2.0);
        
        // Scanlines
        col *= 0.8 + 0.2 * sin(uvFull.y * resolution.y * 3.14159);
    }
    
    let inputColor = textureSampleLevel(readTexture, u_sampler, uvFull, 0.0);
    var finalRGB = mix(inputColor.rgb, col, 0.8);
    
    // Temporal Phosphor Trails
    let prevColor = textureSampleLevel(dataTextureC, u_sampler, uvFull, 0.0).rgb;
    finalRGB = mix(finalRGB, prevColor, 0.75);
    
    textureStore(writeTexture, coord, vec4<f32>(finalRGB, 1.0));
    textureStore(dataTextureA, coord, vec4<f32>(finalRGB, 1.0));
}
