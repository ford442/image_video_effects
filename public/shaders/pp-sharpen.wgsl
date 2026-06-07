// ═══════════════════════════════════════════════════════════════════════════════
//  pp-sharpen.wgsl - Unsharp Mask & Edge Enhancement
//  
//  High-quality sharpening with halo control
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

// Gaussian blur 3x3 approximation
fn blur3x3(uv: vec2<f32>, invRes: vec2<f32>) -> vec3<f32> {
    let offsets = array<vec2<f32>, 8>(
        vec2<f32>(-1.0f, -1.0f), vec2<f32>(0.0f, -1.0f), vec2<f32>(1.0f, -1.0f),
        vec2<f32>(-1.0f,  0.0f),                      vec2<f32>(1.0f,  0.0f),
        vec2<f32>(-1.0f,  1.0f), vec2<f32>(0.0f,  1.0f), vec2<f32>(1.0f,  1.0f)
    );
    
    let weights = array<f32, 8>(
        0.0625f, 0.125f, 0.0625f,
        0.125f,           0.125f,
        0.0625f, 0.125f, 0.0625f
    );
    
    var sum = textureSampleLevel(readTexture, u_sampler, uv, 0.0f).rgb * 0.25f;
    
    for (var i: i32 = 0; i < 8; i = i + 1) {
        sum += textureSampleLevel(readTexture, u_sampler, uv + offsets[i] * invRes, 0.0f).rgb * weights[i];
    }
    
    return sum;
}

// Edge detection (Sobel)
fn edgeDetection(uv: vec2<f32>, invRes: vec2<f32>) -> f32 {
    let sx = array<f32, 9>(-1.0f, 0.0f, 1.0f, -2.0f, 0.0f, 2.0f, -1.0f, 0.0f, 1.0f);
    let sy = array<f32, 9>(-1.0f, -2.0f, -1.0f, 0.0f, 0.0f, 0.0f, 1.0f, 2.0f, 1.0f);
    
    let offsets = array<vec2<f32>, 9>(
        vec2<f32>(-1.0f, -1.0f), vec2<f32>(0.0f, -1.0f), vec2<f32>(1.0f, -1.0f),
        vec2<f32>(-1.0f,  0.0f), vec2<f32>(0.0f,  0.0f), vec2<f32>(1.0f,  0.0f),
        vec2<f32>(-1.0f,  1.0f), vec2<f32>(0.0f,  1.0f), vec2<f32>(1.0f,  1.0f)
    );
    
    var gx = 0.0f;
    var gy = 0.0f;
    
    for (var i: i32 = 0; i < 9; i = i + 1) {
        let lum = dot(
            textureSampleLevel(readTexture, u_sampler, uv + offsets[i] * invRes, 0.0f).rgb,
            vec3<f32>(0.299f, 0.587f, 0.114f)
        );
        gx += lum * sx[i];
        gy += lum * sy[i];
    }
    
    return length(vec2<f32>(gx, gy));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let invRes = 1.0f / resolution;
    
    // Parameters:
    // param1: Sharpen amount (0-1)
    // param2: Radius (0=small, 1=large)
    // param3: Edge mask threshold (0-1)
    // param4: Mode (0=unsharp, 0.5=edge enhance, 1.0=detail)
    
    let amount = u.zoom_params.x;
    let radius = u.zoom_params.y;
    let edgeThreshold = u.zoom_params.z;
    let mode = u.zoom_params.w;
    
    // Sample original and blurred
    let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0f).rgb;
    let blurred = blur3x3(uv, invRes * (0.5f + radius));
    
    // Edge detection for masking
    let edgeStrength = edgeDetection(uv, invRes);
    let edgeMask = smoothstep(edgeThreshold, edgeThreshold + 0.2f, edgeStrength);
    
    var sharpened: vec3<f32>;
    
    if (mode < 0.33f) {
        // Unsharp mask: original + (original - blurred) * amount
        let detail = original - blurred;
        sharpened = original + detail * amount * 2.0f;
    } else if (mode < 0.66f) {
        // Edge enhance: amplify edges only
        let edgeBoost = edgeMask * amount;
        sharpened = mix(original, original * (1.0f + edgeBoost), edgeMask);
    } else {
        // Detail mode: high-pass filter
        let highPass = original - blurred;
        let detail = smoothstep(0.0f, 0.5f, length(highPass)) * highPass;
        sharpened = original + detail * amount * 3.0f;
    }
    
    // Clamp to prevent artifacts
    sharpened = clamp(sharpened, vec3<f32>(0.0f), vec3<f32>(2.0f));
    
    // Store blurred version in dataTextureA for potential cascade
    textureStore(dataTextureA, coord, vec4<f32>(blurred, 1.0f));
    
    textureStore(writeTexture, coord, vec4<f32>(sharpened, 1.0f));
    textureStore(writeDepthTexture, coord, vec4<f32>(
        textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0f).r,
        0.0f, 0.0f, 1.0f
    ));
}
