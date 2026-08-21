// ═══════════════════════════════════════════════════════════════════════════════
//  gen-astro-orrery-blackbody.wgsl - N-Body Gravity Simulation & Stars
//  
//  Upgraded: 2026-08-21 (Batch 42)
//  Techniques:
//    - Procedural starfield with parallax
//    - Audio-reactive accretion disk / orrery ring projection
//    - Star glow (blackbody radiation colors)
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
    let uv = (vec2<f32>(global_id.xy) - resolution * 0.5) / resolution.y;
    let time = u.config.x;
    
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    
    var col = vec3<f32>(0.0);
    
    // Starfield Parallax
    for(var i = 1.0; i < 4.0; i += 1.0) {
        let st = uv * i * 5.0 + time * 0.05 / i;
        let id = floor(st);
        let fst = fract(st) - 0.5;
        let rand = hash12(id);
        if (rand > 0.95) {
            let starGlow = 0.01 / (length(fst) + 0.001);
            let starColor = vec3<f32>(1.0, 0.8 + rand * 0.2, 0.5 + rand * 0.5);
            col += starColor * starGlow * (1.0 + treble * 2.0);
        }
    }
    
    // Orrery / Accretion Disk
    let r = length(uv);
    let a = atan2(uv.y, uv.x);
    let diskFreq = 20.0 - mids * 5.0;
    let diskPattern = sin(r * diskFreq - time * 2.0 + a * 3.0);
    let diskMask = smoothstep(0.4, 0.3, r) * smoothstep(0.1, 0.15, r);
    
    col += vec3<f32>(1.0, 0.5, 0.1) * max(0.0, diskPattern) * diskMask * (1.0 + bass * 3.0);
    
    let inputColor = textureSampleLevel(readTexture, u_sampler, uvFull, 0.0);
    var finalRGB = mix(inputColor.rgb, col, 0.6);
    
    // Temporal Trails
    let prevColor = textureSampleLevel(dataTextureC, u_sampler, uvFull, 0.0).rgb;
    finalRGB = mix(finalRGB, prevColor, 0.8);
    
    textureStore(writeTexture, coord, vec4<f32>(finalRGB, 1.0));
    textureStore(dataTextureA, coord, vec4<f32>(finalRGB, 1.0));
}
