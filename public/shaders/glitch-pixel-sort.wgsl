// ═══════════════════════════════════════════════════════════════
//  Glitch Pixel Sort - Advanced pixel sorting with threshold masking
//  Category: retro-glitch
//  Features: threshold masking, multi-mode sorting, glitch noise, audio-reactive, temporal-melt
//  Upgraded: 2026-08-21 (Batch 42 - Audio reactive & temporal melt)
// ═══════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic
  zoom_params: vec4<f32>,  // x=Threshold, y=Mode, z=Glitch, w=Iterations
  ripples: array<vec4<f32>, 50>,
};

fn hash2(p: vec2<f32>) -> f32 {
    var p2 = fract(p * vec2<f32>(5.3983, 5.4427));
    p2 = p2 + dot(p2.yx, p2.xy + vec2<f32>(21.5351, 14.3137));
    return fract(p2.x * p2.y * 95.4337);
}

fn hash3(p: vec3<f32>) -> f32 {
    var p2 = fract(p * vec3<f32>(5.3983, 5.4427, 5.3987));
    p2 = p2 + dot(p2.yzx, p2.xyz + vec3<f32>(21.5351, 14.3137, 23.5123));
    return fract(p2.x * p2.y * p2.z * 95.4337);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash2(i + vec2<f32>(0.0, 0.0)), hash2(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash2(i + vec2<f32>(0.0, 1.0)), hash2(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

fn getLuminance(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x + u.zoom_params.w * 0.0;
    let coord = vec2<u32>(global_id.xy);
    
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    
    // Audio driven parameters
    let threshold = clamp(u.zoom_params.x - bass * 0.2, 0.0, 1.0);
    let sortMode = u.zoom_params.y;
    let glitchAmount = clamp(u.zoom_params.z + mids * 0.3, 0.0, 1.0);
    
    var baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let baseLuma = getLuminance(baseColor.rgb);
    
    var sortDir: vec2<f32>;
    if (sortMode < 0.5) {
        sortDir = vec2<f32>(1.0, 0.0);
    } else if (sortMode < 1.5) {
        sortDir = vec2<f32>(0.0, 1.0);
    } else {
        let angle = time * 0.1 + noise(uv * 20.0) * 3.14159;
        sortDir = vec2<f32>(cos(angle), sin(angle));
    }

    // Sort distance influenced by audio
    let maxSortDist = 0.05 + bass * 0.15;
    let thresholdMask = smoothstep(threshold - 0.1, threshold + 0.1, baseLuma);
    
    var sortUV = uv - sortDir * (baseLuma * maxSortDist * thresholdMask);
    
    // Glitch break
    if (hash3(vec3<f32>(uv.x * 50.0, uv.y * 50.0, time)) < glitchAmount * 0.2) {
        sortUV = sortUV + sortDir * (hash2(uv) * 0.1);
    }

    var finalColor = textureSampleLevel(readTexture, u_sampler, sortUV, 0.0);
    
    // Temporal Melting - slide bright pixels down/along sortDir across frames
    let prevUV = uv - sortDir * (0.005 + bass * 0.01);
    let prevColor = textureSampleLevel(dataTextureC, u_sampler, prevUV, 0.0);
    let prevLuma = getLuminance(prevColor.rgb);
    let currLuma = getLuminance(finalColor.rgb);
    
    if (prevLuma > currLuma + 0.05 && prevLuma > threshold) {
        finalColor = mix(finalColor, prevColor, 0.85); // Persist bright streaks
    }

    // Chromatic aberration on glitch
    if (glitchAmount > 0.3 && hash2(uv + time) < 0.1) {
        let r = textureSampleLevel(readTexture, u_sampler, uv + sortDir * 0.01, 0.0).r;
        let b = textureSampleLevel(readTexture, u_sampler, uv - sortDir * 0.01, 0.0).b;
        finalColor = vec4<f32>(r, finalColor.g, b, finalColor.a);
    }
    
    textureStore(writeTexture, coord, finalColor);
    textureStore(dataTextureA, coord, finalColor);
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
