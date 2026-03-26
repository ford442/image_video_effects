// ═══════════════════════════════════════════════════════════════════════════════
//  Gen Xeno Botanical Synth Flora - Advanced Alpha with Depth-Layered
//  Category: complex-multi-effect
//  Alpha Mode: Depth-Layered Alpha + Physical Transmittance
//  Features: advanced-alpha, botanical, generative, depth-aware
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

// ═══ ADVANCED ALPHA FUNCTIONS ═══

// Mode 1: Depth-Layered Alpha
fn depthLayeredAlpha(color: vec3<f32>, uv: vec2<f32>, depthWeight: f32) -> f32 {
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let depthAlpha = mix(0.4, 1.0, depth);
    let lumaAlpha = mix(0.5, 1.0, luma);
    return mix(lumaAlpha, depthAlpha, depthWeight);
}

// Mode 4: Volumetric Alpha
fn volumetricAlpha(density: f32, thickness: f32) -> f32 {
    return 1.0 - exp(-density * thickness);
}

// Noise
fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    // ═══ AUDIO REACTIVITY ═══
    let audioOverall = u.config.y;
    let audioBass = u.config.y * 1.2;
    let audioMid = u.config.z;
    let audioHigh = u.config.w;
    let audioReactivity = 1.0 + audioOverall * 0.5;
    
    let growth = u.zoom_params.x;
    let complexity = u.zoom_params.y * 10.0 + 3.0;
    let depthWeight = u.zoom_params.z;
    let organic = u.zoom_params.w;
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // Botanical pattern
    let centered = uv - 0.5;
    let angle = atan2(centered.y, centered.x);
    let radius = length(centered);
    
    let branchPattern = sin(angle * complexity + time * 0.5 * audioReactivity) * cos(radius * 10.0 - time);
    let organicNoise = hash(floor(uv * 20.0) + time * 0.1 * audioReactivity);
    
    let flora = smoothstep(0.0, 0.5 + organic * organicNoise, branchPattern * growth);
    
    // Color
    let floraColorBase = vec3<f32>(
        0.2 + flora * 0.5,
        0.5 + flora * 0.3,
        0.3 + flora * 0.4
    );
    let floraColor = floraColorBase * depthLayeredAlpha(floraColorBase, uv, depthWeight);
    
    let alpha = volumetricAlpha(flora, 1.0) * depthLayeredAlpha(floraColorBase, uv, depthWeight);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(floraColor, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
