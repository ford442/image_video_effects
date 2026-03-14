// ═══════════════════════════════════════════════════════════════════════════════
//  pp-chromatic.wgsl - Chromatic Aberration & Lens Distortion
//  
//  RGB channel separation with barrel/pincushion distortion
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

// Barrel/pincushion distortion
fn distort(uv: vec2<f32>, strength: f32) -> vec2<f32> {
    let center = uv - 0.5f;
    let dist = length(center);
    let distSq = dist * dist;
    
    // Barrel: strength > 0, Pincushion: strength < 0
    let factor = 1.0f + strength * distSq;
    
    return center * factor + 0.5f;
}

// Radial chromatic aberration
fn sampleChromatic(uv: vec2<f32>, amount: f32, direction: vec2<f32>) -> vec3<f32> {
    let rUV = uv + direction * amount * 1.0f;
    let gUV = uv + direction * amount * 0.5f;
    let bUV = uv; // No shift for blue
    
    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0f).r;
    let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0f).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0f).b;
    
    return vec3<f32>(r, g, b);
}

// Lens blur/vignette
fn lensVignette(uv: vec2<f32>, intensity: f32) -> f32 {
    let dist = length(uv - 0.5f);
    return 1.0f - pow(dist * 1.5f, intensity * 2.0f);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let centerDir = normalize(uv - 0.5f);
    
    // Parameters:
    // param1: Chromatic amount (0-1)
    // param2: Distortion strength (-1 to 1, barrel/pincushion)
    // param3: Vignette intensity (0-1)
    // param4: Aberration mode (0=radial, 0.5=axial, 1.0=random)
    
    let chromaAmount = u.zoom_params.x * 0.05f; // Max 5% shift
    let distortion = (u.zoom_params.y - 0.5f) * 2.0f; // -1 to 1
    let vignette = u.zoom_params.z;
    let mode = u.zoom_params.w;
    
    // Apply distortion
    let distortedUV = distort(uv, distortion);
    
    // Skip if outside frame
    if (distortedUV.x < 0.0f || distortedUV.x > 1.0f || 
        distortedUV.y < 0.0f || distortedUV.y > 1.0f) {
        textureStore(writeTexture, coord, vec4<f32>(0.0f, 0.0f, 0.0f, 1.0f));
        return;
    }
    
    var color: vec3<f32>;
    
    // Sample based on aberration mode
    if (mode < 0.33f) {
        // Radial - RGB separate outward from center
        color = sampleChromatic(distortedUV, chromaAmount, centerDir);
    } else if (mode < 0.66f) {
        // Axial - shift along X axis
        color = sampleChromatic(distortedUV, chromaAmount, vec2<f32>(1.0f, 0.0f));
    } else {
        // Random/directional - uses time for variation
        let time = u.config.x;
        let angle = time * 0.5f;
        let dir = vec2<f32>(cos(angle), sin(angle));
        color = sampleChromatic(distortedUV, chromaAmount, dir);
    }
    
    // Apply vignette
    let vignetteFactor = lensVignette(uv, vignette);
    color *= vignetteFactor;
    
    // Optional: edge blur for lens effect
    if (vignette > 0.5f) {
        let edgeDist = length(uv - 0.5f) * 2.0f;
        if (edgeDist > 0.8f) {
            let blurAmount = (edgeDist - 0.8f) * 0.02f;
            var blurred = vec3<f32>(0.0f);
            for (var i: i32 = 0; i < 4; i = i + 1) {
                let offset = vec2<f32>(
                    cos(f32(i) * 1.57f) * blurAmount,
                    sin(f32(i) * 1.57f) * blurAmount
                );
                blurred += textureSampleLevel(readTexture, u_sampler, distortedUV + offset, 0.0f).rgb;
            }
            color = mix(color, blurred * 0.25f, (edgeDist - 0.8f) * 5.0f);
        }
    }
    
    textureStore(writeTexture, coord, vec4<f32>(color, 1.0f));
    textureStore(writeDepthTexture, coord, vec4<f32>(
        textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0f).r,
        0.0f, 0.0f, 1.0f
    ));
}
