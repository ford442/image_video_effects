// ═══════════════════════════════════════════════════════════════════════════════
//  gen-string-theory-structure.wgsl - Calabi-Yau Manifold Projection
//  
//  Upgraded: 2026-08-21 (Batch 42)
//  Techniques:
//    - Complex 3D folded manifold projection
//    - Audio-reactive dimensional folding via plasmaBuffer
//    - Interference patterns (String vibrations)
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

const PI: f32 = 3.14159265359;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<u32>(global_id.xy);
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) { return; }
    
    let uvFull = vec2<f32>(global_id.xy) / resolution;
    var uv = (vec2<f32>(global_id.xy) - resolution * 0.5) / resolution.y;
    let time = u.config.x;
    
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    
    // Complex folded space (Calabi-Yau projection approx)
    var z = uv * 3.0;
    for (var i = 0; i < 4; i = i + 1) {
        let angle = time * 0.2 + length(z) * (1.0 + bass * 0.5);
        let c = cos(angle);
        let s = sin(angle);
        z = vec2<f32>(c * z.x - s * z.y, s * z.x + c * z.y);
        z = abs(z) - vec2<f32>(0.5 + mids * 0.2);
        z = z * 1.5;
    }
    
    // String vibrations (Interference)
    let dist = length(z);
    let vibe = sin(dist * 20.0 - time * 5.0) * cos(z.x * 15.0 + time * 3.0);
    
    let glow = 0.05 / (abs(vibe) + 0.01);
    
    // Dimensional colors
    let col = vec3<f32>(0.5 + 0.5 * sin(z.x * 5.0), 0.5 + 0.5 * cos(z.y * 5.0), 0.8) * glow * (0.5 + treble);
    
    let inputColor = textureSampleLevel(readTexture, u_sampler, uvFull, 0.0);
    var finalRGB = mix(inputColor.rgb, col, 0.7);
    
    // Temporal Trails
    let prevColor = textureSampleLevel(dataTextureC, u_sampler, uvFull, 0.0).rgb;
    finalRGB = mix(finalRGB, prevColor, 0.85);
    
    textureStore(writeTexture, coord, vec4<f32>(finalRGB, 1.0));
    textureStore(dataTextureA, coord, vec4<f32>(finalRGB, 1.0));
}
