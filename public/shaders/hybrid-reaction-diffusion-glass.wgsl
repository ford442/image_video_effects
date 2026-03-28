// ═══════════════════════════════════════════════════════════════════
//  Hybrid Reaction-Diffusion Glass
//  Category: simulation
//  Features: hybrid, reaction-diffusion, glass-distortion, depth-aware
//  Chunks From: reaction-diffusion.wgsl (Gray-Scott), frosted-glass-lens pattern,
//               depth-aware sampling
//  Created: 2026-03-22
//  By: Agent 2A - Shader Surgeon
// ═══════════════════════════════════════════════════════════════════
//  Concept: Turing patterns (reaction-diffusion) refracted through
//           depth-aware glass distortion
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

// ═══ CHUNK 1: hash12 (from gen_grid.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK 2: fbm2 (from gen_grid.wgsl) ═══
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let a = hash12(i + vec2<f32>(0.0, 0.0));
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value = value + amplitude * valueNoise(p * frequency);
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.0;
    }
    return value;
}

// ═══ CHUNK 3: palette (from gen-xeno-botanical-synth-flora.wgsl) ═══
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

// ═══ CHUNK 4: fresnelSchlick (from crystal-facets.wgsl) ═══
fn fresnelSchlick(cosTheta: f32, F0: f32) -> f32 {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// ═══ HYBRID LOGIC: Reaction-Diffusion + Glass ═══
fn laplacian(coord: vec2<i32>) -> f32 {
    var sum: f32 = 0.0;
    let kernel = array<f32, 9>(0.05, 0.2, 0.05, 0.2, -1.0, 0.2, 0.05, 0.2, 0.05);
    var k: i32 = 0;
    for (var j: i32 = -1; j <= 1; j++) {
        for (var i: i32 = -1; i <= 1; i++) {
            let sample = textureLoad(dataTextureC, coord + vec2<i32>(i, j), 0).r;
            sum += sample * kernel[k];
            k++;
        }
    }
    return sum;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let id = vec2<i32>(global_id.xy);
    
    // Parameters
    let feedRate = mix(0.01, 0.1, u.zoom_params.x);        // x: Feed rate (pattern density)
    let killRate = mix(0.03, 0.07, u.zoom_params.y);       // y: Kill rate (pattern stability)
    let glassDistortion = mix(0.02, 0.1, u.zoom_params.z); // z: Glass refraction
    let depthInfluence = u.zoom_params.w;                  // w: Depth effect
    
    // Gray-Scott reaction-diffusion
    let cur = textureLoad(dataTextureC, id, 0).r;
    let lap = laplacian(id);
    
    // Reaction terms
    let reaction = cur * cur * cur;
    let feed = feedRate * (1.0 - cur);
    let kill = (killRate + feedRate) * cur;
    
    // Update with mouse interaction
    let mouse = u.zoom_config.yz;
    let distToMouse = distance(uv, mouse);
    var newChem = cur + lap * 0.2 - reaction + feed - kill;
    
    // Inject chemical at mouse
    if (distToMouse < 0.05) {
        newChem += 0.1 * (1.0 - distToMouse / 0.05);
    }
    
    newChem = clamp(newChem, 0.0, 1.0);
    
    // Store RD state for next frame
    textureStore(dataTextureA, id, vec4<f32>(newChem, 0.0, 0.0, 1.0));
    
    // Glass distortion based on RD pattern
    let patternGradient = vec2<f32>(
        textureLoad(dataTextureC, id + vec2<i32>(1, 0), 0).r - 
        textureLoad(dataTextureC, id - vec2<i32>(1, 0), 0).r,
        textureLoad(dataTextureC, id + vec2<i32>(0, 1), 0).r - 
        textureLoad(dataTextureC, id - vec2<i32>(0, 1), 0).r
    );
    
    // Depth-aware distortion
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let distortionStrength = glassDistortion * (1.0 + depth * depthInfluence);
    
    // Refract UV based on RD pattern
    let refractUV = uv + patternGradient * distortionStrength;
    
    // Sample background through glass
    let bgColor = textureSampleLevel(readTexture, u_sampler, refractUV, 0.0).rgb;
    
    // Color the RD pattern
    let rdColor = palette(newChem + time * 0.05,
        vec3<f32>(0.5),
        vec3<f32>(0.5),
        vec3<f32>(1.0, 0.7, 0.4),
        vec3<f32>(0.0, 0.33, 0.67)
    );
    
    // Combine glass refraction with RD pattern
    var color = mix(bgColor, rdColor, newChem * 0.7);
    
    // Fresnel effect on pattern edges
    let edge = length(patternGradient);
    let fresnel = fresnelSchlick(1.0 - edge * 5.0, 0.1);
    color += vec3<f32>(0.9, 0.95, 1.0) * fresnel * 0.3;
    
    // Glass specular highlights
    let specular = pow(fresnel, 4.0) * 0.5;
    color += vec3<f32>(specular);
    
    // Alpha based on pattern intensity and depth
    let alpha = mix(0.6, 0.95, newChem + fresnel * 0.5);
    
    textureStore(writeTexture, id, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, id, vec4<f32>(depth * (1.0 - newChem * 0.3), 0.0, 0.0, 0.0));
}
