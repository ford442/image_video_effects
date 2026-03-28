// ═══════════════════════════════════════════════════════════════════
//  Neural Fractal - Neural network weight visualization fractals
//  Category: generative
//  Features: procedural, animated, neural-inspired activation functions
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

// Activation functions inspired by neural networks
fn sigmoid(x: f32) -> f32 {
    return 1.0 / (1.0 + exp(-x));
}

fn tanh_activation(x: f32) -> f32 {
    return tanh(x);
}

fn relu(x: f32) -> f32 {
    return max(x, 0.0);
}

fn swish(x: f32) -> f32 {
    return x * sigmoid(x);
}

// Neural layer iteration with domain warping
fn neuralLayer(z: vec2<f32>, c: vec2<f32>, activation: i32) -> vec2<f32> {
    var result: vec2<f32>;
    
    // Apply activation to components
    if (activation == 0) {
        // Sigmoid-based iteration
        result = vec2<f32>(
            sigmoid(z.x * z.x - z.y * z.y + c.x),
            sigmoid(2.0 * z.x * z.y + c.y)
        );
    } else if (activation == 1) {
        // Tanh-based iteration
        result = vec2<f32>(
            tanh_activation(z.x * z.x - z.y * z.y + c.x),
            tanh_activation(2.0 * z.x * z.y + c.y)
        );
    } else if (activation == 2) {
        // Swish-based iteration
        result = vec2<f32>(
            swish(z.x * z.x - z.y * z.y + c.x),
            swish(2.0 * z.x * z.y + c.y)
        );
    } else {
        // Mixed: sigmoid on x, tanh on y
        result = vec2<f32>(
            sigmoid(z.x * z.x - z.y * z.y + c.x),
            tanh_activation(2.0 * z.x * z.y + c.y)
        );
    }
    
    return result;
}

// Domain warping for organic feel
fn domainWarp(p: vec2<f32>, time: f32) -> vec2<f32> {
    let warp1 = vec2<f32>(
        sin(p.x * 3.0 + time * 0.5) * 0.1,
        cos(p.y * 3.0 + time * 0.3) * 0.1
    );
    let warp2 = vec2<f32>(
        sin(p.y * 5.0 - time * 0.4) * 0.05,
        cos(p.x * 5.0 + time * 0.6) * 0.05
    );
    return p + warp1 + warp2;
}

// Color palette generation
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let t = u.config.x;
    
    // Parameters - safe randomization
    let zoom = mix(0.5, 3.0, u.zoom_params.x);
    let colorSpeed = mix(0.1, 1.0, u.zoom_params.y);
    let iterations = i32(mix(30.0, 100.0, u.zoom_params.z));
    let mutation = mix(0.0, 0.5, u.zoom_params.w);
    
    // Map UV to complex plane with slow zoom
    let aspect = resolution.x / resolution.y;
    let zoomAnim = zoom * (1.0 + 0.2 * sin(t * 0.1));
    let scale = 2.5 / zoomAnim;
    
    // Center slowly drifts
    let center = vec2<f32>(
        sin(t * 0.05) * 0.1,
        cos(t * 0.07) * 0.1
    );
    
    var p = (uv - 0.5) * vec2<f32>(scale * aspect, scale) + center;
    
    // Apply domain warping
    p = domainWarp(p, t);
    
    // Julia set constant - animated
    let juliaC = vec2<f32>(
        sin(t * 0.1) * 0.5 + mutation * sin(p.x * 10.0),
        cos(t * 0.08) * 0.5 + mutation * cos(p.y * 10.0)
    );
    
    // Iterate with neural-inspired functions
    var z = p;
    var iter = 0;
    var trap = 1000.0;
    var sumZ = vec2<f32>(0.0);
    
    for (iter = 0; iter < iterations; iter++) {
        // Switch activation based on iteration for layered effect
        let activationType = (iter / 10) % 4;
        z = neuralLayer(z, juliaC, activationType);
        
        // Orbit trap for coloring
        let d = length(z - vec2<f32>(0.5, 0.0));
        trap = min(trap, d);
        
        sumZ = sumZ + z;
        
        if (length(z) > 10.0) {
            break;
        }
    }
    
    // Color calculation
    let iterRatio = f32(iter) / f32(iterations);
    
    // Palette parameters
    let palA = vec3<f32>(0.5, 0.5, 0.5);
    let palB = vec3<f32>(0.5, 0.5, 0.5);
    let palC = vec3<f32>(1.0, 1.0, 1.0);
    let palD = vec3<f32>(
        0.0 + t * colorSpeed * 0.1,
        0.33 + t * colorSpeed * 0.15,
        0.67 + t * colorSpeed * 0.2
    );
    
    // Base color from iteration
    var col = palette(iterRatio + trap * 2.0, palA, palB, palC, palD);
    
    // Add glow from orbit trap
    let glow = exp(-trap * 5.0) * 0.5;
    col += vec3<f32>(0.4, 0.2, 0.6) * glow;
    
    // Add structure from sum
    let structure = length(sumZ) * 0.01;
    col = mix(col, col * (1.0 + structure), 0.3);
    
    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.8;
    col *= vignette;
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(0.0, 0.0, 0.0, 0.0));
}
