// ═══════════════════════════════════════════════════════════════════════════════
//  gen_quantum_foam.wgsl - Quantum Foam Entanglement Shader
//  
//  Agent: Algorithmist + Visualist
//  Techniques:
//    - Quantum fluctuation simulation (virtual particle pairs)
//    - Entanglement visualization (correlated particle networks)
//    - HDR volumetric glow with chromatic dispersion
//    - Temporal coherence for smooth evolution
//  
//  Target: 4.6★ rating
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
const PHI: f32 = 1.61803398875;

// Hash functions
fn hash3(p: vec3<f32>) -> f32 {
    var q = fract(p * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// Smooth noise
fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    var f = fract(p);
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

// FBM for quantum foam texture
fn fbm(p: vec3<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value += amplitude * noise(p * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

// Quantum foam - particle pair fluctuations
fn quantumFoam(uv: vec2<f32>, time: f32, scale: f32) -> vec3<f32> {
    let p = vec3<f32>(uv * scale, time * 0.5);
    
    // Virtual particle pairs
    let foam = fbm(p, 4);
    let foam2 = fbm(p * 2.0 + vec3<f32>(100.0), 3);
    
    // Entanglement correlations
    let correlation = sin(foam * PI * 4.0 + time) * cos(foam2 * PI * 3.0);
    
    // Energy density (vacuum fluctuations)
    let energy = pow(abs(correlation), 0.5) * 2.0;
    
    // Chromatic dispersion based on energy
    let r = energy * (1.0 + 0.3 * sin(time * 2.0));
    let g = energy * (0.8 + 0.2 * cos(time * 1.5));
    let b = energy * (1.2 + 0.4 * sin(time * 2.5 + 1.0));
    
    return vec3<f32>(r, g, b);
}

// Entanglement web - connecting correlated regions
fn entanglementWeb(uv: vec2<f32>, time: f32, density: f32) -> f32 {
    var web = 0.0;
    let numConnections = i32(density * 20.0);
    
    for (var i: i32 = 0; i < numConnections; i = i + 1) {
        let fi = f32(i);
        let seed = vec2<f32>(fi * 1.618, fi * 2.718);
        let p1 = vec2<f32>(
            hash2(seed) + sin(time * 0.3 + fi) * 0.2,
            hash2(seed + 10.0) + cos(time * 0.4 + fi) * 0.2
        );
        let p2 = vec2<f32>(
            hash2(seed + 20.0) + sin(time * 0.35 + fi + PI) * 0.2,
            hash2(seed + 30.0) + cos(time * 0.45 + fi + PI) * 0.2
        );
        
        // Distance to line segment
        let pa = uv - p1;
        let ba = p2 - p1;
        let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
        let dist = length(pa - ba * h);
        
        // Entanglement strength (thicker where correlated)
        let strength = hash2(seed + 50.0);
        web += smoothstep(0.01 + strength * 0.02, 0.0, dist) * strength;
    }
    
    return web;
}

// Tone mapping
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
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
    let foamScale = 4.0 + u.zoom_params.x * 8.0;      // 4-12
    let webDensity = u.zoom_params.y;                  // 0-1
    let glowIntensity = 0.5 + u.zoom_params.z;         // 0.5-1.5
    let evolutionSpeed = 0.3 + u.zoom_params.w * 0.7;  // 0.3-1.0
    
    // Audio reactivity (from mouse Y as proxy)
    let audioPulse = u.zoom_config.z;
    
    // Quantum foam base
    var color = quantumFoam(uv, time * evolutionSpeed, foamScale);
    
    // Add entanglement web
    let web = entanglementWeb(uv, time * evolutionSpeed * 0.5, webDensity);
    color += vec3<f32>(web * 0.8, web * 0.9, web * 1.2);
    
    // Audio-reactive burst
    color *= 1.0 + audioPulse * 2.0;
    
    // Volumetric glow simulation (blur approximation)
    let glowRadius = 2;
    var glowAccum = vec3<f32>(0.0);
    for (var gx: i32 = -glowRadius; gx <= glowRadius; gx = gx + 1) {
        for (var gy: i32 = -glowRadius; gy <= glowRadius; gy = gy + 1) {
            let sampleUV = uv + vec2<f32>(f32(gx), f32(gy)) / resolution * 4.0;
            let sampleFoam = quantumFoam(sampleUV, time * evolutionSpeed, foamScale);
            glowAccum += sampleFoam;
        }
    }
    glowAccum /= f32((glowRadius * 2 + 1) * (glowRadius * 2 + 1));
    color += glowAccum * glowIntensity * 0.5;
    
    // HDR tone mapping
    color = acesToneMap(color * 0.8);
    
    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.3;
    color *= vignette;
    
    // Output
    textureStore(writeTexture, coord, vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, coord, vec4<f32>(0.0, 0.0, 0.0, 1.0));
    
    // Store foam state for temporal continuity
    textureStore(dataTextureA, coord, vec4<f32>(color * 0.5 + 0.5, 1.0));
}
