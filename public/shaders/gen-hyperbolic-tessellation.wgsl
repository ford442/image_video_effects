// ═══════════════════════════════════════════════════════════════════════════════
//  gen-hyperbolic-tessellation.wgsl - Poincare Disk Conformal Mapping
//  
//  Upgraded: 2026-08-21 (Batch 42)
//  Techniques:
//    - Hyperbolic geometry projection (Poincare Disk model)
//    - Audio-reactive conformal mapping and scaling
//    - Kaleidoscope IFS reflections
//    - Temporal feedback trails via dataTextureC
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

// Mobius transformation for conformal mapping
fn mobius(z: vec2<f32>, a: vec2<f32>) -> vec2<f32> {
    // (z - a) / (1 - a_conjugate * z)
    let num = z - a;
    let a_conj = vec2<f32>(a.x, -a.y);
    let den_c = vec2<f32>(1.0, 0.0) - vec2<f32>(a_conj.x * z.x - a_conj.y * z.y, a_conj.x * z.y + a_conj.y * z.x);
    let den_mag2 = dot(den_c, den_c);
    
    return vec2<f32>(
        num.x * den_c.x + num.y * den_c.y,
        num.y * den_c.x - num.x * den_c.y
    ) / max(den_mag2, 0.001);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<u32>(global_id.xy);
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) { return; }
    
    let uv = (vec2<f32>(global_id.xy) - resolution * 0.5) / resolution.y;
    let uvFull = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    
    var z = uv * 2.0;
    
    // Only process inside the Poincare disk
    var mask = smoothstep(1.0, 0.98, length(z));
    
    if (mask > 0.0) {
        // Audio-reactive translation inside the disk
        let a = vec2<f32>(sin(time * 0.5) * 0.5 * (1.0 + bass), cos(time * 0.3) * 0.5 * (1.0 + mids));
        z = mobius(z, a);
        
        // Kaleidoscopic IFS folding
        for(var i = 0; i < 5; i = i + 1) {
            z = abs(z);
            let rot = mat2x2<f32>(cos(PI/4.0), -sin(PI/4.0), sin(PI/4.0), cos(PI/4.0));
            z = rot * z;
            z = z * 1.5 - vec2<f32>(0.5);
        }
    }
    
    let pattern = sin(z.x * 20.0) * cos(z.y * 20.0);
    let col = vec3<f32>(0.5 + 0.5 * pattern, 0.5 + 0.5 * sin(pattern + time), 0.5 + 0.5 * cos(pattern - time)) * mask;
    
    let inputColor = textureSampleLevel(readTexture, u_sampler, uvFull, 0.0);
    var finalRGB = mix(inputColor.rgb, col, mask * 0.8);
    
    // Temporal Trails
    let prevColor = textureSampleLevel(dataTextureC, u_sampler, uvFull, 0.0).rgb;
    finalRGB = mix(finalRGB, prevColor, 0.7);
    
    textureStore(writeTexture, coord, vec4<f32>(finalRGB, max(inputColor.a, mask)));
    textureStore(dataTextureA, coord, vec4<f32>(finalRGB, max(inputColor.a, mask)));
}
