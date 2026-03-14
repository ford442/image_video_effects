// ═══════════════════════════════════════════════════════════════════════════════
//  atmos_volumetric_fog.wgsl - Volumetric Fog with God Rays
//  
//  Agent: Visualist + Algorithmist
//  Techniques:
//    - Raymarch through volumetric medium
//    - Height-based fog density
//    - Light scattering (Mie + Rayleigh)
//    - Temporal accumulation for smoothness
//    - Mouse-controlled light source
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
fn hash3(p: vec3<f32>) -> f32 {
    let q = fract(p * 0.1031);
    return fract((q.x + q.y) * q.z);
}

// Noise
fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    let n = i.x + i.y * 57.0 + i.z * 113.0;
    return mix(
        mix(
            mix(hash3(i), hash3(i + vec3<f32>(1, 0, 0)), f.x),
            mix(hash3(i + vec3<f32>(0, 1, 0)), hash3(i + vec3<f32>(1, 1, 0)), f.x),
            f.y
        ),
        mix(
            mix(hash3(i + vec3<f32>(0, 0, 1)), hash3(i + vec3<f32>(1, 0, 1)), f.x),
            mix(hash3(i + vec3<f32>(0, 1, 1)), hash3(i + vec3<f32>(1, 1, 1)), f.x),
            f.y
        ),
        f.z
    );
}

// FBM for fog density variation
fn fbm(p: vec3<f32>) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    
    for (var i: i32 = 0; i < 4; i = i + 1) {
        value += amplitude * noise(p * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

// Fog density at point
fn fogDensity(p: vec3<f32>, time: f32) -> f32 {
    // Height falloff
    let heightFactor = exp(-p.y * 2.0);
    
    // Turbulence
    let turb = fbm(p * 2.0 + vec3<f32>(0.0, time * 0.1, 0.0));
    
    return heightFactor * (0.5 + turb * 0.5);
}

// Phase function (Henyey-Greenstein approximation)
fn phaseFunction(cosTheta: f32, g: f32) -> f32 {
    let g2 = g * g;
    return (1.0 - g2) / pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5);
}

// Mie scattering (large particles)
fn mieScattering(cosTheta: f32) -> f32 {
    return phaseFunction(cosTheta, 0.76);
}

// Rayleigh scattering (small particles)
fn rayleighScattering(cosTheta: f32) -> f32 {
    return (3.0 / (16.0 * PI)) * (1.0 + cosTheta * cosTheta);
}

// Ray-sphere intersection
fn raySphereIntersect(ro: vec3<f32>, rd: vec3<f32>, r: f32) -> vec2<f32> {
    let b = dot(ro, rd);
    let c = dot(ro, ro) - r * r;
    let h = b * b - c;
    if (h < 0.0) {
        return vec2<f32>(-1.0, -1.0);
    }
    let h2 = sqrt(h);
    return vec2<f32>(-b - h2, -b + h2);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Parameters
    let fogDensityScale = 0.5 + u.zoom_params.x * 2.0;   // 0.5-2.5
    let lightIntensity = 0.5 + u.zoom_params.y * 1.5;    // 0.5-2.0
    let scattering = u.zoom_params.z;                     // 0-1 (Mie vs Rayleigh)
    let godRayStrength = u.zoom_params.w;                 // 0-1
    
    // Mouse-controlled light position
    let mousePos = u.zoom_config.yz;
    let lightPos = vec3<f32>(mousePos.x, 0.8, mousePos.y);
    
    // Audio reactivity
    let audioPulse = u.zoom_config.w;
    
    // Camera ray
    let ro = vec3<f32>(0.5, 0.5, -1.0);
    let rd = normalize(vec3<f32>(uv.x - 0.5, uv.y - 0.5, 1.0));
    
    // Ray marching setup
    let steps = 32;
    let maxDist = 3.0;
    let stepSize = maxDist / f32(steps);
    
    var transmittance = 1.0;
    var scatteredLight = vec3<f32>(0.0);
    
    // Light color (warm sunlight)
    let lightColor = vec3<f32>(1.0, 0.95, 0.8) * lightIntensity * (1.0 + audioPulse);
    
    // Ray march through fog
    for (var i: i32 = 0; i < steps; i = i + 1) {
        let t = f32(i) * stepSize;
        let p = ro + rd * t;
        
        // Sample fog density
        let density = fogDensity(p, time) * fogDensityScale * stepSize;
        
        if (density > 0.001) {
            // Attenuation
            let attenuation = exp(-density);
            transmittance *= attenuation;
            
            // Light contribution
            let toLight = lightPos - p;
            let distToLight = length(toLight);
            let lightDir = toLight / distToLight;
            
            // Check light visibility (simplified shadow)
            let cosTheta = dot(rd, lightDir);
            let phase = mix(rayleighScattering(cosTheta), mieScattering(cosTheta), scattering);
            
            // God ray effect (beam intensity)
            let beamAlignment = pow(max(dot(rd, normalize(lightPos - ro)), 0.0), 4.0);
            let godRays = 1.0 + beamAlignment * godRayStrength * 2.0;
            
            // Add scattered light
            let lightContrib = lightColor * density * phase * godRays;
            scatteredLight += transmittance * lightContrib;
        }
    }
    
    // Sample background through fog
    let bgColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    
    // Combine
    var color = bgColor * transmittance + scatteredLight;
    
    // Add light source glow
    let lightScreen = lightPos.xy;
    let lightDist = length(uv - lightScreen);
    let lightGlow = exp(-lightDist * 20.0) * lightIntensity * (1.0 + audioPulse * 2.0);
    color += lightColor * lightGlow;
    
    // Tone mapping
    color = color / (1.0 + color * 0.5);
    
    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.3;
    color *= vignette;
    
    textureStore(writeTexture, coord, vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, coord, vec4<f32>(1.0 - transmittance, 0.0, 0.0, 1.0));
    
    // Store for temporal accumulation
    textureStore(dataTextureA, coord, vec4<f32>(color, transmittance));
}
