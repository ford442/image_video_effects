// ═══════════════════════════════════════════════════════════════════
//  Temporal Motion Smear - Motion-aware temporal smearing
//  Category: image
//  Features: temporal, motion-aware, frame differencing
//  Created: 2026-03-22
//  By: Agent 4A
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

// Detect motion by comparing current and previous frame
fn detectMotion(uv: vec2<f32>, pixel: vec2<f32>) -> vec2<f32> {
    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let previous = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    
    // Luminance of each frame
    let currLuma = dot(current, vec3<f32>(0.299, 0.587, 0.114));
    let prevLuma = dot(previous, vec3<f32>(0.299, 0.587, 0.114));
    
    // Calculate motion magnitude
    let diff = abs(currLuma - prevLuma);
    
    // Estimate motion direction from gradient
    let right = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(pixel.x, 0.0), 0.0).rgb;
    let left = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(pixel.x, 0.0), 0.0).rgb;
    let up = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0, pixel.y), 0.0).rgb;
    let down = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(0.0, pixel.y), 0.0).rgb;
    
    let dx = dot(right - left, vec3<f32>(0.299, 0.587, 0.114)) * 0.5;
    let dy = dot(up - down, vec3<f32>(0.299, 0.587, 0.114)) * 0.5;
    
    // Motion vector (approximate)
    return vec2<f32>(dx, dy) * diff * 10.0;
}

// Apply directional blur along motion vector
fn directionalBlur(uv: vec2<f32>, dir: vec2<f32>, samples: i32, radius: f32) -> vec3<f32> {
    var result = vec3<f32>(0.0);
    let step = dir * radius / f32(samples);
    
    for (var i: i32 = 0; i < samples; i++) {
        let offset = step * f32(i);
        result += textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb;
    }
    
    return result / f32(samples);
}

// Hue shift for trail coloring
fn hueShift(color: vec3<f32>, shift: f32) -> vec3<f32> {
    let k = vec3<f32>(0.57735, 0.57735, 0.57735);
    let cosAngle = cos(shift);
    return vec3<f32>(color * cosAngle + cross(k, color) * sin(shift) + k * dot(k, color) * (1.0 - cosAngle));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let pixel = 1.0 / resolution;
    
    // Parameters - safe randomization
    let persistence = mix(0.7, 0.99, u.zoom_params.x);
    let sensitivity = mix(0.5, 5.0, u.zoom_params.y);
    let directionality = u.zoom_params.z; // 0=omni, 1=direction-aware
    let intensityBoost = mix(0.5, 2.0, u.zoom_params.w);
    
    // Get current frame
    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let currentLuma = dot(current.rgb, vec3<f32>(0.299, 0.587, 0.114));
    
    // Get previous trail buffer
    let prevTrail = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0);
    
    // Detect motion
    let motion = detectMotion(uv, pixel) * sensitivity;
    let motionStrength = length(motion);
    
    // Calculate decay based on motion
    let decay = mix(persistence * 0.9, persistence, smoothstep(0.1, 0.5, motionStrength));
    
    // Create smeared color
    var smearedColor = current.rgb;
    var alpha = current.a;
    
    if (motionStrength > 0.01) {
        // Direction-aware blur
        let blurDir = normalize(motion + vec2<f32>(0.001));
        let blurRadius = motionStrength * 0.05 * directionality;
        
        // Apply directional blur
        let blurred = directionalBlur(uv, blurDir, 8, blurRadius);
        
        // Color based on velocity - warm for fast, cool for slow
        let velocityColor = mix(
            vec3<f32>(0.3, 0.5, 0.9), // Cool - slow
            vec3<f32>(0.9, 0.6, 0.2), // Warm - fast
            smoothstep(0.0, 1.0, motionStrength)
        );
        
        // Mix blurred color with velocity tint
        smearedColor = mix(blurred, blurred * velocityColor * 1.5, 0.4);
        
        // Increase alpha where motion is strong
        alpha = mix(current.a, 1.0, min(motionStrength * 0.5, 0.5));
    }
    
    // Accumulate trails with decay
    let trailContribution = prevTrail.rgb * decay;
    
    // Combine: current smeared + decayed trail
    // Use max for light-trail effect, or mix for ghosting
    var finalColor = max(smearedColor * intensityBoost, trailContribution * 0.95);
    
    // Add subtle color shift based on trail age
    let trailAge = length(prevTrail.rgb);
    if (trailAge > 0.1) {
        finalColor = hueShift(finalColor, trailAge * 0.1);
    }
    
    // Fade to black if very little motion
    if (motionStrength < 0.001 && length(trailContribution) < 0.01) {
        finalColor = finalColor * 0.99;
    }
    
    // Vignette for alpha
    let vignette = 1.0 - length(uv - 0.5) * 0.3;
    alpha = alpha * vignette;
    
    // Store accumulated trail
    let trailOutput = vec4<f32>(finalColor, alpha);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), trailOutput);
    
    // Write output
    textureStore(writeTexture, vec2<i32>(global_id.xy), trailOutput);
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
