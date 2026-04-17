// ═══════════════════════════════════════════════════════════════════
//  Galaxy - Animated galaxy simulation with RGBA processing
//  Category: generative
//  Features: upgraded-rgba, depth-aware, procedural
//  Upgraded: 2026-03-22
//  By: Agent 1A - Alpha Channel Specialist
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

// Hash function for pseudo-random numbers
fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.6))
    );
    return fract(sin(q) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let coord = vec2<i32>(global_id.xy);
    let time = u.config.x;
    
    // ═══ SAMPLE INPUT FROM PREVIOUS LAYER ═══
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // ═══ AUDIO REACTIVITY ═══
    let audioOverall = u.config.y;
    let audioBass = u.config.y * 1.2;
    let audioMid = u.config.z;
    let audioHigh = u.config.w;
    let audioReactivity = 1.0 + audioOverall * 0.5;
    
    // Opacity control - allows blending with input
    let opacity = mix(0.5, 1.0, u.zoom_params.x);
    
    // Centered UV coordinates
    let p = (uv - 0.5) * 2.0;
    let aspect = resolution.x / resolution.y;
    var screenP = p;
    screenP.x *= aspect;
    
    // Galaxy parameters from uniforms
    let zoom = u.zoom_config.x;
    let arms = mix(2.0, 6.0, u.zoom_params.y);
    let rotation = mix(0.5, 3.0, u.zoom_params.z);
    let spread = mix(0.1, 0.5, u.zoom_params.w);
    let brightness = 1.25;
    
    // Convert to polar coordinates
    let radius = length(screenP);
    let angle = atan2(screenP.y, screenP.x);
    
    // Galaxy spiral pattern
    let spiralAngle = angle + rotation * time * 0.1 * audioReactivity - radius * 2.0;
    let armModulation = cos(spiralAngle * arms);
    
    // Density falloff from center
    let coreDensity = exp(-radius * 3.0);
    let armDensity = smoothstep(1.0 - spread, 1.0, armModulation) * exp(-radius * 1.5);
    let density = (coreDensity * 0.6 + armDensity * 0.4) * brightness;
    
    // Star generation
    let starHash = hash3(vec3<f32>(floor(screenP * 50.0), time * 0.01 * audioReactivity));
    let star = step(0.997, starHash.x) * starHash.y;
    
    // Color palette: blue core → white → red/yellow arms
    let coreColor = vec3<f32>(0.3, 0.5, 1.0);
    let armColor = vec3<f32>(1.0, 0.8, 0.4);
    let starColor = vec3<f32>(1.0, 1.0, 1.0);
    
    let baseColor = mix(coreColor, armColor, smoothstep(0.0, 0.5, radius));
    var generatedColor = baseColor * density + starColor * star;
    
    // Add twinkling
    let twinkle = sin(time * 3.0 * audioReactivity + radius * 10.0) * 0.1 + 0.9;
    generatedColor = generatedColor * twinkle;
    
    // Vignette
    let vignette = 1.0 - radius * 0.5;
    generatedColor = generatedColor * vignette;
    
    // Calculate alpha based on brightness/presence
    let luma = dot(generatedColor, vec3<f32>(0.299, 0.587, 0.114));
    let presence = smoothstep(0.05, 0.2, luma);
    let alpha = mix(0.0, 1.0, presence);
    
    // ═══ BLEND WITH INPUT ═══
    let finalColor = mix(inputColor.rgb, generatedColor, alpha * opacity);
    let finalAlpha = max(inputColor.a, alpha * opacity);
    
    // Depth: closer stars are brighter/closer to center
    let generatedDepth = 1.0 - radius * 0.5;
    let finalDepth = mix(inputDepth, generatedDepth, alpha * opacity);
    
    // Write RGBA color
    textureStore(writeTexture, coord, vec4<f32>(clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.0)), finalAlpha));
    
    // Write depth
    textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 0.0));
}
