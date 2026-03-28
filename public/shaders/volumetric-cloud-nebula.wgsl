// ═══════════════════════════════════════════════════════════════
//  Volumetric Cloud Nebula - Raymarched with Scientific Alpha
//  Category: generative
//  Features: raymarched, volumetric
//  
//  Scientific Implementation:
//  - 3D raymarching with optical depth accumulation
//  - Multiple scattering approximation (albedo-based)
//  - Beer-Lambert extinction for physical alpha
//  - Nebula coloring based on ionization energy levels
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Physical constants for nebula clouds
const SIGMA_T_NEBULA: f32 = 1.2;        // Nebula extinction
const SIGMA_S_NEBULA: f32 = 1.0;        // Scattering albedo ~0.83
const SIGMA_A_NEBULA: f32 = 0.2;        // Absorption (gas/dust)

// Hash function for noise
fn hash3(p: vec3<f32>) -> vec3<f32> {
    let q = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.6))
    );
    return fract(sin(q) * 43758.5453);
}

// 3D Value noise
fn noise3d(p: vec3<f32>) -> f32 {
    var i = floor(p);
    let f = fract(p);
    let f_smooth = f * f * (3.0 - 2.0 * f);
    
    let n = i.x + i.y * 157.0 + 113.0 * i.z;
    
    var result: f32 = 0.0;
    for (var z: i32 = 0; z < 2; z = z + 1) {
        for (var y: i32 = 0; y < 2; y = y + 1) {
            for (var x: i32 = 0; x < 2; x = x + 1) {
                let offset = vec3<f32>(f32(x), f32(y), f32(z));
                var h = hash3(i + offset);
                let w = abs(vec3<f32>(1.0) - offset - f);
                result = result + h.x * w.x * w.y * w.z;
            }
        }
    }
    return result;
}

// FBM (Fractal Brownian Motion) for clouds
fn fbmCloud(p: vec3<f32>) -> f32 {
    var value: f32 = 0.0;
    var amplitude: f32 = 0.5;
    var frequency: f32 = 1.0;
    
    for (var i: i32 = 0; i < 5; i = i + 1) {
        value = value + amplitude * noise3d(p * frequency);
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.0;
    }
    return value;
}

// Cloud density function with volumetric properties
fn cloudDensity(p: vec3<f32>, time: f32, densityScale: f32) -> f32 {
    let animP = p + vec3<f32>(
        time * 0.05,
        time * 0.02,
        time * 0.03
    );
    
    var density = fbmCloud(animP * 0.8);
    
    // Create cloud-like shapes
    density = density - 0.3;
    density = max(density, 0.0);
    density = density * densityScale;
    
    // Falloff at edges
    let dist = length(p);
    density = density * smoothstep(6.0, 2.0, dist);
    
    return density;
}

// Nebula color palette (ionized gas emission)
fn nebulaColor(t: f32, shift: f32) -> vec3<f32> {
    let adjustedT = t + shift;
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557);
    
    return a + b * cos(6.28318 * (c * adjustedT + d));
}

// Raymarch through clouds with volumetric integration
fn raymarchVolumetric(ro: vec3<f32>, rd: vec3<f32>, time: f32, densityScale: f32, colorShift: f32) -> vec4<f32> {
    var accumulatedColor = vec3<f32>(0.0);
    var totalOpticalDepth = 0.0;
    var transmittance = 1.0;
    
    let tMax = 15.0;
    let stepSize = 0.15;
    var t: f32 = 0.1;
    
    for (var i: i32 = 0; i < 60; i = i + 1) {
        if (t > tMax || transmittance < 0.01) {
            break;
        }
        
        var p = ro + rd * t;
        var density = cloudDensity(p, time, densityScale);
        
        if (density > 0.001) {
            // Calculate optical depth for this step
            let stepOpticalDepth = density * stepSize * SIGMA_T_NEBULA;
            totalOpticalDepth += stepOpticalDepth;
            
            // Transmittance through this step
            let stepTransmittance = exp(-stepOpticalDepth);
            
            // Nebula emission/absorption color
            let colorT = length(p) * 0.1 + density * 2.0;
            let cloudEmission = nebulaColor(colorT, colorShift);
            
            // Accumulate in-scattered light
            // L += T * emission * (1 - T_step)
            accumulatedColor += transmittance * cloudEmission * (1.0 - stepTransmittance) * SIGMA_S_NEBULA;
            
            // Update transmittance
            transmittance *= stepTransmittance;
        }
        
        // Adaptive step size
        t = t + stepSize * (1.0 + t * 0.1);
    }
    
    // Final alpha from total optical depth
    let alpha = 1.0 - exp(-totalOpticalDepth);
    
    return vec4<f32>(accumulatedColor, alpha);
}

// Background stars
fn starField(uv: vec2<f32>, time: f32) -> vec3<f32> {
    var h = hash3(vec3<f32>(uv * 200.0, 0.0));
    let star = step(0.997, h.x);
    let twinkle = 0.7 + 0.3 * sin(time * 3.0 + h.y * 10.0);
    return vec3<f32>(star * twinkle);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x * 0.3;
    
    // Parameters from sliders
    let densityScale = u.zoom_params.x * 0.5 + 0.5;
    let colorShift = u.zoom_params.y * 0.5;
    let camDist = u.zoom_params.z * 3.0 + 3.0;
    
    // Normalized UV for raymarching
    let aspect = resolution.x / resolution.y;
    let st = (uv - 0.5) * vec2<f32>(aspect, 1.0);
    
    // Camera setup
    let ro = vec3<f32>(
        camDist * sin(time * 0.2),
        1.0 + sin(time * 0.15) * 0.5,
        camDist * cos(time * 0.2)
    );
    
    let lookAt = vec3<f32>(0.0, 0.0, 0.0);
    let forward = normalize(lookAt - ro);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), forward));
    let up = cross(forward, right);
    
    let rd = normalize(st.x * right + st.y * up + 1.5 * forward);
    
    // Raymarch clouds with volumetric integration
    let cloudResult = raymarchVolumetric(ro, rd, time, densityScale, colorShift);
    
    // Background gradient (deep space)
    let bgGradient = mix(
        vec3<f32>(0.02, 0.02, 0.08),
        vec3<f32>(0.05, 0.03, 0.1),
        uv.y * 0.5 + 0.5
    );
    
    // Add stars
    let stars = starField(st + time * 0.01, time);
    let bg = bgGradient + stars * 0.8;
    
    // Volumetric composition:
    // Final = cloud_emission + background * transmittance
    let transmittance = 1.0 - cloudResult.a;
    var finalCol = cloudResult.rgb + bg * transmittance;
    
    // Tone mapping
    finalCol = finalCol / (1.0 + finalCol);
    finalCol = pow(finalCol, vec3<f32>(0.4545));
    
    // Write output with volumetric alpha
    // RGB: Accumulated in-scattered light + transmitted background
    // A: Volumetric opacity from optical depth
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalCol, cloudResult.a));
    
    // Write depth (simplified for generative shader)
    // Store optical depth in depth for post-processing effects
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.5, cloudResult.a, 0.0, cloudResult.a));
}
