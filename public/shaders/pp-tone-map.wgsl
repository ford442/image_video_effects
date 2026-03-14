// ═══════════════════════════════════════════════════════════════════════════════
//  pp-tone-map.wgsl - HDR Tone Mapping Post-Process
//  
//  Multiple algorithms: ACES, Uncharted 2, Reinhard, AgX
//  Gamut mapping for wide color spaces
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

// ═══════════════════════════════════════════════════════════════════════════════
//  TONE MAPPING CURVES
// ═══════════════════════════════════════════════════════════════════════════════

// ACES Filmic Tone Mapping (high contrast, cinematic)
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51f;
    let b = 0.03f;
    let c = 2.43f;
    let d = 0.59f;
    let e = 0.14f;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0f), vec3<f32>(1.0f));
}

// Uncharted 2 Tone Mapping (smooth rolloff)
fn uncharted2Tonemap(x: vec3<f32>) -> vec3<f32> {
    let A = 0.15f;
    let B = 0.50f;
    let C = 0.10f;
    let D = 0.20f;
    let E = 0.02f;
    let F = 0.30f;
    let W = 11.2f;
    
    let whiteScale = 1.0f / (((W * (A * W + C * B) + D * E) / (W * (A * W + B) + D * F)) - E / F);
    
    var c = ((x * (A * x + C * B) + D * E) / (x * (A * x + B) + D * F)) - E / F;
    c *= whiteScale;
    return clamp(c, vec3<f32>(0.0f), vec3<f32>(1.0f));
}

// Reinhard Tone Mapping (simple, film-like)
fn reinhardToneMap(x: vec3<f32>) -> vec3<f32> {
    return x / (1.0f + x);
}

// Reinhard Extended (with white point)
fn reinhardExtended(x: vec3<f32>, whitePoint: f32) -> vec3<f32> {
    let num = x * (1.0f + x / (whitePoint * whitePoint));
    return num / (1.0f + x);
}

// AgX (modern, neutral, no color shift)
// Simplified approximation
fn agxToneMap(x: vec3<f32>) -> vec3<f32> {
    let sigmoid = (x * (x * 0.8f + 0.1f)) / (x * (x * 0.7f + 0.4f) + 0.05f);
    return clamp(sigmoid, vec3<f32>(0.0f), vec3<f32>(1.0f));
}

// ═══════════════════════════════════════════════════════════════════════════════
//  GAMMA & COLOR SPACE
// ═══════════════════════════════════════════════════════════════════════════════

fn linearToSRGB(x: f32) -> f32 {
    if (x <= 0.0031308f) {
        return x * 12.92f;
    }
    return 1.055f * pow(x, 1.0f / 2.4f) - 0.055f;
}

fn linearToSRGB3(x: vec3<f32>) -> vec3<f32> {
    return vec3<f32>(
        linearToSRGB(x.r),
        linearToSRGB(x.g),
        linearToSRGB(x.b)
    );
}

fn sRGBToLinear(x: f32) -> f32 {
    if (x <= 0.04045f) {
        return x / 12.92f;
    }
    return pow((x + 0.055f) / 1.055f, 2.4f);
}

fn sRGBToLinear3(x: vec3<f32>) -> vec3<f32> {
    return vec3<f32>(
        sRGBToLinear(x.r),
        sRGBToLinear(x.g),
        sRGBToLinear(x.b)
    );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  EXPOSURE & CONTRAST
// ═══════════════════════════════════════════════════════════════════════════════

fn applyExposure(color: vec3<f32>, exposure: f32) -> vec3<f32> {
    return color * pow(2.0f, exposure);
}

fn applyContrast(color: vec3<f32>, contrast: f32) -> vec3<f32> {
    return (color - 0.5f) * contrast + 0.5f;
}

fn applySaturation(color: vec3<f32>, saturation: f32) -> vec3<f32> {
    let luminance = dot(color, vec3<f32>(0.299f, 0.587f, 0.114f));
    return mix(vec3<f32>(luminance), color, saturation);
}

// ═══════════════════════════════════════════════════════════════════════════════
//  MAIN
// ═══════════════════════════════════════════════════════════════════════════════

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    
    // Parameters:
    // param1: Tone map algorithm (0=ACES, 0.33=Uncharted, 0.66=Reinhard, 1.0=AgX)
    // param2: Exposure (-2 to +2)
    // param3: Contrast (0.5 to 2.0)
    // param4: Saturation (0.0 to 2.0)
    
    let algorithm = u.zoom_params.x;
    let exposure = (u.zoom_params.y - 0.5f) * 4.0f; // -2 to +2
    let contrast = u.zoom_params.z * 2.0f; // 0-2
    let saturation = u.zoom_params.w * 2.0f; // 0-2
    
    // Sample input (HDR range)
    let hdr = textureSampleLevel(readTexture, u_sampler, uv, 0.0f).rgb;
    
    // Apply exposure (in linear space)
    var color = applyExposure(hdr, exposure);
    
    // Apply tone mapping
    var ldr: vec3<f32>;
    if (algorithm < 0.25f) {
        ldr = acesToneMap(color);
    } else if (algorithm < 0.5f) {
        ldr = uncharted2Tonemap(color);
    } else if (algorithm < 0.75f) {
        ldr = reinhardToneMap(color);
    } else {
        ldr = agxToneMap(color);
    }
    
    // Apply contrast and saturation
    ldr = applyContrast(ldr, contrast);
    ldr = applySaturation(ldr, saturation);
    
    // Final clamp
    ldr = clamp(ldr, vec3<f32>(0.0f), vec3<f32>(1.0f));
    
    // Output
    textureStore(writeTexture, coord, vec4<f32>(ldr, 1.0f));
    
    // Pass through depth
    textureStore(writeDepthTexture, coord, vec4<f32>(
        textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0f).r,
        0.0f, 0.0f, 1.0f
    ));
}
