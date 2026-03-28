// ═══════════════════════════════════════════════════════════════════════════════
//  pp-ssao.wgsl - Screen Space Ambient Occlusion
//  
//  Fake ambient occlusion for added depth
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

fn random(uv: vec2<f32>) -> f32 {
    return fract(sin(dot(uv, vec2<f32>(12.9898f, 78.233f))) * 43758.5453f);
}

fn getNormalFromDepth(uv: vec2<f32>, invRes: vec2<f32>) -> vec3<f32> {
    let c = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0f).r;
    let l = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(invRes.x, 0.0f), 0.0f).r;
    let r = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(invRes.x, 0.0f), 0.0f).r;
    let t = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0f, invRes.y), 0.0f).r;
    let b = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0f, invRes.y), 0.0f).r;
    
    return normalize(vec3<f32>(l - r, t - b, 0.01f));
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
    // param1: AO radius (0-1)
    // param2: AO intensity (0-1)
    // param3: Sample count quality (0=4, 0.5=8, 1.0=16)
    // param4: Color bleed amount (0-1)
    
    let radius = 0.01f + u.zoom_params.x * 0.05f;
    let intensity = u.zoom_params.y;
    let quality = u.zoom_params.z;
    let colorBleed = u.zoom_params.w;
    
    var sampleCount: i32;
    if (quality < 0.33f) {
        sampleCount = 4;
    } else if (quality < 0.66f) {
        sampleCount = 8;
    } else {
        sampleCount = 16;
    }
    
    let centerDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0f).r;
    let centerNormal = getNormalFromDepth(uv, invRes);
    
    var occlusion = 0.0f;
    var colorInfluence = vec3<f32>(0.0f);
    
    // Sample hemisphere
    for (var i: i32 = 0; i < sampleCount; i = i + 1) {
        let angle = f32(i) / f32(sampleCount) * 6.28318f + random(uv + f32(i)) * 0.5f;
        let dist = radius * (0.5f + random(uv * 2.0f + f32(i)) * 0.5f);
        
        let offset = vec2<f32>(cos(angle), sin(angle)) * dist;
        let sampleUV = uv + offset;
        
        // Skip if out of bounds
        if (sampleUV.x < 0.0f || sampleUV.x > 1.0f || sampleUV.y < 0.0f || sampleUV.y > 1.0f) {
            continue;
        }
        
        let sampleDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0f).r;
        let sampleColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0f).rgb;
        
        // Depth difference
        let depthDiff = sampleDepth - centerDepth;
        
        // If sample is closer (occluding), accumulate occlusion
        if (depthDiff < 0.0f && depthDiff > -radius * 2.0f) {
            let falloff = 1.0f - smoothstep(0.0f, radius, -depthDiff);
            occlusion += falloff;
            colorInfluence += sampleColor * falloff;
        }
    }
    
    occlusion = clamp(occlusion / f32(sampleCount), 0.0f, 1.0f) * intensity;
    
    // Sample original color
    let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0f).rgb;
    
    // Apply AO as darkening
    let ao = 1.0f - occlusion;
    var finalColor = color * (0.5f + 0.5f * ao); // Don't go completely black
    
    // Add color bleed from occluding surfaces
    if (colorBleed > 0.0f && occlusion > 0.0f) {
        colorInfluence /= max(occlusion * f32(sampleCount), 0.001f);
        finalColor = mix(finalColor, finalColor * colorInfluence * 1.5f, occlusion * colorBleed);
    }
    
    // Store AO factor in dataTextureA for debugging or cascade
    textureStore(dataTextureA, coord, vec4<f32>(vec3<f32>(ao), 1.0f));
    
    textureStore(writeTexture, coord, vec4<f32>(finalColor, 1.0f));
    textureStore(writeDepthTexture, coord, vec4<f32>(centerDepth, 0.0f, 0.0f, 1.0f));
}
