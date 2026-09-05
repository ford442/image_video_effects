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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<u32>(global_id.xy);
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) { return; }
    
    let uvFull = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    let audio = plasmaBuffer[0].xyz;
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    let gridDensity = clamp(u.zoom_params.x, 0.1, 5.0);
    let glyphSharpness = clamp(u.zoom_params.y, 0.0, 1.0);
    let characterBrightness = clamp(u.zoom_params.z, 0.5, 2.0);
    let scanlineBloom = clamp(u.zoom_params.w, 0.0, 2.0);
    
    // CRT Curvature
    var uv = uvFull * 2.0 - 1.0;
    uv = uv * (1.0 + dot(uv, uv) * 0.1);
    uv = uv * 0.5 + 0.5;
    
    var col = vec3<f32>(0.0);
    
    if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
        // Digital Rain
        let cols = 32.0 + gridDensity * 38.0;
        let rows = cols * resolution.y / max(resolution.x, 1.0) * 0.9;
        let gridUV = vec2<f32>(floor(uv.x * cols), floor(uv.y * rows));
        let cellUV = fract(uv * vec2<f32>(cols, rows)) - 0.5;
        
        let speed = 2.0 + hash12(vec2<f32>(gridUV.x, 0.0)) * 5.0 + bass * 5.0;
        let dropPos = fract(time * speed + hash12(vec2<f32>(gridUV.x, 1.0)));
        let trail = fract(uv.y - dropPos);
        
        let dataBit = hash12(gridUV + floor(time * (7.0 + treble * 8.0)));
        let strokeWidth = mix(0.22, 0.055, glyphSharpness);
        let vertical = 1.0 - smoothstep(strokeWidth, strokeWidth + 0.035, abs(cellUV.x + (dataBit - 0.5) * 0.24));
        let horizontal = 1.0 - smoothstep(strokeWidth, strokeWidth + 0.035, abs(cellUV.y - (fract(dataBit * 7.0) - 0.5) * 0.35));
        let glyph = max(vertical * step(abs(cellUV.y), 0.42), horizontal * step(abs(cellUV.x), 0.38));
        let intensity = (1.0 - trail) * step(trail, 0.34) * glyph;
        let phosphor = mix(vec3<f32>(0.03, 0.72, 0.16), vec3<f32>(0.12, 1.0, 0.68), mids);
        col = phosphor * intensity * characterBrightness * (1.0 + bass * 2.0 + treble * dataBit);
        
        // Scanlines
        let scan = 0.78 + 0.22 * sin(uvFull.y * resolution.y * 3.14159);
        col *= scan;
        col += phosphor * pow(max(scan, 0.0), 10.0) * scanlineBloom * intensity * 0.18;
    }
    
    let inputColor = textureSampleLevel(readTexture, u_sampler, uvFull, 0.0);
    var finalRGB = mix(inputColor.rgb, col, 0.8);
    
    // Temporal Phosphor Trails
    let prevColor = textureLoad(dataTextureC, vec2<i32>(coord), 0).rgb;
    let hdrColor = clamp(mix(finalRGB, prevColor, 0.62 + scanlineBloom * 0.07), vec3<f32>(0.0), vec3<f32>(5.0));
    let mappedColor = acesToneMap(hdrColor * 1.12);
    let phosphorEnergy = dot(mappedColor, vec3<f32>(0.2126, 0.7152, 0.0722));
    let alpha = clamp(phosphorEnergy * 1.35 + length(col) * 0.18, 0.03, 0.98);
    
    textureStore(writeTexture, coord, vec4<f32>(mappedColor, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(hdrColor, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(clamp(phosphorEnergy, 0.0, 1.0), 0.0, 0.0, 0.0));
}
