// ═══════════════════════════════════════════════════════════════════
//  VHS Chroma Bleed
//  Category: image
//  Features: upgraded-rgba, temporal, glitch, retro
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

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn hash11(p: f32) -> f32 {
    return fract(sin(p * 12.9898) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.zw);
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let coords = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / res;
    let time = u.config.x;

    let chromaShift = u.zoom_params.x;
    let noiseIntensity = u.zoom_params.y;
    let jitterAmount = u.zoom_params.z;
    let bleedWidth = u.zoom_params.w;

    // Tracking jitter
    let jitterLine = hash11(floor(uv.y * 200.0) + floor(time * 12.0));
    let jitterOffset = select(0.0, (jitterLine - 0.5) * jitterAmount * 0.02, jitterLine < jitterAmount);
    let jitteredUV = vec2<f32>(uv.x + jitterOffset, uv.y);

    // Sample with horizontal chroma displacement
    let shift = chromaShift * 0.01 * bleedWidth;
    let rUV = jitteredUV + vec2<f32>(shift, 0.0);
    let gUV = jitteredUV;
    let bUV = jitteredUV - vec2<f32>(shift, 0.0);

    let r = textureSampleLevel(readTexture, u_sampler, clamp(rUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, clamp(gUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(bUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    let baseAlpha = textureSampleLevel(readTexture, u_sampler, jitteredUV, 0.0).a;

    var col = vec4<f32>(r, g, b, baseAlpha);

    // Luma noise in dark areas
    let luma = dot(col.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let darkMask = 1.0 - smoothstep(0.0, 0.3, luma);
    let noise = (hash21(uv * 400.0 + fract(time * 30.0) * 10.0) - 0.5) * noiseIntensity * darkMask;
    col = col + vec4<f32>(noise, noise, noise, 0.0);

    // Horizontal banding artifact
    let bandY = sin(uv.y * 300.0 + time * 2.0) * 0.5 + 0.5;
    let bandNoise = hash11(uv.y * 500.0 + time) * 0.03 * noiseIntensity;
    col = col * (1.0 - bandY * bandNoise);

    // Occasional color burst error
    let burstTrigger = hash11(floor(time * 4.0) + floor(uv.y * 50.0)) < 0.03;
    let burstColor = vec3<f32>(hash11(time), hash11(time + 1.0), hash11(time + 2.0)) * 0.15;
    col = vec4<f32>(select(col.rgb, col.rgb + burstColor, burstTrigger), col.a);

    col = clamp(col, vec4<f32>(0.0), vec4<f32>(1.0));

    textureStore(writeTexture, coords, col);
}
