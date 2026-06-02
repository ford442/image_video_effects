// ═══════════════════════════════════════════════════════════════════
//  Anaglyph 3D
//  Category: image
//  Features: depth-aware, upgraded-rgba, red-cyan, stereoscopic, audio-reactive,
//            temporal-ghosting, chromatic-separation, mouse-focal-depth
//  Complexity: Medium
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let separation = u.zoom_params.x * 0.04 * (1.0 + bass * 0.15);
    let depthCurve = u.zoom_params.y;
    let ghostAmount = u.zoom_params.z;
    let grainAmount = u.zoom_params.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let mouse = u.zoom_config.yz;
    let mouseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, mouse, 0.0).r;

    // Mouse focal depth curve refinement
    let focalDepth = mix(mouseDepth, 0.5, 0.3);
    let depthOffset = depthCurve * (depth - focalDepth) * 2.0;
    let shift = separation * depthOffset;

    let rUV = clamp(uv + vec2<f32>(shift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let cUV = clamp(uv - vec2<f32>(shift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

    var color = vec3<f32>(0.0);
    color.r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    color.g = textureSampleLevel(readTexture, u_sampler, cUV, 0.0).g;
    color.b = textureSampleLevel(readTexture, u_sampler, cUV, 0.0).b;

    // Ghost fringing: R/C offset residual trails
    let ghostShift = separation * depthOffset * 0.5;
    let ghostR = textureSampleLevel(readTexture, u_sampler, clamp(rUV + vec2<f32>(ghostShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r * 0.5;
    let ghostC = textureSampleLevel(readTexture, u_sampler, clamp(cUV - vec2<f32>(ghostShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g * 0.5;
    color.r = color.r + ghostR * ghostAmount;
    color.g = color.g + ghostC * ghostAmount;

    // Chromatic separation enhancement per depth
    let chromaBoost = smoothstep(0.0, 1.0, abs(depth - focalDepth)) * treble * 0.2;
    color.r = color.r * (1.0 + chromaBoost);
    color.g = color.g * (1.0 - chromaBoost * 0.3);
    color.b = color.b * (1.0 - chromaBoost * 0.1);

    let grain = fract(sin(dot(uv * time * 0.01, vec2<f32>(12.9898, 78.233))) * 43758.5453) - 0.5;
    color = color + grain * grainAmount * 0.1;

    // Temporal ghost persistence
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    color = mix(color, prev * 0.9, 0.04 + mids * 0.01);

    let baseAlpha = textureSampleLevel(readTexture, u_sampler, uv, 0.0).a;
    let finalAlpha = mix(baseAlpha, 1.0, separation * 0.3);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, finalAlpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(color, finalAlpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0, 0, 1));
}
