// ═══════════════════════════════════════════════════════════════════
//  Hybrid Voronoi Glass
//  Category: distortion
//  Features: hybrid, voronoi-cells, glass-refraction, chromatic-dispersion
//  Chunks From: voronoi-glass.wgsl (voronoi), crystal-facets.wgsl (fresnel),
//               hyperbolic-dreamweaver.wgsl (dispersion)
//  Created: 2026-03-22
//  By: Agent 2A - Shader Surgeon
// ═══════════════════════════════════════════════════════════════════
//  Concept: Voronoi diagram rendered as glass blocks with chromatic
//           dispersion and physically-inspired refraction
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

// ═══ CHUNK 1: hash22 (from voronoi-glass.wgsl) ═══
fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// ═══ CHUNK 2: fresnelSchlick (from crystal-facets.wgsl) ═══
fn fresnelSchlick(cosTheta: f32, F0: f32) -> f32 {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// ═══ HYBRID LOGIC: Voronoi Glass ═══
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Parameters
    let cellDensity = mix(3.0, 20.0, u.zoom_params.x);     // x: Cell density
    let ior = mix(1.1, 1.8, u.zoom_params.y);              // y: Index of refraction
    let dispersion = u.zoom_params.z * 0.1;                // z: Chromatic dispersion
    let glassThickness = mix(0.1, 1.0, u.zoom_params.w);   // w: Glass thickness
    
    let aspect = resolution.x / resolution.y;
    let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
    
    // Voronoi calculation
    let i_st = floor(uv_corrected * cellDensity);
    let f_st = fract(uv_corrected * cellDensity);
    
    var m_dist = 1.0;
    var m_point = vec2<f32>(0.0);
    var m_neighbor = vec2<f32>(0.0);
    var second_dist = 1.0;
    
    // Iterate through neighbors for Voronoi
    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            var point = hash22(i_st + neighbor);
            
            // Animate point
            point = 0.5 + 0.5 * sin(time * 0.5 + 6.2831 * point);
            
            let diff = neighbor + point - f_st;
            let dist = length(diff);
            
            if (dist < m_dist) {
                second_dist = m_dist;
                m_dist = dist;
                m_neighbor = neighbor;
                m_point = point;
            } else if (dist < second_dist) {
                second_dist = dist;
            }
        }
    }
    
    // Calculate Voronoi edge
    let edgeDist = second_dist - m_dist;
    let isEdge = 1.0 - smoothstep(0.0, 0.05, edgeDist);
    
    // Calculate normal based on distance from cell center
    let toCenter = m_point - f_st;
    let normal = normalize(vec3<f32>(toCenter, 0.5));
    
    // Chromatic dispersion - different IOR per channel
    let iorR = ior - dispersion;
    let iorG = ior;
    let iorB = ior + dispersion;
    
    // Refraction for each channel
    let refractStrength = (ior - 1.0) * 0.1;
    let rUV = uv + normal.xy * refractStrength * (1.0 / iorR);
    let gUV = uv + normal.xy * refractStrength * (1.0 / iorG);
    let bUV = uv + normal.xy * refractStrength * (1.0 / iorB);
    
    // Sample with refraction
    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    var color = vec3<f32>(r, g, b);
    
    // Fresnel reflection on edges
    let cosTheta = max(dot(normal, vec3<f32>(0.0, 0.0, 1.0)), 0.0);
    let F0 = pow((ior - 1.0) / (ior + 1.0), 2.0);
    let fresnel = fresnelSchlick(1.0 - cosTheta, F0);
    
    // Glass edge highlight
    color += vec3<f32>(0.9, 0.95, 1.0) * isEdge * fresnel * 0.5;
    
    // Cell interior color variation
    let cellColor = hash22(i_st + m_neighbor);
    let tint = vec3<f32>(
        0.8 + cellColor.x * 0.2,
        0.9 + cellColor.y * 0.1,
        1.0
    );
    color *= mix(vec3<f32>(1.0), tint, glassThickness * 0.3);
    
    // Alpha based on fresnel and thickness
    let alpha = mix(0.4, 0.95, fresnel * glassThickness + isEdge * 0.5);
    
    // Sample depth through glass
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, gUV, 0.0).r;
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth * (1.0 - fresnel * 0.3), 0.0, 0.0, 0.0));
}
