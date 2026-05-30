// ═══════════════════════════════════════════════════════════════════
//  Holographic Prism
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: holographic-prism
//  Upgraded: 2026-05-30
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
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let aspect = resolution.x / resolution.y;
    let facets = max(3.0, floor(u.zoom_params.x));
    let dispersion = u.zoom_params.y * 0.04;
    let rotation = u.zoom_params.z;
    let glitch = u.zoom_params.w;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    let center = vec2<f32>(0.5, 0.5) + (mouse - 0.5) * 0.14;
    let p = (uv - center) * vec2<f32>(aspect, 1.0);
    let dist = max(length(p), 0.001);
    let angle = atan2(p.y, p.x) + u.config.x * rotation * (1.0 + treble * 0.4);
    let facet = abs(fract(angle / 6.28318 * facets) - 0.5) * 2.0;
    let prismDir = vec2<f32>(cos(facet * 3.14159265), sin(facet * 3.14159265));
    let facetWarp = vec2<f32>(prismDir.x / aspect, prismDir.y) * (0.03 + bass * 0.02) / dist;
    let glitchJitter = vec2<f32>(
        sin(uv.y * 80.0 + u.config.x * (5.0 + treble * 8.0)),
        cos(uv.x * 90.0 + u.config.x * (4.0 + mids * 7.0))
    ) * glitch * 0.006;
    let baseUV = clamp(uv + facetWarp + glitchJitter, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
    let uvR = clamp(baseUV + vec2<f32>(dispersion, 0.0), vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
    let uvG = baseUV;
    let uvB = clamp(baseUV - vec2<f32>(dispersion, 0.0), vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));

    let sampled = vec3<f32>(
        textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r,
        textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g,
        textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b
    );
    let caustic = vec3<f32>(
        0.25 + facet * 0.75,
        0.4 + treble * 0.2,
        1.0 - facet * 0.18 + bass * 0.12
    ) * exp(-dist * (2.5 + mids * 2.0)) * (0.18 + bass * 0.12);
    let shardRing = smoothstep(0.08, 0.0, abs(dist - (0.18 + bass * 0.08)));
    let finalColor = sampled * (0.78 + caustic.b * 0.18) + caustic + vec3<f32>(1.0, 0.9, 0.4) * shardRing * 0.15;
    let alpha = clamp(0.1 + caustic.b * 0.25 + shardRing * 0.2 + bass * 0.05, 0.08, 1.0);
    let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, baseUV, 0.0).r + shardRing * 0.05, 0.0, 1.0);
    let finalPixel = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalPixel);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(facet, shardRing, dist, alpha));
}
