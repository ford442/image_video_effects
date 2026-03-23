// ═══════════════════════════════════════════════════════════════════
//  Chromatic Reaction-Diffusion
//  Category: artistic
//  Features: advanced-hybrid, gray-scott-rd, multi-channel, chromatic-separation
//  Complexity: High
//  Chunks From: reaction-diffusion.wgsl, gen_grid
//  Created: 2026-03-22
//  By: Agent 3B - Advanced Hybrid Creator
// ═══════════════════════════════════════════════════════════════════
//  Each RGB channel has separate feed/kill rates
//  Creates organic patterns with chromatic fringes at boundaries
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

// ═══ LAPLACIAN KERNEL ═══
fn laplacian9(coord: vec2<i32>, channel: i32) -> f32 {
    var sum: f32 = 0.0;
    let kernel = array<f32, 9>(0.05, 0.2, 0.05, 0.2, -1.0, 0.2, 0.05, 0.2, 0.05);
    var k: i32 = 0;
    for (var j: i32 = -1; j <= 1; j++) {
        for (var i: i32 = -1; i <= 1; i++) {
            let sample = textureLoad(dataTextureC, coord + vec2<i32>(i, j), 0)[channel];
            sum += sample * kernel[k];
            k++;
        }
    }
    return sum;
}

// ═══ REACT-DIFFUSE FUNCTION ═══
fn reactDiffuse(current: f32, lap: f32, feed: f32, kill: f32) -> f32 {
    let reaction = current * current * current;
    let diffusion = lap * 0.2;
    let feedTerm = feed * (1.0 - current);
    let killTerm = (kill + feed) * current;
    
    return current + diffusion - reaction + feedTerm - killTerm;
}

// ═══ MAIN ═══
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let id = vec2<i32>(global_id.xy);
    
    // Parameters - separate feed rates for each channel
    let feedR = mix(0.01, 0.1, u.zoom_params.x);    // x: Red feed rate
    let feedG = mix(0.02, 0.08, u.zoom_params.y);   // y: Green feed rate  
    let feedB = mix(0.005, 0.12, u.zoom_params.z);  // z: Blue feed rate
    let chromaticSep = mix(0.0, 0.03, u.zoom_params.w); // w: Chromatic separation
    
    // Kill rates derived from feed rates for interesting patterns
    let killR = feedR * 2.5 + 0.015;
    let killG = feedG * 2.2 + 0.02;
    let killB = feedB * 1.8 + 0.025;
    
    // Read current chemical states
    let curR = textureLoad(dataTextureC, id, 0).r;
    let curG = textureLoad(dataTextureC, id, 0).g;
    let curB = textureLoad(dataTextureC, id, 0).b;
    
    // Calculate Laplacian for each channel
    let lapR = laplacian9(id, 0);
    let lapG = laplacian9(id, 1);
    let lapB = laplacian9(id, 2);
    
    // Reaction-diffusion for each channel
    var newR = reactDiffuse(curR, lapR, feedR, killR);
    var newG = reactDiffuse(curG, lapG, feedG, killG);
    var newB = reactDiffuse(curB, lapB, feedB, killB);
    
    // Inject chemicals at mouse position
    let mouse = u.zoom_config.yz;
    let distToMouse = distance(uv, mouse);
    if (distToMouse < 0.05) {
        let injection = (1.0 - distToMouse / 0.05) * 0.5;
        newR += injection * 0.8;
        newG += injection * 0.6;
        newB += injection * 0.9;
    }
    
    // Clamp values
    newR = clamp(newR, 0.0, 1.0);
    newG = clamp(newG, 0.0, 1.0);
    newB = clamp(newB, 0.0, 1.0);
    
    // Store state for next frame
    textureStore(dataTextureA, id, vec4<f32>(newR, newG, newB, 1.0));
    
    // Chromatic aberration based on pattern gradients
    let gradR = vec2<f32>(
        textureLoad(dataTextureC, id + vec2<i32>(1, 0), 0).r - textureLoad(dataTextureC, id - vec2<i32>(1, 0), 0).r,
        textureLoad(dataTextureC, id + vec2<i32>(0, 1), 0).r - textureLoad(dataTextureC, id - vec2<i32>(0, 1), 0).r
    );
    let gradG = vec2<f32>(
        textureLoad(dataTextureC, id + vec2<i32>(1, 0), 0).g - textureLoad(dataTextureC, id - vec2<i32>(1, 0), 0).g,
        textureLoad(dataTextureC, id + vec2<i32>(0, 1), 0).g - textureLoad(dataTextureC, id - vec2<i32>(0, 1), 0).g
    );
    let gradB = vec2<f32>(
        textureLoad(dataTextureC, id + vec2<i32>(1, 0), 0).b - textureLoad(dataTextureC, id - vec2<i32>(1, 0), 0).b,
        textureLoad(dataTextureC, id + vec2<i32>(0, 1), 0).b - textureLoad(dataTextureC, id - vec2<i32>(0, 1), 0).b
    );
    
    // Displace each channel differently based on the others' gradients
    let pixel = 1.0 / resolution;
    let rUV = clamp(uv + gradG * chromaticSep, vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(uv + (gradR + gradB) * 0.5 * chromaticSep, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv + gradG * chromaticSep * 0.8, vec2<f32>(0.0), vec2<f32>(1.0));
    
    // Sample background through displaced channels
    let bgR = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let bgG = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let bgB = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    
    // Combine RD pattern with chromatic background
    let patternIntensity = (newR + newG + newB) / 3.0;
    let rdColor = vec3<f32>(newR * 0.8 + newG * 0.2, newG * 0.7 + newB * 0.3, newB * 0.9 + newR * 0.1);
    let bgColor = vec3<f32>(bgR, bgG, bgB);
    
    var color = mix(bgColor, rdColor, patternIntensity * 0.7);
    
    // Add edge glow at pattern boundaries
    let edge = length(gradR) + length(gradG) + length(gradB);
    color += vec3<f32>(edge * 0.5, edge * 0.3, edge * 0.7) * chromaticSep * 10.0;
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let alpha = mix(0.6, 0.95, patternIntensity);
    
    textureStore(writeTexture, id, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, id, vec4<f32>(depth * (1.0 - patternIntensity * 0.2), 0.0, 0.0, 0.0));
}
