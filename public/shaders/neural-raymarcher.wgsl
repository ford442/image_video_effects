// ═══════════════════════════════════════════════════════════════════
//  Neural Raymarcher
//  Category: generative
//  Features: advanced-hybrid, sdf-raymarching, neural-patterns, volumetric
//  Complexity: Very High
//  Chunks From: gen-xeno-botanical-synth-flora.wgsl, crystal-facets.wgsl
//  Created: 2026-03-22
//  By: Agent 3B - Advanced Hybrid Creator
// ═══════════════════════════════════════════════════════════════════
//  Raymarched neural network with activation visualization
//  Glowing 3D neural structure with weights as connection thickness
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

const MAX_STEPS: i32 = 64;
const MAX_DIST: f32 = 20.0;
const EPSILON: f32 = 0.001;

// ═══ CHUNK: sdSphere ═══
fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

// ═══ CHUNK: sdSmoothUnion ═══
fn sdSmoothUnion(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

// ═══ CHUNK: palette ═══
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

// ═══ NEURAL ACTIVATION FUNCTIONS ═══
fn activationTanh(x: f32) -> f32 {
    return tanh(x);
}

fn activationReLU(x: f32) -> f32 {
    return max(x, 0.0);
}

fn activationSigmoid(x: f32) -> f32 {
    return 1.0 / (1.0 + exp(-x));
}

// ═══ NEURAL SDF ═══
fn neuralSDF(p: vec3<f32>, time: f32, networkDepth: f32) -> vec2<f32> {
    var d = MAX_DIST;
    var activationSum = 0.0;
    
    let layers = i32(networkDepth * 4.0 + 2.0); // 2-6 layers
    let neuronsPerLayer = 6;
    
    for (var layer = 0; layer < layers; layer++) {
        let layerZ = f32(layer) * 2.0 - f32(layers - 1);
        let layerOffset = f32(layer) * 1.234;
        
        for (var i = 0; i < neuronsPerLayer; i++) {
            let neuronX = cos(f32(i) * 1.047 + time * 0.5 * audioReactivity + layerOffset) * 1.5;
            let neuronY = sin(f32(i) * 1.047 + time * 0.3 * audioReactivity + layerOffset) * 1.5;
            let neuronPos = vec3<f32>(neuronX, neuronY, layerZ);
            
            // Calculate activation
            let inputVal = sin(f32(i) * 0.5 + time + layerOffset);
            var activation = 0.0;
            
            if (layer % 3 == 0) {
                activation = activationTanh(inputVal);
            } else if (layer % 3 == 1) {
                activation = activationReLU(inputVal);
            } else {
                activation = activationSigmoid(inputVal);
            }
            
            activationSum += abs(activation);
            
            // Neuron size based on activation
            let neuronRadius = 0.15 + abs(activation) * 0.1;
            let neuron = sdSphere(p - neuronPos, neuronRadius);
            d = sdSmoothUnion(d, neuron, 0.2);
        }
    }
    
    // Connections between layers
    for (var layer = 0; layer < layers - 1; layer++) {
        let layerZ1 = f32(layer) * 2.0 - f32(layers - 1);
        let layerZ2 = f32(layer + 1) * 2.0 - f32(layers - 1);
        let layerOffset = f32(layer) * 1.234;
        
        for (var i = 0; i < neuronsPerLayer; i++) {
            let n1x = cos(f32(i) * 1.047 + time * 0.5 * audioReactivity + layerOffset) * 1.5;
            let n1y = sin(f32(i) * 1.047 + time * 0.3 * audioReactivity + layerOffset) * 1.5;
            
            // Connect to next layer with weighted connections
            for (var j = 0; j < 3; j++) {
                let weight = sin(f32(i * 3 + j) * 0.7 + time) * 0.5 + 0.5;
                let n2x = cos(f32((i + j) % neuronsPerLayer) * 1.047 + time * 0.5 * audioReactivity + layerOffset + 1.234) * 1.5;
                let n2y = sin(f32((i + j) % neuronsPerLayer) * 1.047 + time * 0.3 * audioReactivity + layerOffset + 1.234) * 1.5;
                
                let midPoint = vec3<f32>((n1x + n2x) * 0.5, (n1y + n2y) * 0.5, (layerZ1 + layerZ2) * 0.5);
                let connection = sdSphere(p - midPoint, 0.03 + weight * 0.05);
                d = sdSmoothUnion(d, connection, 0.1);
            }
        }
    }
    
    return vec2<f32>(d, activationSum);
}

// ═══ RAYMARCHING ═══
fn raymarch(ro: vec3<f32>, rd: vec3<f32>, time: f32, networkDepth: f32) -> vec4<f32> {
    var t = 0.0;
    var activation = 0.0;
    
    for (var i = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * t;
        let result = neuralSDF(p, time, networkDepth);
        let d = result.x;
        activation = result.y;
        
        if (d < EPSILON) {
            return vec4<f32>(t, activation, 0.0, 1.0);
        }
        
        if (t > MAX_DIST) {
            break;
        }
        
        t += d * 0.5;
    }
    
    return vec4<f32>(t, activation, 0.0, 0.0);
}

// ═══ MAIN ═══
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    
    let uv = (vec2<f32>(global_id.xy) / resolution - 0.5) * 2.0;
    let time = u.config.x;
    // ═══ AUDIO REACTIVITY ═══
    let audioOverall = u.config.y;
    let audioBass = u.config.y * 1.2;
    let audioMid = u.config.z;
    let audioHigh = u.config.w;
    let audioReactivity = 1.0 + audioOverall * 0.5;
    let id = vec2<i32>(global_id.xy);
    
    // Parameters
    let networkDepth = u.zoom_params.x;          // x: Network depth (0-1)
    let activationVis = u.zoom_params.y;         // y: Activation visualization
    let glowIntensity = mix(0.5, 2.0, u.zoom_params.z); // z: Glow intensity
    let cameraRotation = u.zoom_params.w * 6.28; // w: Camera rotation
    
    // Camera setup
    let camDist = 8.0;
    let camAngle = time * 0.2 * audioReactivity + cameraRotation;
    let ro = vec3<f32>(cos(camAngle) * camDist, sin(camAngle * 0.5) * 2.0, sin(camAngle) * camDist);
    let lookAt = vec3<f32>(0.0, 0.0, 0.0);
    let forward = normalize(lookAt - ro);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), forward));
    let up = cross(forward, right);
    
    // Ray direction
    let aspect = resolution.x / resolution.y;
    let rd = normalize(forward + right * uv.x * aspect * 0.5 + up * uv.y * 0.5);
    
    // Raymarch
    let result = raymarch(ro, rd, time, networkDepth);
    let t = result.x;
    let activation = result.y;
    let hit = result.w;
    
    var color = vec3<f32>(0.0);
    var depth = 1.0;
    
    if (hit > 0.5) {
        // Hit the neural structure
        let neuralColor = palette(activation * 0.1 + time * 0.05 * audioReactivity,
            vec3<f32>(0.5, 0.5, 0.5),
            vec3<f32>(0.5, 0.5, 0.5),
            vec3<f32>(1.0, 1.0, 0.8),
            vec3<f32>(0.0, 0.33, 0.67)
        );
        
        // Activation visualization
        let activationColor = mix(
            vec3<f32>(0.2, 0.4, 1.0),  // Low activation
            vec3<f32>(1.0, 0.2, 0.5),  // High activation
            activation * activationVis
        );
        
        color = mix(neuralColor, activationColor, activationVis * 0.7);
        depth = t / MAX_DIST;
    } else {
        // Background - sample original image
        let bgUV = vec2<f32>(global_id.xy) / resolution;
        color = textureSampleLevel(readTexture, u_sampler, bgUV, 0.0).rgb * 0.3;
    }
    
    // Volumetric glow effect
    var glow = 0.0;
    for (var i = 0; i < 16; i++) {
        let t_glow = MAX_DIST * f32(i) / 16.0;
        let p = ro + rd * t_glow;
        let result = neuralSDF(p, time, networkDepth);
        glow += exp(-result.x * 2.0) * result.y * 0.05;
    }
    
    let glowColor = vec3<f32>(0.4, 0.7, 1.0) * glow * glowIntensity;
    color += glowColor;
    
    // Alpha blending
    let alpha = mix(0.6, 1.0, hit + glow * 0.5);
    
    textureStore(writeTexture, id, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, id, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
