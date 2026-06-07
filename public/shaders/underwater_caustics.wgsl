// ═══════════════════════════════════════════════════════════════════════════════
//  underwater_caustics.wgsl - Realistic Water Caustics with RGBA Depth
//  
//  RGBA Focus: Alpha = caustic intensity for light shaft blending
//  Techniques:
//    - Wave surface simulation (Gerstner waves)
//    - Caustic pattern from refracted light
//    - God rays through water volume
//    - Mouse-controlled light source
//    - Audio-reactive wave intensity
//  
//  Target: 4.7★ rating
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

const PI: f32 = 3.14159265359;

// Hash
fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// Gerstner wave
fn gerstnerWave(p: vec2<f32>, time: f32, direction: vec2<f32>, wavelength: f32, amplitude: f32) -> f32 {
    let k = 2.0 * PI / wavelength;
    let c = sqrt(9.8 / k);
    let phase = k * (dot(p, direction) - c * time);
    return amplitude * sin(phase);
}

// Wave surface height
fn waveHeight(p: vec2<f32>, time: f32, audioPulse: f32) -> f32 {
    var height = 0.0;
    
    // Multiple wave directions
    height += gerstnerWave(p, time, vec2<f32>(1.0, 0.0), 0.5, 0.05);
    height += gerstnerWave(p, time * 0.8, vec2<f32>(0.5, 0.866), 0.3, 0.03);
    height += gerstnerWave(p, time * 1.2, vec2<f32>(-0.3, 0.95), 0.2, 0.02);
    height += gerstnerWave(p, time * 0.6, vec2<f32>(0.8, 0.6), 0.15, 0.015);
    
    // Audio adds turbulence
    height += audioPulse * gerstnerWave(p, time * 3.0, vec2<f32>(0.0, 1.0), 0.1, 0.02);
    
    return height;
}

// Wave normal from finite differences
fn waveNormal(p: vec2<f32>, time: f32, audioPulse: f32) -> vec3<f32> {
    let eps = 0.01;
    let h = waveHeight(p, time, audioPulse);
    let hx = waveHeight(p + vec2<f32>(eps, 0.0), time, audioPulse);
    let hy = waveHeight(p + vec2<f32>(0.0, eps), time, audioPulse);
    
    return normalize(vec3<f32>(h - hx, h - hy, eps));
}

// Caustic pattern from wave slopes
fn causticPattern(uv: vec2<f32>, time: f32, audioPulse: f32) -> f32 {
    let normal = waveNormal(uv * 5.0, time, audioPulse);
    
    // Caustics form where surface focuses light
    let slope = length(normal.xy);
    let focusing = 1.0 / (1.0 + slope * 10.0);
    
    // Add temporal variation
    let shimmer = sin(time * 3.0 + slope * 20.0) * 0.5 + 0.5;
    
    return pow(focusing * shimmer, 2.0) * 3.0;
}

// God ray through water
fn godRay(uv: vec2<f32>, lightPos: vec2<f32>, time: f32) -> f32 {
    let toLight = lightPos - uv;
    let dist = length(toLight);
    let dir = normalize(toLight);
    
    // Volumetric scattering
    var intensity = 0.0;
    let steps = 20;
    
    for (var i: i32 = 0; i < steps; i = i + 1) {
        let t = f32(i) / f32(steps);
        let p = uv + dir * dist * t;
        
        // Dappled light effect
        let dapple = sin(p.x * 50.0 + time) * sin(p.y * 50.0 + time * 1.3);
        intensity += max(dapple, 0.0) * (1.0 - t) / f32(steps);
    }
    
    return intensity * 2.0;
}

// Underwater color grading
fn underwaterColor(depth: f32, caustics: f32) -> vec3<f32> {
    // Deep blue-green water
    let deepColor = vec3<f32>(0.0, 0.15, 0.25);
    let shallowColor = vec3<f32>(0.0, 0.4, 0.5);
    let sunColor = vec3<f32>(0.9, 0.95, 0.7);
    
    let baseColor = mix(deepColor, shallowColor, exp(-depth * 2.0));
    return baseColor + sunColor * caustics;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Parameters
    let waveScale = 3.0 + u.zoom_params.x * 7.0; // 3-10
    let causticIntensity = u.zoom_params.y; // 0-1
    let depth = u.zoom_params.z * 3.0; // 0-3
    let clarity = 0.3 + u.zoom_params.w * 0.7; // 0.3-1.0
    
    let mousePos = u.zoom_config.yz;
    let audioPulse = u.zoom_config.w;
    
    // Sample caustics
    let caustics = causticPattern(uv * waveScale, time, audioPulse);
    
    // God rays from mouse position
    let rays = godRay(uv, mousePos, time);
    
    // Combine lighting
    let totalLight = caustics * causticIntensity + rays * 0.3;
    
    // Underwater color
    var color = underwaterColor(depth, totalLight);
    
    // Add specular from surface
    let surfaceNormal = waveNormal(uv * waveScale, time, audioPulse);
    let lightDir = normalize(vec3<f32>(mousePos.x - 0.5, mousePos.y - 0.5, 1.0));
    let specAngle = max(dot(surfaceNormal, lightDir), 0.0);
    let specular = pow(specAngle, 64.0) * (1.0 + audioPulse);
    color += vec3<f32>(1.0, 0.95, 0.8) * specular * 0.5;
    
    // Apply clarity (murky vs clear water)
    color = mix(vec3<f32>(0.05, 0.1, 0.15), color, clarity);
    
    // Alpha based on caustic intensity
    let finalAlpha = min(caustics * causticIntensity * 0.8 + 0.2, 1.0);
    
    // Tone mapping
    color = color / (1.0 + color * 0.3);
    
    // Vignette (underwater darkness)
    let vignette = 1.0 - length(uv - 0.5) * 0.5;
    
    textureStore(writeTexture, coord, vec4<f32>(color * vignette, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(finalAlpha, 0.0, 0.0, 1.0));
    
    textureStore(dataTextureA, coord, vec4<f32>(color, finalAlpha));
}
