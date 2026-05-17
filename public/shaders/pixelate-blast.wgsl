// ═══════════════════════════════════════════════════════════════════
//  Pixelate Blast
//  Category: retro-glitch
//  Features: mouse-driven, audio-reactive
//  Complexity: Medium
//  Chunks From: pixelate-blast (original)
//  Created: 2026-05-17
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
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz;
    let time = u.config.x;
    let minPixelSize = 1.0;
    var maxPixelSize = 50.0 + u.zoom_params.x * 100.0;
    let radius = 0.5 + u.zoom_params.y * 0.5;
    let invert = u.zoom_params.z;
    let colorCrunch = u.zoom_params.w;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    maxPixelSize += bass * 20.0;
    let aspect = resolution.x / resolution.y;
    let dVec = uv - mouse;
    let mouseDist = length(vec2<f32>(dVec.x * aspect, dVec.y));
    let centerDist = length(uv - vec2<f32>(0.5));
    var dist = select(centerDist, mouseDist, mouse.x >= 0.0);
    let rippleCount = u32(u.config.y);
    var rippleBoost = 0.0;
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let r = u.ripples[i];
        let rd = length((uv - r.xy) * vec2<f32>(aspect, 1.0));
        let re = time - r.z;
        rippleBoost += smoothstep(0.3, 0.0, rd) * exp(-re * 2.0) * 0.5;
    }
    dist = max(0.0, dist - rippleBoost * 0.1);
    let audioRadius = radius + mids * 0.15;
    var t = smoothstep(0.0, audioRadius, dist);
    t = mix(1.0 - t, t, step(0.5, invert));
    let shockwave = step(0.5, u.zoom_config.w) * 0.5;
    t = min(1.0, t + shockwave);
    let pixelSize = mix(minPixelSize, maxPixelSize, t);
    let blocks = resolution / pixelSize;
    let blockUV = floor(uv * blocks) / blocks;
    let centerUV = blockUV + (0.5 / blocks);
    var color = textureSampleLevel(readTexture, u_sampler, centerUV, 0.0);
    let crunchFactor = step(0.1, colorCrunch);
    let steps = 4.0 + (1.0 - colorCrunch) * 20.0;
    color = mix(color, floor(color * steps) / steps, crunchFactor);
    let edgeDist = abs(fract(uv * blocks) - 0.5) * 2.0;
    let ca = max(edgeDist.x, edgeDist.y) * 0.02;
    color.r = textureSampleLevel(readTexture, u_sampler, centerUV + vec2<f32>(ca, 0.0), 0.0).r;
    color.b = textureSampleLevel(readTexture, u_sampler, centerUV - vec2<f32>(ca, 0.0), 0.0).b;
    let scanline = 1.0 - 0.04 * step(0.5, fract(floor(f32(global_id.y) / pixelSize) * 0.5));
    let vignette = 1.0 - 0.12 * t * smoothstep(0.3, 0.9, length(uv - 0.5));
    color = vec4<f32>(color.rgb * vignette * scanline, color.a);
    color.a = mix(color.a, color.a * 0.9, t);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, vec2<i32>(global_id.xy), color);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), color);
}
