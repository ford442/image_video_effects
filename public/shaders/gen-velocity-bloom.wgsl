// ═══════════════════════════════════════════════════════════════════
//  Velocity Bloom - Velocity-sensitive bloom that intensifies on motion
//  Category: lighting-effects
//  Features: temporal, velocity-based, multi-octave bloom
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

// Calculate velocity magnitude
fn calculateVelocity(uv: vec2<f32>, pixel: vec2<f32>) -> f32 {
    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let previous = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    
    // Frame difference
    let diff = current - previous;
    let lumaDiff = length(diff);
    
    // Gradient magnitude for edge detection
    let right = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(pixel.x, 0.0), 0.0).rgb;
    let left = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(pixel.x, 0.0), 0.0).rgb;
    let up = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, pixel.y), 0.0).rgb;
    let down = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, pixel.y), 0.0).rgb;
    
    let gradient = length(right - left) + length(up - down);
    
    // Combined velocity estimate
    return lumaDiff + gradient * 0.5;
}

// Multi-octave bloom sampling
fn multiOctaveBloom(uv: vec2<f32>, baseRadius: f32, velocity: f32) -> vec3<f32> {
    var bloom = vec3<f32>(0.0);
    var totalWeight = 0.0;
    
    // Multiple octaves with different radii
    let octaves = 4;
    for (var o: i32 = 0; o < octaves; o++) {
        let fo = f32(o);
        let radius = baseRadius * (1.0 + fo * 0.5) * (1.0 + velocity);
        let weight = 1.0 / (1.0 + fo * 0.5);
        
        // Sample in star pattern for performance
        let directions = 8;
        for (var i: i32 = 0; i < directions; i++) {
            let angle = f32(i) * 6.28318 / f32(directions);
            let offset = vec2<f32>(cos(angle), sin(angle)) * radius;
            bloom += textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb * weight;
        }
        
        totalWeight += weight * f32(directions);
    }
    
    return bloom / totalWeight;
}

// Anamorphic bloom (stretched horizontally)
fn anamorphicBloom(uv: vec2<f32>, radius: f32, velocity: f32) -> vec3<f32> {
    var bloom = vec3<f32>(0.0);
    let samples = 16;
    let stretch = 1.0 + velocity * 2.0;
    
    for (var i: i32 = 0; i < samples; i++) {
        let t = (f32(i) / f32(samples - 1) - 0.5) * 2.0;
        let offset = vec2<f32>(t * radius * stretch, 0.0);
        bloom += textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb;
    }
    
    return bloom / f32(samples);
}

// Velocity-based color tint
fn velocityColor(velocity: f32) -> vec3<f32> {
    // White core, colored aura based on velocity
    if (velocity < 0.3) {
        return mix(vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(0.8, 0.9, 1.0), velocity / 0.3);
    } else if (velocity < 0.6) {
        return mix(vec3<f32>(0.8, 0.9, 1.0), vec3<f32>(0.4, 0.7, 1.0), (velocity - 0.3) / 0.3);
    } else {
        return mix(vec3<f32>(0.4, 0.7, 1.0), vec3<f32>(0.9, 0.4, 0.8), (velocity - 0.6) / 0.4);
    }
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let pixel = 1.0 / resolution;
    let t = u.config.x;
    
    // Parameters - safe randomization
    let threshold = mix(0.0, 0.3, u.zoom_params.x);
    let bloomIntensity = mix(0.3, 2.0, u.zoom_params.y);
    let bloomRadius = mix(0.01, 0.05, u.zoom_params.z);
    let decay = mix(0.7, 0.99, u.zoom_params.w);
    
    // Get base color
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let baseLuma = dot(baseColor, vec3<f32>(0.299, 0.587, 0.114));
    
    // Calculate velocity
    let velocity = calculateVelocity(uv, pixel);
    
    // Determine bloom amount based on velocity
    let velocityMask = smoothstep(threshold, threshold + 0.2, velocity);
    
    // Multi-octave bloom
    let bloom = multiOctaveBloom(uv, bloomRadius, velocity);
    let bloomLuma = dot(bloom, vec3<f32>(0.299, 0.587, 0.114));
    
    // Anamorphic bloom for high velocity areas
    let anamorphic = anamorphicBloom(uv, bloomRadius * 2.0, velocity);
    
    // Combine blooms
    var finalBloom = mix(bloom, anamorphic, velocityMask * 0.5);
    
    // Apply velocity-based color tint to bloom
    let tint = velocityColor(velocity);
    finalBloom = finalBloom * tint;
    
    // Previous bloom accumulation for decay
    let prevBloom = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0).rgb;
    let decayedBloom = prevBloom * decay;
    
    // Accumulate bloom with decay
    let accumulatedBloom = max(finalBloom * bloomIntensity, decayedBloom * 0.9);
    
    // Composite: base + bloom
    // Use screen blend for light areas, add for motion areas
    let screenBlend = 1.0 - (1.0 - baseColor) * (1.0 - accumulatedBloom);
    let addBlend = baseColor + accumulatedBloom * velocityMask;
    
    var finalColor = mix(screenBlend, addBlend, velocityMask * 0.5);
    
    // Boost brightness in high-velocity areas
    finalColor = finalColor * (1.0 + velocity * 0.3);
    
    // Store accumulated bloom for next frame
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(accumulatedBloom, 1.0));
    
    // Alpha based on effect intensity
    let alpha = mix(0.8, 1.0, velocityMask);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    
    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
