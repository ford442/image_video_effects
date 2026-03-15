// ═══════════════════════════════════════════════════════════════
//  Cross-Stitch - Physical Media Simulation with Alpha
//  Category: artistic
//  Features: thread coverage → alpha, fabric substrate, stitch depth
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

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx+33.33);
    return fract((p3.xx+p3.yz)*p3.zy);
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Params
    let baseScale = max(0.005, u.zoom_params.x * 0.1);
    let thickness = max(0.05, u.zoom_params.y);
    let mouseRadius = u.zoom_params.z;
    let threadDensity = u.zoom_params.w; // How dense the thread coverage is

    var mousePos = u.zoom_config.yz;
    let d = distance(uv * vec2<f32>(aspect, 1.0), mousePos * vec2<f32>(aspect, 1.0));

    // Mouse Interaction: Unravel / Distort Scale
    var influence = smoothstep(mouseRadius, 0.0, d);

    var gridUV = uv;
    if (influence > 0.0) {
       let noise = (hash22(uv * 10.0 + u.config.x) - 0.5) * 0.1 * influence;
       gridUV += noise;
    }

    // Grid Logic
    let gridID = floor(gridUV / baseScale);
    let gridCenter = (gridID + 0.5) * baseScale;
    let localUV = (gridUV - gridID * baseScale) / baseScale;

    // Sample image at grid center to get the thread color
    let color = textureSampleLevel(readTexture, u_sampler, gridCenter, 0.0).rgb;

    // Draw X Shape (cross-stitch pattern)
    let d1 = abs(localUV.x - localUV.y);
    let d2 = abs(localUV.x + localUV.y - 1.0);
    let lineDist = min(d1, d2);

    // Mask for the thread
    let mask = 1.0 - smoothstep(thickness * 0.5, thickness * 0.5 + 0.1, lineDist);

    // Thread texture/shading
    let thread = sin(localUV.x * 30.0) * sin(localUV.y * 30.0) * 0.2 + 0.8;

    // Shadow under the thread
    let shadow = smoothstep(thickness + 0.1, thickness + 0.3, lineDist);

    // Background cloth (Aida fabric)
    let cloth = vec3<f32>(0.95, 0.94, 0.92);

    // CROSS-STITCH THREAD ALPHA CALCULATION
    // Physical embroidery properties:
    // - Thread has physical thickness → coverage → alpha
    // - Fabric substrate visible between stitches
    // - Multiple thread crossings = more opaque
    
    // THREAD COVERAGE → ALPHA MAPPING
    // - Dense stitching (thread overlap): high opacity (alpha ~0.85-0.95)
    // - Single thread: medium opacity (alpha ~0.6-0.75)
    // - Fabric only: substrate visible (alpha ~0.0)
    
    // Base alpha from thread presence
    var thread_alpha = mask * (0.6 + threadDensity * 0.35);
    
    // Thread thickness variation (some threads are thicker than others)
    // Simulated by slight color variation in input
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let thread_thickness = mix(0.85, 1.0, luma);
    thread_alpha *= thread_thickness;
    
    // Shadow area increases perceived density (thread is raised)
    let depth_effect = (1.0 - shadow) * 0.15;
    thread_alpha = min(1.0, thread_alpha + depth_effect);
    
    // Edge anti-aliasing for thread
    let edge_softness = smoothstep(0.0, 0.3, mask);
    thread_alpha *= mix(0.7, 1.0, edge_softness);
    
    // Fabric texture (Aida cloth has a grid pattern)
    let fabric_grid = abs(sin(gridUV.x * 200.0)) * abs(sin(gridUV.y * 200.0));
    let fabric_tex = mix(0.92, 1.0, fabric_grid * 0.5);
    
    // Apply fabric texture to cloth areas
    let cloth_with_texture = cloth * fabric_tex;
    
    // Color modification based on thread properties
    var thread_color = color * thread;
    
    // Darker threads appear more opaque (more pigment)
    let dark_boost = 1.0 - luma * 0.3;
    thread_alpha *= dark_boost;
    
    // Final Mix with alpha
    var finalColor = mix(cloth_with_texture * shadow, thread_color, mask);
    
    // Adjust final color alpha based on thread coverage
    // Where there's no thread, we see the fabric (low alpha)
    // Where there's thread, we see the stitch (higher alpha)
    let final_alpha = mix(0.15, thread_alpha, mask);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, final_alpha));

    // Store thread thickness in depth
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(mask * threadDensity, 0.0, 0.0, final_alpha));
}
