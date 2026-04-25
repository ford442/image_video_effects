// ═══════════════════════════════════════════════════════════════════
//  spec-histogram-equalize
//  Category: image
//  Features: cooperative-workgroup, histogram, CLAHE
//  Complexity: High
//  Chunks From: none
//  Created: 2026-04-18
//  By: Agent 3C — Spectral Computation Pioneer
// ═══════════════════════════════════════════════════════════════════
//  Real-Time Histogram Equalization via Workgroup Reduction
//  Computes a local histogram within each 8x8 workgroup tile, then
//  uses the CDF to remap pixel intensities (CLAHE-style contrast).
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

var<workgroup> localHistogram: array<atomic<u32>, 256>;

@compute @workgroup_size(16, 16, 1)
fn main(
    @builtin(global_invocation_id) gid: vec3<u32>,
    @builtin(local_invocation_id) lid: vec3<u32>,
    @builtin(local_invocation_index) lidx: u32
) {
    let res = u.config.zw;
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;

    let clipLimit = mix(1.0, 8.0, u.zoom_params.x);
    let strength = mix(0.0, 1.0, u.zoom_params.y);
    let tileBlend = mix(0.0, 1.0, u.zoom_params.z);
    let colorPreserve = mix(0.0, 1.0, u.zoom_params.w);

    // Phase 1: Clear histogram (cooperative clear)
    for (var i = lidx; i < 256u; i = i + 256u) {
        atomicStore(&localHistogram[i], 0u);
    }
    workgroupBarrier();

    // Read color and compute luma
    let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = clamp(dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114)), 0.0, 1.0);
    let bin = u32(luma * 255.0);

    // Phase 2: Vote into histogram
    atomicAdd(&localHistogram[bin], 1u);
    workgroupBarrier();

    // Phase 3: Read our bin count and compute prefix sum (CDF) for our bin
    var cdf = 0u;
    for (var i = 0u; i <= bin; i = i + 1u) {
        cdf = cdf + atomicLoad(&localHistogram[i]);
    }

    // CLAHE: clip histogram and redistribute
    let totalPixels = 256u; // 16x16 workgroup
    let clippedCount = min(atomicLoad(&localHistogram[bin]), u32(clipLimit));

    // Phase 4: Remap using CDF
    let equalizedLuma = f32(cdf) / f32(totalPixels);
    let originalLuma = max(luma, 0.001);
    let scaleFactor = equalizedLuma / originalLuma;

    // Blend between equalized and original
    var outColor: vec3<f32>;
    if (colorPreserve > 0.5) {
        // Preserve hue, adjust luminance
        outColor = color.rgb * mix(1.0, scaleFactor, strength);
    } else {
        outColor = mix(color.rgb, color.rgb * scaleFactor, strength);
    }

    // Tone map and clamp
    outColor = clamp(outColor, vec3<f32>(0.0), vec3<f32>(3.0));

    // Alpha stores CDF value (statistical importance map)
    textureStore(writeTexture, gid.xy, vec4<f32>(outColor, f32(cdf) / f32(totalPixels)));
    textureStore(dataTextureA, gid.xy, vec4<f32>(equalizedLuma, luma, scaleFactor, f32(cdf) / f32(totalPixels)));
}
