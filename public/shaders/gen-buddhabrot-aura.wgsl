// ═══════════════════════════════════════════════════════════════════
//  Buddhabrot Aura
//  Category: generative
//  Features: buddhabrot, fractal, generative, audio-reactive, mouse-interactive, semantic-alpha
//  Complexity: High
//  Created: 2026-05-30
//  Updated: 2026-06-01
//  By: Kimi Agent (integrated + upgraded)
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

fn mandelIter(c: vec2<f32>, maxIter: i32) -> i32 {
    var z = vec2<f32>(0.0);
    for (var i = 0; i < maxIter; i++) {
        z = vec2<f32>(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
        if (dot(z, z) > 4.0) { return i; }
    }
    return maxIter;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let orbitThreshold = u.zoom_params.x * (18.0 + bass * 8.0);
    let densityScale = u.zoom_params.y * (0.8 + treble * 0.5);
    let mouseZoom = u.zoom_params.z;
    let aura = u.zoom_params.w;

    let mouse = u.zoom_config.yz;
    let mouseC = (mouse - 0.5) * 2.0 * mouseZoom;

    let c = uv * 1.8 + mouseC;
    let maxIter = i32(orbitThreshold);

    // Buddhabrot sampling (simplified single-pass version)
    var z = vec2<f32>(0.0);
    var density = 0.0;
    var pathSum = vec2<f32>(0.0);

    for (var i = 0; i < maxIter; i++) {
        z = vec2<f32>(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
        pathSum += z;
        if (dot(z, z) > 4.0) { break; }
        density += 1.0 / f32(maxIter);
    }

    let r = fract(density * densityScale * 1.6 + time * 0.03);
    let g = fract(density * densityScale * 1.1 + mids * 0.2);
    let b = fract(density * densityScale * 0.7 + treble * 0.15);

    var color = vec3<f32>(r, g, b) * (0.6 + aura * 0.8);

    // Subtle center glow / aura
    let center = length(uv - mouseC * 0.3);
    color += vec3<f32>(0.15, 0.12, 0.25) * smoothstep(0.8, 0.2, center) * aura;

    // Semantic alpha - higher where the fractal density is strong
    let semantic_alpha = clamp(0.45 + density * 0.9, 0.35, 1.0);

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, semantic_alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(density * 0.6, 0.0, 0.0, 0.0));
}