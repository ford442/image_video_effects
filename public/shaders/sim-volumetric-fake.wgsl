// ═══════════════════════════════════════════════════════════════════
//  Sim: Volumetric Fake (Fast God Rays)
//  Category: lighting-effects
//  Features: simulation, fake-volumetrics, radial-blur, god-rays
//  Complexity: Medium
//  Created: 2026-03-22
//  By: Agent 3B - Advanced Hybrid Creator
// ═══════════════════════════════════════════════════════════════════
//  Approximate god rays without raymarching
//  Radial blur from light source, multiply by depth density, noise for dust
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
    
    let uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;
    
    // Parameters
    let lightIntensity = mix(0.5, 2.0, u.zoom_params.x); // x: Light intensity
    let dustDensity = mix(0.0, 1.0, u.zoom_params.y);    // y: Dust density
    let scattering = mix(0.3, 1.5, u.zoom_params.z);     // z: Scattering amount
    let noiseSpeed = mix(0.1, 1.0, u.zoom_params.w);     // w: Noise speed
    
    // Light source position (animated)
    let lightPos = vec2<f32>(
        0.5 + cos(time * 0.2) * 0.3,
        0.2 + sin(time * 0.15) * 0.1
    );
    
    // Vector from light to pixel
    let toLight = lightPos - uv;
    let distToLight = length(toLight);
    let dirToLight = normalize(toLight);
    
    // Sample depth for occlusion
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // Radial blur toward light source
    var volumetric = vec3<f32>(0.0);
    let samples = i32(16.0 + dustDensity * 16.0);
    var occlusion = 0.0;
    
    for (var i = 0; i < 32; i++) {
        if (i >= samples) { break; }
        let t = f32(i) / f32(samples);
        let samplePos = uv + dirToLight * t * distToLight;
        
        if (samplePos.x < 0.0 || samplePos.x > 1.0 || samplePos.y < 0.0 || samplePos.y > 1.0) {
            continue;
        }
        
        // Sample scene color for occlusion
        let sampleColor = textureSampleLevel(readTexture, u_sampler, samplePos, 0.0).rgb;
        let sampleDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, samplePos, 0.0).r;
        let luma = dot(sampleColor, vec3<f32>(0.299, 0.587, 0.114));
        
        // Accumulate occlusion
        occlusion += luma * (1.0 - t);
        
        // Add light contribution
        let attenuation = 1.0 - t;
        volumetric += vec3<f32>(1.0) * attenuation * attenuation;
    }
    
    volumetric /= f32(samples);
    occlusion = clamp(occlusion / f32(samples), 0.0, 1.0);
    
    // Dust particles
    let dustNoise = noise(uv * 20.0 + time * noiseSpeed) * noise(uv * 15.0 - time * noiseSpeed * 0.5);
    let dust = pow(dustNoise, 3.0) * dustDensity;
    
    // Combine
    let density = 0.3 * scattering;
    var lightRays = volumetric * (1.0 - occlusion) * density;
    lightRays *= lightIntensity;
    
    // Add dust scattering
    lightRays += vec3<f32>(dust * lightIntensity * 0.5);
    
    // Sun color
    let sunColor = vec3<f32>(1.0, 0.95, 0.8);
    lightRays *= sunColor;
    
    // Blend with base image
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    
    // Additive blending for light rays
    var color = baseColor + lightRays;
    
    // Boost in light direction
    let lightDir = normalize(vec2<f32>(0.5) - lightPos);
    let viewDir = normalize(uv - lightPos);
    let alignment = max(0.0, dot(viewDir, lightDir));
    color += sunColor * alignment * alignment * lightIntensity * 0.1;
    
    // Distance falloff
    let falloff = 1.0 / (1.0 + distToLight * distToLight * 2.0);
    color = mix(baseColor, color, falloff);
    
    textureStore(writeTexture, gid.xy, vec4<f32>(color, 0.95));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
