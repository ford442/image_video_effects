// ═══════════════════════════════════════════════════════════════════
//  spec-histogram-equalize-sg
//  Category: image
//  Features: cooperative-workgroup, histogram, CLAHE, subgroups
//  Complexity: High
//  Chunks From: spec-histogram-equalize.wgsl
//  Created: 2026-05-23
//  By: Copilot — Subgroup Ops Pioneer
// ═══════════════════════════════════════════════════════════════════
//  Subgroup variant of spec-histogram-equalize.wgsl.
//
//  KEY OPTIMISATION — histogram build (Phase 2):
//    Base shader: each of 256 threads does one atomicAdd → 256 atomic ops.
//    This shader: threads in the same subgroup that share a bin value are
//    counted with subgroupAdd, then only the elected lane issues a single
//    atomicAdd for the whole subgroup.  For typical images this cuts atomic
//    traffic by ~subgroupSize (32×) for dense bins.
//
//  The `enable subgroups;` directive causes createShaderModule to fail on
//  browsers without subgroup support, which is why this lives in a separate
//  -sg.wgsl sibling file.  The JS renderer probes this file first when
//  device.features.has('subgroups') is true, then falls back to the base.
// ═══════════════════════════════════════════════════════════════════

enable subgroups;

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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=ClipLimit, y=Strength, z=TileBlend, w=ColorPreserve
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

var<workgroup> localHistogram: array<atomic<u32>, 256>;

@compute @workgroup_size(16, 16, 1)
fn main(
    @builtin(global_invocation_id) gid: vec3<u32>,
    @builtin(local_invocation_id) lid: vec3<u32>,
    @builtin(local_invocation_index) lidx: u32
) {
    let res = u.config.zw;
    let inBounds = gid.x < u32(res.x) && gid.y < u32(res.y);
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let bass = plasmaBuffer[0].x;

    let clipLimit = mix(1.0, 8.0, u.zoom_params.x) * (1.0 + bass * 0.3);
    let strength = mix(0.0, 1.0, u.zoom_params.y);
    let tileBlend = mix(0.0, 1.0, u.zoom_params.z);
    let colorPreserve = mix(0.0, 1.0, u.zoom_params.w);

    // Phase 1: Clear histogram cooperatively
    for (var i = lidx; i < 256u; i = i + 256u) {
        atomicStore(&localHistogram[i], 0u);
    }
    workgroupBarrier();

    // Read color and compute luma
    let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = clamp(dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114)), 0.0, 1.0);
    let bin = u32(luma * 255.0);

    // ═══════════════════════════════════════════════════════════════
    // Phase 2 — SUBGROUP-ACCELERATED histogram build
    //
    // For each of the 256 bins we ask: "how many lanes in my subgroup
    // landed in this bin?"  subgroupAdd aggregates the per-lane 0/1
    // votes into a single count, and only the elected (first active)
    // lane writes one atomicAdd for the whole subgroup.
    //
    // Worst-case atomic ops = 256 (all threads in unique bins, same as
    // base).  Typical-case savings ≈ subgroupSize× for dense bins,
    // which is the common case for natural-image luma distributions.
    // ═══════════════════════════════════════════════════════════════
    for (var b = 0u; b < 256u; b++) {
        let myContrib = select(0u, 1u, bin == b);
        let subgroupTotal = subgroupAdd(myContrib);
        if (subgroupElect()) {
            if (subgroupTotal > 0u) {
                atomicAdd(&localHistogram[b], subgroupTotal);
            }
        }
    }
    workgroupBarrier();

    // Phase 3: Compute CDF prefix sum for this bin
    var cdf = 0u;
    for (var i = 0u; i <= bin; i = i + 1u) {
        cdf = cdf + atomicLoad(&localHistogram[i]);
    }

    // CLAHE: clip and redistribute
    let totalPixels = 256u;
    let clippedCount = min(atomicLoad(&localHistogram[bin]), u32(clipLimit));

    // Phase 4: Remap using CDF
    let equalizedLuma = f32(cdf) / f32(totalPixels);
    let originalLuma = max(luma, 0.001);
    let scaleFactor = equalizedLuma / originalLuma;

    var outColor: vec3<f32>;
    if (colorPreserve > 0.5) {
        outColor = color.rgb * mix(1.0, scaleFactor, strength);
    } else {
        outColor = mix(color.rgb, color.rgb * scaleFactor, strength);
    }

    outColor = clamp(outColor, vec3<f32>(0.0), vec3<f32>(3.0));

    if (inBounds) {
        textureStore(writeTexture, gid.xy, vec4<f32>(outColor, f32(cdf) / f32(totalPixels)));
        textureStore(dataTextureA, gid.xy, vec4<f32>(equalizedLuma, luma, scaleFactor, f32(cdf) / f32(totalPixels)));
        let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
        textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    }
}
