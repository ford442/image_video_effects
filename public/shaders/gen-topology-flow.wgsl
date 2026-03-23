// ═══════════════════════════════════════════════════════════════════
//  Topology Flow - Topological surface flow with Morse theory
//  Category: generative
//  Features: procedural, gradient flow, critical point detection
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

// Value noise
fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

// FBM for height field
fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var pp = p;
    for (var i: i32 = 0; i < octaves; i++) {
        v += a * noise(pp);
        pp = pp * 2.0 + vec2<f32>(100.0);
        a *= 0.5;
    }
    return v;
}

// Height field function
fn heightField(p: vec2<f32>, complexity: f32, t: f32) -> f32 {
    let octaves = i32(mix(2.0, 6.0, complexity));
    var h = fbm(p + t * 0.1, octaves);
    
    // Add ridge-like features for Morse theory
    let ridge1 = sin(p.x * 3.0 + t * 0.2) * cos(p.y * 2.5);
    let ridge2 = sin((p.x + p.y) * 2.0 - t * 0.15);
    h += ridge1 * 0.2 + ridge2 * 0.15;
    
    // Add saddle points
    let saddle = (p.x * p.x - p.y * p.y) * 0.5;
    h += saddle * 0.1 * sin(t * 0.1);
    
    return h;
}

// Calculate gradient for flow direction
fn gradient(p: vec2<f32>, complexity: f32, t: f32) -> vec2<f32> {
    let eps = 0.01;
    let h = heightField(p, complexity, t);
    let hx = heightField(p + vec2<f32>(eps, 0.0), complexity, t);
    let hy = heightField(p + vec2<f32>(0.0, eps), complexity, t);
    return vec2<f32>((hx - h) / eps, (hy - h) / eps);
}

// Detect critical points (where gradient is near zero)
fn detectCritical(grad: vec2<f32>, secondDeriv: f32) -> i32 {
    let gradMag = length(grad);
    
    if (gradMag < 0.05) {
        // Max, min, or saddle based on second derivative
        if (secondDeriv < -0.1) { return 1; } // Maximum (peak)
        else if (secondDeriv > 0.1) { return 2; } // Minimum (valley)
        else { return 3; } // Saddle point
    }
    return 0; // Not critical
}

// Height-based color
fn heightColor(h: f32) -> vec3<f32> {
    // Valleys (blue) to peaks (red)
    let valley = vec3<f32>(0.1, 0.3, 0.8);
    let mid = vec3<f32>(0.2, 0.6, 0.3);
    let peak = vec3<f32>(0.9, 0.2, 0.1);
    
    if (h < 0.4) {
        return mix(valley, mid, h / 0.4);
    } else {
        return mix(mid, peak, (h - 0.4) / 0.6);
    }
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let t = u.config.x;
    
    // Parameters - safe randomization
    let flowSpeed = mix(0.2, 2.0, u.zoom_params.x);
    let complexity = u.zoom_params.y;
    let particleDensity = mix(50.0, 300.0, u.zoom_params.z);
    let trailPersistence = mix(0.8, 0.98, u.zoom_params.w);
    
    // Map UV to flow space
    let aspect = resolution.x / resolution.y;
    let p = uv * vec2<f32>(aspect * 3.0, 3.0) - vec2<f32>(aspect * 1.5, 1.5);
    
    // Get height and gradient
    let h = heightField(p, complexity, t);
    let grad = gradient(p, complexity, t);
    
    // Second derivative approximation (Laplacian)
    let eps = 0.02;
    let hL = heightField(p - vec2<f32>(eps, 0.0), complexity, t);
    let hR = heightField(p + vec2<f32>(eps, 0.0), complexity, t);
    let hD = heightField(p - vec2<f32>(0.0, eps), complexity, t);
    let hU = heightField(p + vec2<f32>(0.0, eps), complexity, t);
    let laplacian = (hL + hR + hD + hU - 4.0 * h) / (eps * eps);
    
    // Detect critical points
    let critical = detectCritical(grad, laplacian);
    
    // Base color from height
    var col = heightColor(h);
    
    // Draw flow lines using streamline integration
    var flowAccum = 0.0;
    var particleCount = 0.0;
    
    // Seed particles across the field
    let numParticles = i32(particleDensity);
    for (var i: i32 = 0; i < numParticles; i++) {
        let seed = vec2<f32>(f32(i) * 0.1, f32(i) * 0.07);
        var particlePos = fract(seed + t * flowSpeed * 0.1) * vec2<f32>(aspect * 3.0, 3.0) - vec2<f32>(aspect * 1.5, 1.5);
        
        // Advect particle backwards to see if it passes through current pixel
        for (var step: i32 = 0; step < 20; step++) {
            let g = gradient(particlePos, complexity, t);
            particlePos = particlePos - normalize(g) * 0.02;
            
            let dist = length(particlePos - p);
            if (dist < 0.03) {
                flowAccum += 1.0 - dist / 0.03;
                particleCount += 1.0;
            }
        }
    }
    
    // Add flow visualization
    let flowIntensity = flowAccum * 0.1;
    let flowDir = normalize(grad);
    let flowCol = vec3<f32>(0.5 + flowDir.x * 0.5, 0.5 + flowDir.y * 0.5, 0.8);
    col = mix(col, flowCol, min(flowIntensity, 0.5));
    
    // Highlight critical points
    if (critical == 1) {
        // Peak - white glow
        col = mix(col, vec3<f32>(1.0, 0.9, 0.7), 0.7);
    } else if (critical == 2) {
        // Valley - dark blue
        col = mix(col, vec3<f32>(0.0, 0.1, 0.4), 0.5);
    } else if (critical == 3) {
        // Saddle - yellow
        col = mix(col, vec3<f32>(0.9, 0.8, 0.2), 0.6);
    }
    
    // Contour lines
    let contour = abs(fract(h * 10.0) - 0.5);
    let contourMask = smoothstep(0.02, 0.0, contour);
    col = mix(col, col * 0.7, contourMask * 0.5);
    
    // Previous frame for trails
    let prev = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0).rgb;
    col = col * 0.3 + prev * trailPersistence;
    
    // Store for feedback
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(h * 0.5 + 0.5, 0.0, 0.0, 0.0));
}
