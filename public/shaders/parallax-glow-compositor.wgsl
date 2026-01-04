// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

// ═══════════════════════════════════════════════════════════════
//  Parallax Glow Compositor - PASS 2 of 2
//  Applies chromatic aberration, volumetric glow, and 
//  depth-aware compositing for volumetric zooms.
//  
//  Inputs:
//    - readTexture: Pass 1 volumetric zoom
//    - readDepthTexture: Pass 1 raymarch depth
//  
//  Previous Pass: volumetric-depth-zoom.wgsl
// ═══════════════════════════════════════════════════════════════

struct Uniforms {
  config: vec4<f32>;
  zoom_config: vec4<f32>;
  zoom_params: vec4<f32>;
  ripples: array<vec4<f32>, 50>;
};

// Mapping notes:
// - glowRadius = u.zoom_params.x
// - glowIntensity = u.zoom_params.y
// - aberration = u.zoom_params.z
// - bloomThreshold = u.zoom_params.w
// - final_params may be in extraBuffer[0..]

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Sample Pass 1 results
    let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Chromatic aberration (depth-based)
    let aberration = u.zoom_params.z * depth;
    let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(aberration, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(aberration, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    let aberrant = vec3<f32>(r, g, b);

    // Volumetric glow (depth-weighted blur)
    let glowRadius = u.zoom_params.x * 0.01;
    let bloomThreshold = u.zoom_params.w;
    var glow = vec3<f32>(0.0);
    var count = 0.0;
    for (var i: i32 = -2; i <= 2; i = i + 1) {
        for (var j: i32 = -2; j <= 2; j = j + 1) {
            let sampleUV = clamp(uv + vec2<f32>(f32(i), f32(j)) * glowRadius, vec2<f32>(0.0), vec2<f32>(1.0));
            let sampleDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
            let sampleColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;

            let depthWeight = exp(-abs(sampleDepth - depth) * 10.0);
            let brightness = length(sampleColor);
            let bloomWeight = max(brightness - bloomThreshold, 0.0);

            let w = depthWeight * bloomWeight;
            glow = glow + sampleColor * w;
            count = count + w;
        }
    }
    glow = glow / max(count, 1.0);

    // Composite with video (video assumed to be readTexture in this simplified compositor)
    let finalColor = mix(textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb, aberrant + glow * u.zoom_params.y, if (arrayLength(&extraBuffer) > 0u) { extraBuffer[0] } else { 0.5 });

    // Temporal feedback stored in dataTextureA (optional): keep it simple and write final result
    textureStore(writeTexture, vec2<u32>(global_id.xy), vec4<f32>(finalColor, 1.0));
    textureStore(writeDepthTexture, vec2<u32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}