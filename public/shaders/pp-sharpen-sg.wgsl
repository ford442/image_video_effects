// ═══════════════════════════════════════════════════════════════════
//  pp-sharpen-sg
//  Category: post-processing
//  Features: sharpening, subgroups, shared-memory, edge-enhancement
//  Complexity: Medium
//  Chunks From: pp-sharpen.wgsl
//  Created: 2026-05-23
//  By: Copilot — Subgroup Ops Pioneer
// ═══════════════════════════════════════════════════════════════════
//  Subgroup + shared-memory variant of pp-sharpen.wgsl.
//
//  OPTIMISATION STRATEGY
//  ─────────────────────
//  Base shader (pp-sharpen.wgsl): blur3x3 issues 9 textureSampleLevel
//  calls per thread (8 neighbours + centre).
//
//  This shader uses two complementary techniques to reduce that to ~2:
//
//  A) var<workgroup> sharedLuma  (18×18 NOT needed here; 16×16 suffices
//     for the vertical 3-tap because we only need ±1 row of the *current*
//     tile, which is always present in the same workgroup).
//
//     Each thread loads its centre luminance into shared memory once, then
//     reads sharedLuma[lid.y±1][lid.x] for the up/down neighbours.  This
//     eliminates 2 texture samples for ≈87% of threads (all except top/
//     bottom rows of the tile).
//
//  B) subgroupShuffleUp/Down(val, 1)  for left/right neighbours.
//     Within a 16-wide row the WGSL local_invocation_index stride is 1,
//     and all known WebGPU implementations assign subgroup lanes in
//     local_invocation_index order within a workgroup.  On hardware that
//     exposes the `subgroups` feature this is therefore reliable in
//     practice, though the WGSL spec does not formally guarantee it.
//     At horizontal tile borders (lid.x == 0 or 15) we fall back to a
//     texture sample; these account for 2/16 ≈ 12.5% of threads.
//
//  Net average texture samples per thread (interior 14×14 block):
//    Base  : ~9 (full 3×3 blur neighbourhood)
//    -sg   : ~1.25 (1 centre + 0 V-reads from shared + ≤0.25 H-fallbacks)
//
//  The `enable subgroups;` directive makes this module fail compilation
//  on browsers without subgroup support.  The renderer probes this file
//  first and falls back to pp-sharpen.wgsl transparently.
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
  zoom_params: vec4<f32>,  // x=Strength, y=HaloControl, z=EdgeBoost, w=ColorPreserve
  ripples: array<vec4<f32>, 50>,
};

const LUMA_WEIGHT: vec3<f32> = vec3<f32>(0.299, 0.587, 0.114);
const TILE_W: u32 = 16u;
const TILE_H: u32 = 16u;

// ── Shared memory ─────────────────────────────────────────────────
// 16×16 luminance tile.  Each thread writes its own luma, then reads
// neighbours from adjacent rows after the workgroupBarrier.
var<workgroup> sharedLuma: array<f32, 256>;  // TILE_W * TILE_H

@compute @workgroup_size(16, 16, 1)
fn main(
    @builtin(global_invocation_id) gid: vec3<u32>,
    @builtin(local_invocation_id)  lid: vec3<u32>,
    @builtin(local_invocation_index) lidx: u32,
) {
    let res    = u.config.zw;
    let invRes = 1.0 / res;
    let uv     = (vec2<f32>(gid.xy) + 0.5) / res;

    let inBounds = gid.x < u32(res.x) && gid.y < u32(res.y);

    let strength     = mix(0.0, 2.0, u.zoom_params.x);
    let haloControl  = mix(0.0, 1.0, u.zoom_params.y);
    let edgeBoost    = mix(0.0, 1.0, u.zoom_params.z);
    let colorPreserve = u.zoom_params.w;

    // ── 1. Load centre pixel (1 texture sample per thread) ──────────────────
    let center    = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let centerLum = dot(center.rgb, LUMA_WEIGHT);

    // ── 2. Write luminance into shared memory for cross-row reads ────────────
    sharedLuma[lidx] = centerLum;
    workgroupBarrier();

    // ── 3. Vertical neighbours from shared memory (0 extra texture samples
    //       for interior rows; 1 texture sample only at tile top/bottom) ──────
    //
    //  Safe index: when lid.y == 0, upIdx == lidx (reads the centre itself,
    //  result is then overridden by the fallback texture sample via select).
    let upIdx = select(lidx, lidx - TILE_W, lid.y > 0u);
    let dnIdx = select(lidx, lidx + TILE_W, lid.y < TILE_H - 1u);
    let lum_u_sm = sharedLuma[upIdx];
    let lum_d_sm = sharedLuma[dnIdx];

    var lum_u: f32;
    var lum_d: f32;
    if (lid.y == 0u) {
        lum_u = dot(textureSampleLevel(readTexture, u_sampler,
            uv - vec2<f32>(0.0, invRes.y), 0.0).rgb, LUMA_WEIGHT);
    } else {
        lum_u = lum_u_sm;
    }
    if (lid.y == TILE_H - 1u) {
        lum_d = dot(textureSampleLevel(readTexture, u_sampler,
            uv + vec2<f32>(0.0, invRes.y), 0.0).rgb, LUMA_WEIGHT);
    } else {
        lum_d = lum_d_sm;
    }

    // ── 4. Horizontal neighbours via subgroup shuffle (stride-1) ─────────────
    //
    //  subgroupShuffleUp(val, 1)   → value from lane (thisLane - 1)  i.e. left
    //  subgroupShuffleDown(val, 1) → value from lane (thisLane + 1)  i.e. right
    //
    //  This relies on the de-facto mapping where subgroup lane N corresponds to
    //  local_invocation_index N within each workgroup — true for all known
    //  WebGPU implementations on hardware that exposes the 'subgroups' feature.
    //  At tile borders the shuffle result is undefined; we replace it with a
    //  regular texture sample (≈12.5% of threads).
    let lum_l_shuf = subgroupShuffleUp  (centerLum, 1u);
    let lum_r_shuf = subgroupShuffleDown(centerLum, 1u);

    var lum_l: f32;
    var lum_r: f32;
    if (lid.x == 0u) {
        lum_l = dot(textureSampleLevel(readTexture, u_sampler,
            uv - vec2<f32>(invRes.x, 0.0), 0.0).rgb, LUMA_WEIGHT);
    } else {
        lum_l = lum_l_shuf;
    }
    if (lid.x == TILE_W - 1u) {
        lum_r = dot(textureSampleLevel(readTexture, u_sampler,
            uv + vec2<f32>(invRes.x, 0.0), 0.0).rgb, LUMA_WEIGHT);
    } else {
        lum_r = lum_r_shuf;
    }

    // ── 5. 5-point Laplacian ─────────────────────────────────────────────────
    let laplacian = lum_l + lum_r + lum_u + lum_d - 4.0 * centerLum;

    // ── 6. Unsharp mask with halo control ────────────────────────────────────
    let rawBoost  = -laplacian * strength;
    // haloControl > 0.5 suppresses negative overshoots that create bright haloes
    let safeBoost = select(rawBoost, max(rawBoost, 0.0), haloControl > 0.5 && laplacian < 0.0);

    // ── 7. Apply to colour channels ──────────────────────────────────────────
    var outColor: vec3<f32>;
    if (colorPreserve > 0.5) {
        let newLum   = clamp(centerLum + safeBoost, 0.0, 1.0);
        let lumRatio = select(1.0, newLum / max(centerLum, 0.001), centerLum > 0.001);
        outColor = center.rgb * lumRatio;
    } else {
        outColor = center.rgb + safeBoost;
    }

    let edgeMag = abs(laplacian) * edgeBoost;
    outColor   += vec3<f32>(edgeMag);
    outColor    = clamp(outColor, vec3<f32>(0.0), vec3<f32>(1.0));

    if (inBounds) {
        textureStore(writeTexture, gid.xy, vec4<f32>(outColor, center.a));
        textureStore(dataTextureA, gid.xy, vec4<f32>(laplacian, centerLum, safeBoost, 1.0));
        let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
        textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    }
}
