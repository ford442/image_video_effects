// ═══════════════════════════════════════════════════════════════════════════════
//  pp-vignette.wgsl - Vignette, Film Grain, & Vintage Effects
//  
//  Classic photo/videographic post-processing
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

// Hash function for grain
fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031f, 0.1030f, 0.0973f));
    p3 += dot(p3, p3.yzx + 33.33f);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031f);
    p3 += dot(p3, p3.yzx + 33.33f);
    return fract((p3.x + p3.y) * p3.z);
}

// Vignette calculation
fn calculateVignette(uv: vec2<f32>, intensity: f32, smoothness: f32, roundness: f32) -> f32 {
    let center = uv - 0.5f;
    // Roundness: 0 = oval, 1 = circular
    let dist = length(vec2<f32>(center.x * (1.0f + roundness), center.y));
    return 1.0f - smoothstep(smoothness, 1.0f, dist * (1.0f + intensity));
}

// Film grain
fn filmGrain(uv: vec2<f32>, intensity: f32, time: f32) -> f32 {
    let grain = hash12(uv * 1000.0f + time);
    // Convert uniform to triangular distribution for more natural look
    let tri = grain + hash12(uv * 1000.0f + time + 1.0f) - 0.5f;
    return tri * intensity;
}

// Sepia tone
fn applySepia(color: vec3<f32>, amount: f32) -> vec3<f32> {
    let sepia = vec3<f32>(
        dot(color, vec3<f32>(0.393f, 0.769f, 0.189f)),
        dot(color, vec3<f32>(0.349f, 0.686f, 0.168f)),
        dot(color, vec3<f32>(0.272f, 0.534f, 0.131f))
    );
    return mix(color, sepia, amount);
}

// Lift/gamma/gain (color grading)
fn colorGrade(color: vec3<f32>, lift: f32, gamma: f32, gain: f32) -> vec3<f32> {
    var c = color;
    // Lift (shadows)
    c = c + lift * (1.0f - c);
    // Gamma (midtones)
    c = pow(c, vec3<f32>(1.0f / (gamma + 0.5f)));
    // Gain (highlights)
    c = c * (1.0f + gain);
    return c;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Parameters:
    // param1: Vignette intensity (0-1)
    // param2: Grain intensity (0-1)
    // param3: Sepia/Color style (0=none, 0.5=warm, 1.0=sepia)
    // param4: Effect blend (0=normal, 0.5=overlay, 1.0=multiply)
    
    let vignetteIntensity = u.zoom_params.x;
    let grainIntensity = u.zoom_params.y;
    let colorStyle = u.zoom_params.z;
    let blendMode = u.zoom_params.w;
    
    // Sample original
    var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0f).rgb;
    
    // Apply vignette
    let vignette = calculateVignette(uv, vignetteIntensity * 2.0f, 0.3f, 0.5f);
    color = color * vignette;
    
    // Apply film grain
    if (grainIntensity > 0.01f) {
        let grain = filmGrain(uv, grainIntensity * 0.3f, time);
        color = color + vec3<f32>(grain);
    }
    
    // Apply color grading
    if (colorStyle > 0.01f) {
        if (colorStyle < 0.33f) {
            // Warm
            color = colorGrade(color, -0.05f, 0.1f, 0.05f);
            color.r = color.r * 1.1f;
            color.b = color.b * 0.9f;
        } else if (colorStyle < 0.66f) {
            // Cool
            color = colorGrade(color, 0.0f, 0.0f, 0.0f);
            color.r = color.r * 0.9f;
            color.b = color.b * 1.1f;
        } else {
            // Full sepia
            color = applySepia(color, colorStyle);
        }
    }
    
    // Optional: scanlines for retro effect
    if (grainIntensity > 0.7f) {
        let scanline = sin(uv.y * resolution.y * 0.5f) * 0.5f + 0.5f;
        color = color * (0.9f + scanline * 0.1f);
    }
    
    // Clamp
    color = clamp(color, vec3<f32>(0.0f), vec3<f32>(2.0f));
    
    textureStore(writeTexture, coord, vec4<f32>(color, 1.0f));
    textureStore(writeDepthTexture, coord, vec4<f32>(
        textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0f).r,
        0.0f, 0.0f, 1.0f
    ));
}
