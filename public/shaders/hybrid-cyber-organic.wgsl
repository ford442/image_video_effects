// ═══════════════════════════════════════════════════════════════════
//  Hybrid Cyber-Organic
//  Category: generative
//  Features: hybrid, circuit-patterns, organic-growth, neon-glow
//  Chunks From: hex-circuit.wgsl (hex-grid), digital-moss.wgsl (growth logic),
//               neon-edge-diffusion.wgsl (glow calculation)
//  Created: 2026-03-22
//  By: Agent 2A - Shader Surgeon
// ═══════════════════════════════════════════════════════════════════
//  Concept: Digital circuit traces that grow organically with neon glow,
//           combining hexagonal grid structures with cellular growth patterns
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

// ═══ CHUNK 2: hexEdgeDist (from hex-circuit.wgsl) ═══
fn hexEdgeDist(p: vec2<f32>) -> f32 {
    var q = abs(p);
    return max(q.x * 0.5 + q.y * 0.866025, q.x);
}

// ═══ CHUNK 3: palette (from gen-xeno-botanical-synth-flora.wgsl) ═══
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

// ═══ CHUNK 4: fbm2 (from gen_grid.wgsl) ═══
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

// ═══ HYBRID LOGIC: Cyber-Organic Fusion ═══
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let id = vec2<i32>(global_id.xy);
    
    // Parameters
    let gridSize = mix(5.0, 25.0, u.zoom_params.x);        // x: Circuit density
    let growthAmount = u.zoom_params.y;                     // y: Organic growth
    let glowStrength = mix(0.5, 3.0, u.zoom_params.z);      // z: Neon glow
    let chaosFactor = u.zoom_params.w * 0.5;                // w: Randomness
    
    // Hex grid setup
    let aspect = resolution.x / resolution.y;
    let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
    var p = uvCorrected * gridSize;
    
    // Hex grid calculation
    let r = vec2<f32>(1.0, 1.7320508);
    let h = r * 0.5;
    let fractA = fract(p / r) * r - h;
    let fractB = (fract((p / r) + 0.5) * r) - h;
    
    var localUV = vec2<f32>(0.0);
    if (dot(fractA, fractA) < dot(fractB, fractB)) {
        localUV = fractA;
    } else {
        localUV = fractB;
    }
    
    // Hex distance
    var q = abs(localUV);
    let distToCenter = max(q.x * 0.5 + q.y * 0.866025, q.x);
    let distToEdge = 0.5 - distToCenter;
    
    // Organic growth pattern using FBM
    let cellId = floor(p / r);
    let growthNoise = fbm2(cellId * 0.5 + time * 0.1, 3);
    let growthPattern = smoothstep(0.3, 0.7, growthNoise + growthAmount - 0.5);
    
    // Circuit activation based on growth
    let circuitActive = growthPattern > 0.5;
    let lineThickness = mix(0.02, 0.08, growthAmount) * (1.0 + chaosFactor * hash12(cellId));
    let isHexLine = 1.0 - smoothstep(0.0, lineThickness, distToEdge);
    
    // Organic tendrils extending from hexes
    let tendrilNoise = fbm2(uv * gridSize * 2.0 + time * 0.2, 4);
    let tendrils = smoothstep(0.4, 0.6, tendrilNoise) * growthPattern;
    
    // Neon glow colors
    let hue = cellId.x * 0.1 + cellId.y * 0.05 + time * 0.1;
    let baseColor = palette(hue,
        vec3<f32>(0.5),
        vec3<f32>(0.5),
        vec3<f32>(1.0, 1.0, 0.5),
        vec3<f32>(0.0, 0.33, 0.67)
    );
    
    // Cyber color when active, organic when growing
    let cyberColor = mix(
        vec3<f32>(0.0, 0.8, 1.0),  // Cyan circuit
        vec3<f32>(0.2, 1.0, 0.3),  // Green organic
        growthPattern
    );
    
    // Combine colors
    var color = vec3<f32>(0.02, 0.03, 0.05);  // Dark background
    
    // Hex circuit lines
    if (isHexLine > 0.0 && circuitActive) {
        color = mix(color, cyberColor * glowStrength, isHexLine);
    }
    
    // Organic tendrils
    color += vec3<f32>(0.1, 0.9, 0.4) * tendrils * growthAmount;
    
    // Neon glow around active circuits
    let glowRadius = lineThickness * 3.0;
    let glow = (1.0 - smoothstep(0.0, glowRadius, distToEdge)) * growthPattern;
    color += baseColor * glow * glowStrength * 0.5;
    
    // Pulse effect along circuits
    let pulse = sin(time * 3.0 + cellId.x * 0.5 + cellId.y * 0.3) * 0.5 + 0.5;
    color += cyberColor * pulse * isHexLine * 0.3;
    
    // Alpha based on activity
    let activity = isHexLine + tendrils + glow * 0.5;
    let alpha = mix(0.3, 1.0, activity);
    
    textureStore(writeTexture, id, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, id, vec4<f32>(growthPattern, 0.0, 0.0, 0.0));
}
