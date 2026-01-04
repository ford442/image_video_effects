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
//  Prismatic 3D Compositor - PASS 2 of 2
//  Adds parallax shifting, volumetric glow, chromatic aberration
//  and final composite with depth-aware blending.
//  
//  Inputs:
//    - readTexture: Pass 1 cloud color
//    - readDepthTexture: Pass 1 cloud depth
//  
//  Previous Pass: volumetric-rainbow-clouds.wgsl
// ═══════════════════════════════════════════════════════════════

struct Uniforms {
  config: vec4<f32>;
  zoom_config: vec4<f32>;
  zoom_params: vec4<f32>;
  ripples: array<vec4<f32>, 50>;
};

// Mapping notes:
// u.zoom_config.yz -> mouse X,Y
// u.zoom_config.w -> cameraZ
// u.zoom_params.x..w -> comp_params: glowRadius, glowIntensity, parallaxAmount, aberration
// u.ripples[0].x may be used for blend_params.x (videoBlend) if needed

@compute @workgroup_size(8,8,1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;
    let mousePos = vec2<f32>(u.zoom_config.y / dims.x, u.zoom_config.z / dims.y);
    let cameraZ = u.zoom_config.w;

    // Sample Pass 1 results (assume readTexture contains Pass1 color and readDepthTexture contains Pass1 depth)
    let cloudColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // 1) Parallax shift
    let parallax = u.zoom_params.z * depth * cameraZ;
    let parallaxUV = uv + (mousePos - vec2<f32>(0.5, 0.5)) * parallax;
    let parallaxColor = textureSampleLevel(readTexture, u_sampler, clamp(parallaxUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;

    // 2) Volumetric glow
    let glowRadius = u.zoom_params.x * 0.01;
    let glowIntensity = u.zoom_params.y;
    let glowThreshold = if (arrayLength(&extraBuffer) > 2u) { extraBuffer[2] } else { 0.2 };

    var glow = vec3<f32>(0.0);
    var count = 0.0;
    for (var x: i32 = -2; x <= 2; x = x + 1) {
        for (var y: i32 = -2; y <= 2; y = y + 1) {
            let sampleUV = clamp(uv + vec2<f32>(f32(x), f32(y)) * glowRadius, vec2<f32>(0.0), vec2<f32>(1.0));
            let sampleColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
            let sampleDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
            let brightness = length(sampleColor);
            let weight = exp(-sampleDepth) * max(brightness - glowThreshold, 0.0);
            glow = glow + sampleColor * weight;
            count = count + weight;
        }
    }
    glow = glow / max(count, 1.0);

    // 3) Chromatic aberration along depth
    let aberration = u.zoom_params.w * depth;
    let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(aberration,0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(aberration,0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    let aberrantColor = vec3<f32>(r, g, b);

    // 4) Composite with video (video assumed bound to historyTex via renderer when desired) - here we just mix with original readTexture
    let videoColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    // blend params: videoBlend in extraBuffer[0], glowThreshold in extraBuffer[1], depthSharpness in extraBuffer[2]
    let videoBlend = if (arrayLength(&extraBuffer) > 0u) { extraBuffer[0] } else { 0.5 };
    let finalColor = mix(videoColor, aberrantColor + glow * glowIntensity, videoBlend);

    // 5) Temporal feedback using history stored in dataTextureA (optional)
    let prev = textureSampleLevel(dataTextureC, comparison_sampler, uv, 0.0).rgb; // fallback attempt (may be unused)
    let feedback = mix(finalColor, prev, 0.85);

    textureStore(writeTexture, vec2<u32>(gid.xy), vec4<f32>(finalColor, 1.0));
    textureStore(writeDepthTexture, vec2<u32>(gid.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}