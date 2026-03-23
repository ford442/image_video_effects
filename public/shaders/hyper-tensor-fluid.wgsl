// ═══════════════════════════════════════════════════════════════════
//  Hyper Tensor Fluid
//  Category: simulation
//  Features: advanced-hybrid, tensor-field, navier-stokes, depth-aware, fbm
//  Complexity: Very High
//  Chunks From: tensor-flow-sculpting, navier-stokes-dye, gen_grid
//  Created: 2026-03-22
//  By: Agent 3B - Advanced Hybrid Creator
// ═══════════════════════════════════════════════════════════════════
//  Fluid flows according to image structure via tensor eigendecomposition
//  Edges create barriers, smooth areas allow flow
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

// ═══ CHUNK: hash12 (from gen_grid.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: fbm2 (from gen_grid.wgsl) ═══
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

// ═══ TENSOR FIELD CALCULATION ═══
fn calculateStructureTensor(uv: vec2<f32>, pixel: vec2<f32>) -> mat2x2<f32> {
    // Sample image luminance for structure detection
    let l = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let lum = dot(l, vec3<f32>(0.299, 0.587, 0.114));
    
    // Calculate gradient using Sobel-like operator
    let right = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(pixel.x, 0.0), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    let left = dot(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(pixel.x, 0.0), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    let up = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, pixel.y), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    let down = dot(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, pixel.y), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    
    let dx = (right - left) * 0.5;
    let dy = (up - down) * 0.5;
    
    // Structure tensor: [dx*dx, dx*dy; dy*dx, dy*dy]
    return mat2x2<f32>(
        dx * dx, dx * dy,
        dy * dx, dy * dy
    );
}

fn calculateTensorEigen(tensor: mat2x2<f32>) -> vec4<f32> {
    // Eigenvalues of 2x2 matrix [[a, b], [b, d]]
    let a = tensor[0][0];
    let b = tensor[0][1];
    let d = tensor[1][1];
    
    let trace = a + d;
    let det = a * d - b * b;
    let discriminant = sqrt(max(trace * trace - 4.0 * det, 0.0));
    
    let lambda1 = (trace + discriminant) * 0.5;
    let lambda2 = (trace - discriminant) * 0.5;
    
    // Eigenvectors
    let vec1 = normalize(vec2<f32>(lambda1 - d, b + 0.0001));
    let vec2 = normalize(vec2<f32>(-vec1.y, vec1.x));
    
    return vec4<f32>(vec1, vec2); // vec_pos in xy, vec_neg in zw
}

// ═══ FLUID ADVECTION ═══
fn advectFluid(uv: vec2<f32>, velocity: vec2<f32>, dt: f32, pixel: vec2<f32>) -> vec3<f32> {
    // Backtrace for advection
    let prevUV = uv - velocity * dt;
    return textureSampleLevel(readTexture, u_sampler, clamp(prevUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
}

// ═══ MAIN ═══
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let pixel = 1.0 / resolution;
    let time = u.config.x;
    // ═══ AUDIO REACTIVITY ═══
    let audioOverall = u.zoom_config.x;
    let audioBass = audioOverall * 1.5;
    let audioReactivity = 1.0 + audioOverall * 0.3;
    let id = vec2<i32>(global_id.xy);
    
    // Parameters
    let tensorStrength = mix(0.0, 2.0, u.zoom_params.x);  // x: Tensor strength
    let viscosity = mix(0.1, 0.99, u.zoom_params.y);      // y: Viscosity
    let turbulence = mix(0.0, 0.5, u.zoom_params.z);      // z: Turbulence amount
    let advectionSpeed = mix(0.5, 3.0, u.zoom_params.w);  // w: Advection speed
    
    // Calculate structure tensor from image
    let tensor = calculateStructureTensor(uv, pixel);
    let eigen = calculateTensorEigen(tensor);
    
    // Principal flow direction (along edges)
    let flowDirection = eigen.xy;
    let edgeStrength = length(eigen.xy);
    
    // Get previous velocity from data texture
    var velocity = textureLoad(dataTextureC, id, 0).xy;
    
    // Apply tensor field influence - flow follows image structure
    velocity += flowDirection * tensorStrength * 0.01;
    
    // Add FBM turbulence
    let turb = fbm2(uv * 8.0 + time * 0.1 * audioReactivity, 4);
    velocity += vec2<f32>(
        fbm2(uv * 4.0 + vec2<f32>(time * 0.1 * audioReactivity, 0.0), 3) - 0.5,
        fbm2(uv * 4.0 + vec2<f32>(0.0, time * 0.1 * audioReactivity), 3) - 0.5
    ) * turbulence;
    
    // Apply viscosity (damping)
    velocity *= viscosity;
    
    // Store velocity for next frame
    textureStore(dataTextureA, id, vec4<f32>(velocity, 0.0, 1.0));
    
    // Advect color along flow field
    let dt = 0.016 * advectionSpeed;
    let advectedUV = uv + velocity * dt;
    
    // Sample with advected coordinates
    var color = textureSampleLevel(readTexture, u_sampler, clamp(advectedUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    
    // Depth-aware distortion
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthFactor = 1.0 - depth * 0.5;
    
    // Apply flow-based color modulation
    let flowIntensity = length(velocity) * 5.0;
    color = mix(color, color * (1.0 + flowIntensity), edgeStrength * 2.0);
    
    // Add iridescent highlights along flow
    let hueShift = flowIntensity * 0.1 + time * 0.05 * audioReactivity;
    let highlight = vec3<f32>(
        0.5 + 0.5 * cos(hueShift * 6.28),
        0.5 + 0.5 * cos(hueShift * 6.28 + 2.09),
        0.5 + 0.5 * cos(hueShift * 6.28 + 4.18)
    );
    color += highlight * flowIntensity * 0.3 * depthFactor;
    
    // Alpha based on motion and depth
    let alpha = mix(0.7, 1.0, flowIntensity);
    
    textureStore(writeTexture, id, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, id, vec4<f32>(depth * (1.0 - flowIntensity * 0.2), 0.0, 0.0, 0.0));
}
