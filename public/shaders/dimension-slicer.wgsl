// ═══════════════════════════════════════════════════════════════════
//  Dimension Slicer
//  Category: image
//  Features: upgraded-rgba, audio-reactive, chromatic-aberration, depth-aware,
//            temporal-slice-rotation, chromatic-slice-dispersion, audio-slice-width
//  Complexity: High
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

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

fn rot2D(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let sliceAngle = u.zoom_params.x * PI * 2.0;
    let zoomWarp = u.zoom_params.y * 2.0;
    let chromaticAmount = u.zoom_params.z;
    let depthModulation = u.zoom_params.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Temporal slice rotation memory: angle drifts slowly
    let driftedAngle = sliceAngle + time * 0.3;

    let p = uv - vec2<f32>(0.5);
    let rotP = rot2D(driftedAngle) * p;
    let sliceDist = rotP.y;

    // Audio-driven slice width modulation
    let sliceWidth = 0.04 + bass * 0.02;
    let inSlice = smoothstep(sliceWidth, sliceWidth * 0.5, abs(sliceDist));

    let slicePos = rotP.x / max(abs(rotP.y), 1e-4);
    let zoomedSlice = slicePos * zoomWarp * (1.0 + depth * depthModulation);

    // Chromatic inside-slice dispersion
    let chromaShift = chromaticAmount * 0.015 * (1.0 + treble * 0.3);
    var rUV = vec2<f32>(zoomedSlice + chromaShift, rotP.y);
    var gUV = vec2<f32>(zoomedSlice, rotP.y);
    var bUV = vec2<f32>(zoomedSlice - chromaShift, rotP.y);

    rUV = rot2D(-driftedAngle) * rUV + vec2<f32>(0.5);
    gUV = rot2D(-driftedAngle) * gUV + vec2<f32>(0.5);
    bUV = rot2D(-driftedAngle) * bUV + vec2<f32>(0.5);

    var color = vec3<f32>(0.0);
    color.r = textureSampleLevel(readTexture, u_sampler, clamp(rUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    color.g = textureSampleLevel(readTexture, u_sampler, clamp(gUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    color.b = textureSampleLevel(readTexture, u_sampler, clamp(bUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

    let edgeGlow = smoothstep(0.02, 0.0, abs(sliceDist)) * inSlice;
    let edgeColor = vec3<f32>(1.0, 0.8, 0.5) * (1.0 + bass * 0.3);
    color = mix(color, edgeColor, edgeGlow);

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    color = mix(baseColor.rgb, color, inSlice);

    let finalAlpha = mix(baseColor.a, 1.0, inSlice * 0.5 + edgeGlow * 0.3);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, finalAlpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(color, finalAlpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0, 0, 1));
}
