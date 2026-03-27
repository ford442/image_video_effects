// ═══════════════════════════════════════════════════════════════════
//  Hybrid Magnetic Field
//  Category: generative
//  Features: hybrid, vector-field, particle-trails, magnetic-distortion
//  Chunks From: magnetic-field.wgsl (vector field), particle-swarm.wgsl (trails),
//               fbm noise for field variation
//  Created: 2026-03-22
//  By: Agent 2A - Shader Surgeon
// ═══════════════════════════════════════════════════════════════════
//  Concept: Magnetic field line visualization with flowing particles
//           and FBM-varied field distortion
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

// ═══ CHUNK 4: rot2 (from kaleidoscope.wgsl) ═══
fn rot2(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// ═══ HYBRID LOGIC: Magnetic Field Visualization ═══
// Magnetic dipole field calculation
fn magneticField(pos: vec2<f32>, dipolePos: vec2<f32>, strength: f32) -> vec2<f32> {
    let r = pos - dipolePos;
    let dist = length(r);
    let dist3 = dist * dist * dist + 0.001; // Avoid division by zero
    
    // Dipole field: 3(m·r̂)r̂ - m
    // Simplified for 2D: radial component falls as 1/r^3
    let radial = r / dist;
    let field = radial * strength / dist3;
    
    return vec2<f32>(-field.y, field.x); // Perpendicular for field lines
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;
    
    // Parameters
    let fieldStrength = mix(0.5, 3.0, u.zoom_params.x);    // x: Field intensity
    let lineDensity = mix(5.0, 30.0, u.zoom_params.y);     // y: Line density
    let trailPersistence = u.zoom_params.z * 0.95;         // z: Trail fade
    let noiseInfluence = u.zoom_params.w * 2.0;            // w: Field distortion
    
    // Mouse as magnetic source
    var mouse = u.zoom_config.yz;
    mouse.x *= aspect;
    var p = uv;
    p.x *= aspect;
    
    // Multiple magnetic sources
    let source1 = vec2<f32>(mouse.x, mouse.y);
    let source2 = vec2<f32>(0.5 * aspect + sin(time * 0.5) * 0.2, 0.5 + cos(time * 0.3) * 0.2);
    
    // Calculate magnetic field vector
    var field = vec2<f32>(0.0);
    field += magneticField(p, source1, fieldStrength);
    field += magneticField(p, source2, fieldStrength * 0.5);
    
    // Add FBM noise variation to field
    let noiseField = vec2<f32>(
        fbm2(uv * 5.0 + time * 0.1, 4),
        fbm2(uv * 5.0 + vec2<f32>(5.2, 1.3), 4)
    ) * noiseInfluence;
    field += noiseField;
    
    // Normalize field for visualization
    let fieldMag = length(field);
    let fieldDir = field / (fieldMag + 0.001);
    
    // Field line pattern
    let fieldAngle = atan2(fieldDir.y, fieldDir.x);
    let linePattern = sin(fieldAngle * lineDensity + fieldMag * 10.0);
    let isFieldLine = smoothstep(0.8, 1.0, linePattern);
    
    // Particle trails along field lines
    let flowUV = uv + fieldDir * 0.01;
    let prevFrame = textureSampleLevel(dataTextureC, u_sampler, flowUV, 0.0).rgb;
    
    // Color based on field strength and direction
    let fieldColor = palette(fieldAngle * 0.5 + time * 0.1,
        vec3<f32>(0.5),
        vec3<f32>(0.5),
        vec3<f32>(1.0, 1.0, 0.5),
        vec3<f32>(0.8, 0.9, 0.3)
    );
    
    // Combine field lines with trails
    var color = prevFrame * trailPersistence;
    color += fieldColor * isFieldLine * (0.5 + fieldMag * 0.3);
    
    // Glow around magnetic sources
    let dist1 = length(p - source1);
    let dist2 = length(p - source2);
    let glow = exp(-dist1 * 3.0) + exp(-dist2 * 3.0) * 0.5;
    color += vec3<f32>(1.0, 0.8, 0.3) * glow * 0.5;
    
    // Vortex visualization at source
    let vortex = sin(atan2(p.y - source1.y, p.x - source1.x) * 10.0 + dist1 * 20.0);
    color += vec3<f32>(0.3, 0.6, 1.0) * vortex * exp(-dist1 * 2.0) * 0.3;
    
    // Alpha based on field activity
    let alpha = mix(0.4, 1.0, isFieldLine + glow * 0.5);
    
    // Store for feedback
    textureStore(dataTextureA, global_id.xy, vec4<f32>(color, alpha));
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(fieldMag * 0.5, 0.0, 0.0, 0.0));
}
