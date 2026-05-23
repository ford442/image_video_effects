// ═══════════════════════════════════════════════════════════════════
//  Posterize Neon Edges
//  Category: image
//  Features: upgraded-rgba, edge-detect, neon
//  Complexity: Medium
//  Created: 2026-05-23
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.zw);
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let coords = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / res;
    let texel = 1.0 / res;

    let levels = u.zoom_params.x;
    let edgeThreshold = u.zoom_params.y;
    let glowIntensity = u.zoom_params.z;
    let hueShift = u.zoom_params.w;

    // Sample neighbors for Sobel edge detection
    let tl = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x,  texel.y), 0.0).rgb;
    let tm = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( 0.0,       texel.y), 0.0).rgb;
    let tr = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( texel.x,  texel.y), 0.0).rgb;
    let ml = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x,  0.0),      0.0).rgb;
    let mc = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let mr = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( texel.x,  0.0),      0.0).rgb;
    let bl = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x, -texel.y), 0.0).rgb;
    let bm = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( 0.0,      -texel.y), 0.0).rgb;
    let br = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( texel.x, -texel.y), 0.0).rgb;

    let baseAlpha = textureSampleLevel(readTexture, u_sampler, uv, 0.0).a;

    // Sobel gradients
    let gx = (tl + 2.0 * ml + bl) - (tr + 2.0 * mr + br);
    let gy = (tl + 2.0 * tm + tr) - (bl + 2.0 * bm + br);
    let edgeMag = length(gx) + length(gy);

    // Posterize main color
    let quantize = max(levels, 2.0);
    var col = floor(mc * quantize) / quantize;

    // Neon edge glow
    let edgeMask = smoothstep(edgeThreshold * 0.5, edgeThreshold, edgeMag);
    let neonHue = fract(hueShift * 0.1 + edgeMag * 0.5);
    let neonColor = vec3<f32>(
        abs(sin(neonHue * 6.28318)),
        abs(sin((neonHue + 0.333) * 6.28318)),
        abs(sin((neonHue + 0.666) * 6.28318))
    );
    col = mix(col, neonColor * 1.5, edgeMask * glowIntensity);

    // Inner glow on bright areas
    let bright = smoothstep(0.5, 1.0, dot(mc, vec3<f32>(0.299, 0.587, 0.114)));
    col = col + neonColor * bright * edgeMask * glowIntensity * 0.3;

    let finalColor = vec4<f32>(clamp(col, vec3<f32>(0.0), vec3<f32>(1.0)), baseAlpha);

    textureStore(writeTexture, coords, finalColor);
}
