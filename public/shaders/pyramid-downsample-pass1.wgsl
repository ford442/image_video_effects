// ═══════════════════════════════════════════════════════════════════════════
//  Gaussian-Laplacian Pyramid — Pass 1: Bilateral Gaussian Base
//  Category: image
//  Features: multi-pass-1, shared-memory, gaussian-blur, temporal-feedback
//  Complexity: Medium
//  Upgraded: 2026-10-18
//  Ideas: bilateral range weight; low-band settle
//  A packing: B = (bilateral blur RGB, range agreement). Not display.
// ═══════════════════════════════════════════════════════════════════════════
//  This pass computes a separable 7-tap Gaussian blur of the input image using
//  an 18×18 shared-memory tile (16×16 threads + 1-pixel halo on each side).
//  The blurred image is stored in dataTextureB so that the post-slot copy
//  (dataTexB → dataTexC) makes it available as dataTextureC in the NEXT frame.
//  Passes 2 and 3 then read the previous-frame Gaussian blur from dataTextureC
//  to compute Laplacian (high-frequency) detail and apply per-band creative ops.
//
//  Uniforms used:
//    u.zoom_params.x = high-frequency band amplitude (pass 2 uses it)
//    u.zoom_params.y = mid-frequency band amplitude  (pass 2 uses it)
//    u.zoom_params.z = low-frequency band amplitude  (pass 2 uses it)
//    u.zoom_params.w = ROI radius (pass 3 uses it)
// ═══════════════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=HighFreqAmp, y=MidFreqAmp, z=LowFreqAmp, w=ROIRadius

// ─── Shared-memory tile setup ────────────────────────────────────────────────
// Workgroup: 16×16 threads processing a 16×16 block of output pixels.
// Tile pads with a 1-pixel halo on each side → 18×18 elements loaded once,
// then all 256 threads share the data without additional texture reads.
const TILE_W:  u32 = 16u;
const TILE_H:  u32 = 16u;
const HALO:    u32 = 1u;
const PADDED:  u32 = 18u;   // TILE_W + 2*HALO

var<workgroup> tile: array<array<vec3<f32>, 18>, 18>;  // [row][col]

// ─── Gaussian 7-tap kernel (σ ≈ 1.4, separable) ─────────────────────────────
// Coefficients sum to 1.0 after normalization.
// Applied separably: X-pass then Y-pass both use the shared tile,
// avoiding a second workgroupBarrier pass by using a 3-tap approximation
// in the second direction that fits within the 1-pixel halo.
//
// For a 1-halo tile we use a 3-tap kernel (radius 1) per direction,
// which approximates a σ≈0.85 Gaussian per axis.
// The combined 2D blur with two 3-tap passes gives a smooth low-pass.
const K0: f32 = 0.375;   // centre weight
const K1: f32 = 0.25;    // ±1 neighbour weight
// 2D binomial weights. Centre K0, neighbour K1. Their product is the
// old separable kernel when the range weight is 1.

// Load one vec3 pixel from readTexture using integer coords (fast path).
fn loadPixelRGB(coord: vec2<i32>) -> vec3<f32> {
  let dims = vec2<i32>(textureDimensions(readTexture, 0));
  let c = clamp(coord, vec2<i32>(0), dims - vec2<i32>(1));
  return textureLoad(readTexture, c, 0).rgb;
}

// Fill the 18×18 shared tile cooperatively.
// Each of the 256 threads loads its own texel plus any needed halo pixels.
fn fillTile(gid: vec3<u32>, lid: vec3<u32>) {
  // Pixel coordinate of the top-left corner of this workgroup's 16×16 block,
  // offset by HALO so the tile covers a 1-pixel border on every side.
  // Using (gid.xy - lid.xy) gives the workgroup origin so all 256 threads
  // share exactly the same base and cooperate on ONE 18×18 tile.
  let base = vec2<i32>(gid.xy - lid.xy) - vec2<i32>(i32(HALO), i32(HALO));

  // Centre texel for this thread (at tile[lid.y+1][lid.x+1]).
  tile[lid.y + HALO][lid.x + HALO] = loadPixelRGB(base + vec2<i32>(lid.xy));

  // Right column halo.
  if (lid.x == TILE_W - 1u) {
    tile[lid.y + HALO][TILE_W + HALO] = loadPixelRGB(base + vec2<i32>(i32(TILE_W), i32(lid.y)));
  }
  // Bottom row halo.
  if (lid.y == TILE_H - 1u) {
    tile[TILE_H + HALO][lid.x + HALO] = loadPixelRGB(base + vec2<i32>(i32(lid.x), i32(TILE_H)));
  }
  // Bottom-right corner.
  if (lid.x == TILE_W - 1u && lid.y == TILE_H - 1u) {
    tile[TILE_H + HALO][TILE_W + HALO] = loadPixelRGB(base + vec2<i32>(i32(TILE_W), i32(TILE_H)));
  }
  // Left column halo.
  if (lid.x == 0u) {
    tile[lid.y + HALO][0u] = loadPixelRGB(base + vec2<i32>(-1, i32(lid.y)));
  }
  // Top row halo.
  if (lid.y == 0u) {
    tile[0u][lid.x + HALO] = loadPixelRGB(base + vec2<i32>(i32(lid.x), -1));
  }
  // Top-left corner.
  if (lid.x == 0u && lid.y == 0u) {
    tile[0u][0u] = loadPixelRGB(base + vec2<i32>(-1, -1));
  }
  // Top-right corner.
  if (lid.x == TILE_W - 1u && lid.y == 0u) {
    tile[0u][TILE_W + HALO] = loadPixelRGB(base + vec2<i32>(i32(TILE_W), -1));
  }
  // Bottom-left corner.
  if (lid.x == 0u && lid.y == TILE_H - 1u) {
    tile[TILE_H + HALO][0u] = loadPixelRGB(base + vec2<i32>(-1, i32(TILE_H)));
  }

  workgroupBarrier();
}

// Read from shared tile with local invocation coords (+halo offset).
fn tileAt(lid: vec3<u32>, dx: i32, dy: i32) -> vec3<f32> {
  let x = i32(lid.x) + dx + i32(HALO);
  let y = i32(lid.y) + dy + i32(HALO);
  return tile[clamp(y, 0, 17)][clamp(x, 0, 17)];
}

fn luma3(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// 3×3 binomial blur with a luma range weight. When every tap agrees, the
// weights collapse to the old separable kernel.
fn bilateralBlur(lid: vec3<u32>, rangeSigma: f32) -> vec4<f32> {
  let center = tileAt(lid, 0, 0);
  let lc = luma3(center);
  let sig2 = max(rangeSigma * rangeSigma, 1e-4);
  var acc = vec3<f32>(0.0);
  var wsum = 0.0;
  var agree = 0.0;
  for (var dy: i32 = -1; dy <= 1; dy = dy + 1) {
    for (var dx: i32 = -1; dx <= 1; dx = dx + 1) {
      let tap = tileAt(lid, dx, dy);
      let wx = select(K1, K0, dx == 0);
      let wy = select(K1, K0, dy == 0);
      let spatial = wx * wy;
      let lt = luma3(tap);
      let diff = lt - lc;
      let range = exp(-(diff * diff) / sig2);
      let w = spatial * range;
      acc = acc + tap * w;
      wsum = wsum + w;
      agree = agree + range;
    }
  }
  let rgb = acc / max(wsum, 1e-4);
  return vec4<f32>(rgb, clamp(agree / 9.0, 0.0, 1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(
  @builtin(global_invocation_id) gid: vec3<u32>,
  @builtin(local_invocation_id)  lid: vec3<u32>
) {
  let resolution = u.config.zw;
  let resU = vec2<u32>(u32(resolution.x), u32(resolution.y));

  // Bounds check — pad-threads outside the image do nothing but must
  // participate in the workgroupBarrier and tile fill.
  let inBounds = gid.x < resU.x && gid.y < resU.y;

  // High Freq Amp tightens the range weight. Mid stays with pass 2.
  // Low Freq Amp is the base's temporal inertia. ROI radius is pass 3.
  let highAmp = clamp(u.zoom_params.x, 0.0, 2.0);
  let midAmp = u.zoom_params.y;
  let lowAmp = clamp(u.zoom_params.z, 0.0, 2.0);
  let roiRadius = u.zoom_params.w;
  let chainKeep = (midAmp + roiRadius) * 0.0;

  // ── Step 1: Cooperatively fill the shared-memory tile ──────────────────
  fillTile(gid, lid);

  if (!inBounds) { return; }

  // ── Idea 1: bilateral range weight ──────────────────────────────────
  let rangeSigma = mix(0.42, 0.07, highAmp * 0.5);
  let blur = bilateralBlur(lid, rangeSigma);

  // ── Idea 2: low-band settle ─────────────────────────────────────────
  // The base eases toward last frame's blur so the Laplacian does not
  // tick. A black history (first frame) is ignored.
  let prevBlur = textureLoad(dataTextureC, vec2<i32>(gid.xy), 0).rgb;
  let prevOk = f32(dot(prevBlur, prevBlur) > 1e-4);
  let settle = (0.12 + 0.38 * (lowAmp * 0.5)) * prevOk;
  let blurRGB = mix(blur.rgb, prevBlur, settle);

  textureStore(dataTextureB, gid.xy, vec4<f32>(blurRGB, blur.a));

  let origRGB = tileAt(lid, 0, 0);
  textureStore(writeTexture, gid.xy, vec4<f32>(origRGB, 1.0 + chainKeep));
  let uv = vec2<f32>(gid.xy) / vec2<f32>(textureDimensions(readTexture));
  let depth_in = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth_in, 0.0, 0.0, 0.0));
}
