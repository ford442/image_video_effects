// ═══════════════════════════════════════════════════════════════════
//  Emergent Calligraphic Weave
//  Category: generative
//  Features: stroke-based, emergent-symbols, audio-field, mouse-influence, temporal
//  Complexity: High
//  Chunks From: orientation field techniques + particle advection
//  Created: 2026-05-31
//  By: Grok (creative technical artist)
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn getOrientation(p: vec2<f32>, t: f32, complexity: f32) -> f32 {
    let n1 = hash12(p * 1.7 + t * 0.1) - 0.5;
    let n2 = hash12(p * 4.3 - t * 0.17) - 0.5;
    return (n1 * 1.2 + n2 * 0.6) * complexity;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x * 0.6;
    
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    
    // Read previous stroke field
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    
    // Audio-driven field parameters
    let fieldStrength = 0.6 + mids * 0.8;
    let strokeLength = 0.012 + bass * 0.018;
    let chaos = 0.3 + treble * 0.9;
    
    // Mouse influence on orientation field
    let toMouse = normalize(uv - mouse + vec2<f32>(0.0001));
    let mouseAngle = atan2(toMouse.y, toMouse.x);
    let mouseInfluence = smoothstep(0.25, 0.02, length(uv - mouse)) * mouseDown * 1.5;
    
    // Base orientation field
    let baseAngle = getOrientation(uv * 2.5, time, 1.0 + chaos * 0.6);
    
    // Combine with mouse influence
    let angle = mix(baseAngle, mouseAngle, mouseInfluence);
    
    // Sample previous stroke in the direction of the field
    let dir = vec2<f32>(cos(angle), sin(angle));
    let sampleUV = clamp(uv - dir * strokeLength, vec2<f32>(0.0), vec2<f32>(1.0));
    let sampled = textureSampleLevel(dataTextureC, u_sampler, sampleUV, 0.0);
    
    // Stroke accumulation with decay
    let decay = 0.94 - bass * 0.03;
    var newStroke = sampled.r * decay + 0.06;
    
    // Add new strokes where field is coherent
    let coherence = 1.0 - abs(sampled.g - angle) * 0.8;
    newStroke += coherence * 0.045 * (0.6 + mids * 0.5);
    
    // Store new field (stroke density + angle)
    textureStore(dataTextureA, gid.xy, vec4<f32>(newStroke, angle, 0.0, 0.0));
    
    // Visualization
    let density = clamp(newStroke, 0.0, 1.4);
    let ink = pow(density, 0.85);
    
    // Elegant color - warm ink on cool background
    let col = mix(vec3<f32>(0.08, 0.06, 0.04), vec3<f32>(0.95, 0.88, 0.65), ink);
    
    // Subtle color variation based on angle
    let hueShift = sin(angle * 2.0) * 0.08;
    let finalCol = col * (1.0 + hueShift);
    
    let alpha = ink * 0.92;
    let a = clamp(alpha, 0.0, 1.0);
    
    textureStore(writeTexture, gid.xy, vec4<f32>(finalCol * a, a));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(density * 0.6, 0.0, 0.0, 0.0));
}