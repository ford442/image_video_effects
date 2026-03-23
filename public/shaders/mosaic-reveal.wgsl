// ═══════════════════════════════════════════════════════════════════
//  mosaic-reveal - Interactive mosaic reveal effect
//  Category: distortion
//  Features: upgraded-rgba, depth-aware, mosaic, interactive-reveal
//  Upgraded: 2026-03-22
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    
    let coord = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let aspectVec = vec2<f32>(aspect, 1.0);

    // Params
    let mosaicSize = mix(20.0, 200.0, u.zoom_params.x);
    let radius = u.zoom_params.y * 0.5;
    let softness = u.zoom_params.z;

    var mouse = u.zoom_config.yz;
    let dist = distance((uv - mouse) * aspectVec, vec2<f32>(0.0));

    // Calculate Mosaic UV
    let uvPix = floor(uv * mosaicSize) / mosaicSize;
    let uvCenter = uvPix + (0.5 / mosaicSize);

    // Sample Mosaic and Full Res
    let colMosaic = textureSampleLevel(readTexture, non_filtering_sampler, uvCenter, 0.0).rgb;
    let colFull = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Mask: 0 = Mosaic, 1 = Full
    let mask = 1.0 - smoothstep(radius, radius + 0.1 + softness * 0.2, dist);

    let color = mix(colMosaic, colFull, mask);

    // Calculate alpha based on mask transition and luminance
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let maskAlpha = mix(0.9, 1.0, mask);
    let alpha = mix(maskAlpha * 0.8, maskAlpha, luma);
    let finalAlpha = mix(alpha * 0.8, alpha, depth);

    textureStore(writeTexture, coord, vec4<f32>(color, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
