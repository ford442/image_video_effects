// ═══════════════════════════════════════════════════════════════════
//  Chrono-Voronoi Mycelium
//  Category: generative
//  Features: temporal-layers, voronoi-growth, audio-seasons, mouse-seeding, multi-scale, temporal, chromatic, depth-aware
//  Complexity: High
//  Chunks From: standard voronoi + temporal feedback patterns
//  Created: 2026-05-31
//  By: Grok (creative technical artist)
//  Upgraded: 2026-05-31
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

fn voronoi(p: vec2<f32>, time: f32, seed: f32) -> vec3<f32> {
    let n = floor(p);
    let f = fract(p);
    var res = vec3<f32>(8.0);
    
    for (var j = -1; j <= 1; j++) {
        for (var i = -1; i <= 1; i++) {
            let g = vec2<f32>(f32(i), f32(j));
            let o = hash12(n + g + seed) * vec2<f32>(1.0);
            let r = g + o - f;
            let d = dot(r, r);
            if (d < res.x) {
                res = vec3<f32>(d, o.x, o.y);
            }
        }
    }
    return res;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x * 0.4;
    
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    
    // Audio seasons
    let seasonBloom = mids * 0.8;
    let seasonHarsh = bass * 0.6;
    let seasonVolatile = treble * 0.9;
    
    // Mouse seeding
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mouse);
    let mouseSeed = smoothstep(0.08, 0.0, mouseDist) * mouseDown * 2.5;
    
    // Read previous temporal layers
    let prevLayer1 = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let prevLayer2 = textureSampleLevel(dataTextureA, u_sampler, uv, 0.0);
    
    // Multi-scale Voronoi growth
    let scale1 = 8.0 + seasonVolatile * 6.0;
    let scale2 = 18.0 + seasonBloom * 8.0;
    let scale3 = 32.0;
    
    let v1 = voronoi(uv * scale1, time * (0.6 + seasonHarsh * 0.4), 0.0);
    let v2 = voronoi(uv * scale2, time * (0.9 + seasonBloom * 0.3), 1.3);
    let v3 = voronoi(uv * scale3, time * 1.2, 3.7);
    
    // Growth with temporal memory
    let growth1 = smoothstep(0.02, 0.18, v1.x) * (0.6 + seasonBloom * 0.5);
    let growth2 = smoothstep(0.015, 0.12, v2.x) * (0.5 + seasonVolatile * 0.6);
    let growth3 = smoothstep(0.01, 0.08, v3.x) * (0.4 + seasonHarsh * 0.3);
    
    // Combine layers with decay
    let decay = 0.985 - seasonHarsh * 0.02;
    var layer1 = prevLayer1.r * decay + growth1 * 0.7;
    var layer2 = prevLayer2.g * (decay - 0.01) + growth2 * 0.65;
    var layer3 = prevLayer1.b * (decay - 0.02) + growth3 * 0.55;
    
    // Mouse seeding affects all layers
    layer1 = min(layer1 + mouseSeed * 0.8, 1.8);
    layer2 = min(layer2 + mouseSeed * 0.6, 1.6);
    layer3 = min(layer3 + mouseSeed * 0.9, 1.9);
    
    // Chromatic dispersion: audio-modulated layer offsets
    layer1 = layer1 + bass * 0.06;
    layer2 = layer2 + mids * 0.05;
    layer3 = layer3 + treble * 0.04;
    
    // Store temporal layers
    textureStore(dataTextureA, gid.xy, vec4<f32>(layer1, layer2, layer3, 0.0));
    textureStore(dataTextureB, gid.xy, vec4<f32>(layer2, layer3, layer1, 0.0));
    
    // Visualization - layered organic colors
    let ageMix = vec3<f32>(layer1, layer2 * 0.8, layer3 * 0.6);
    var col = mix(vec3<f32>(0.1, 0.15, 0.1), vec3<f32>(0.9, 0.95, 0.7), ageMix);
    
    // Temporal feedback blend
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    col = mix(col, prev.rgb * 0.9, 0.03 + bass * 0.01);
    
    // Subtle depth from layers
    let depth = (layer1 * 0.3 + layer2 * 0.5 + layer3 * 0.7) * 0.6 + 0.2;
    
    // Alpha represents "life" / density
    let life = clamp(layer1 + layer2 * 0.7 + layer3 * 0.5, 0.1, 1.3);
    let alpha = life * 0.85;
    
    let a = clamp(alpha, 0.0, 1.0);
    textureStore(writeTexture, gid.xy, vec4<f32>(col * a, a));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
