// ═══════════════════════════════════════════════════════════════════════════
//  Gaussian-Laplacian Pyramid — Pass 1: Bilateral Gaussian Base
//  Category: image
//  Features: multi-pass-1, shared-memory, gaussian-blur, temporal-feedback, audio-reactive
//  Complexity: Medium
//  Upgraded: 2026-11-22
//  Ideas: bilateral range weight; low-band settle; Burt-Adelson 5-tap REDUCE kernel; beat-opened range sigma
//  A packing: B = (bilateral blur RGB, range agreement). Not display.
// ═══════════════════════════════════════════════════════════════════════════
//  This pass computes a bilateral Gaussian base of the input image using a
//  20×20 shared-memory tile (16×16 threads + 2-pixel halo on each side) so the
//  spatial kernel can be the true pyramid REDUCE kernel (Burt–Adelson, a = 0.4).
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
const HALO:    u32 = 2u;
const PADDED:  u32 = 20u;   // TILE_W + 2*HALO

var<workgroup> tile: array<array<vec3<f32>, 20>, 20>;  // [row][col]

// ─── Spatial kernel ──────────────────────────────────────────────────────────
// ── Idea 3: Burt–Adelson generating kernel ──────────────────────────────────
// The pyramid REDUCE kernel is the 5-tap [0.05 0.25 0.40 0.25 0.05] (a = 0.4).
// The old 3-tap binomial (0.25 / 0.375 / 0.25) is its radius-1 truncation.
// The 2D weight is the product of two taps; the bilateral range weight below
// multiplies it, and the sum is renormalised, so the base still collapses to a
// plain low-pass wherever every tap agrees.
fn reduceTap(d: i32) -> f32 {
  let a = abs(d);
  return select(select(0.05, 0.25, a == 1), 0.4, a == 0);
}

// Load one vec3 pixel from readTexture using integer coords (fast path).
fn loadPixelRGB(coord: vec2<i32>) -> vec3<f32> {
  let dims = vec2<i32>(textureDimensions(readTexture, 0));
  let c = clamp(coord, vec2<i32>(0), dims - vec2<i32>(1));
  return textureLoad(readTexture, c, 0).rgb;
}

// Fill the 20×20 shared tile cooperatively: 400 texels over 256 threads, each
// thread strides by the workgroup size. Every thread reaches the barrier.
fn fillTile(gid: vec3<u32>, lid: vec3<u32>) {
  let base = vec2<i32>(gid.xy - lid.xy) - vec2<i32>(i32(HALO));
  let flat = lid.y * TILE_W + lid.x;
  for (var i: u32 = flat; i < PADDED * PADDED; i = i + TILE_W * TILE_H) {
    let ty = i / PADDED;
    let tx = i % PADDED;
    tile[ty][tx] = loadPixelRGB(base + vec2<i32>(i32(tx), i32(ty)));
  }
  workgroupBarrier();
}

// Read from shared tile with local invocation coords (+halo offset).
fn tileAt(lid: vec3<u32>, dx: i32, dy: i32) -> vec3<f32> {
  let x = i32(lid.x) + dx + i32(HALO);
  let y = i32(lid.y) + dy + i32(HALO);
  return tile[clamp(y, 0, 19)][clamp(x, 0, 19)];
}

fn luma3(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// 5×5 Burt–Adelson blur with a luma range weight. When every tap agrees, the
// weights collapse to the plain separable REDUCE kernel.
fn bilateralBlur(lid: vec3<u32>, rangeSigma: f32) -> vec4<f32> {
  let center = tileAt(lid, 0, 0);
  let lc = luma3(center);
  let sig2 = max(rangeSigma * rangeSigma, 1e-4);
  var acc = vec3<f32>(0.0);
  var wsum = 0.0;
  var agree = 0.0;
  var spatialSum = 0.0;
  for (var dy: i32 = -2; dy <= 2; dy = dy + 1) {
    for (var dx: i32 = -2; dx <= 2; dx = dx + 1) {
      let tap = tileAt(lid, dx, dy);
      let spatial = reduceTap(dx) * reduceTap(dy);
      let lt = luma3(tap);
      let diff = lt - lc;
      let range = exp(-(diff * diff) / sig2);
      let w = spatial * range;
      acc = acc + tap * w;
      wsum = wsum + w;
      agree = agree + spatial * range;
      spatialSum = spatialSum + spatial;
    }
  }
  let rgb = acc / max(wsum, 1e-4);
  return vec4<f32>(rgb, clamp(agree / max(spatialSum, 1e-4), 0.0, 1.0));
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

  // Audio: bass only (plasmaBuffer[0].x), read once.
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);

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

  // Idea 1 (bilateral range weight) is kept; it now runs over the Idea 3 kernel.
  // ── Idea 4: beat-opened range sigma ─────────────────────────────────────
  // A bass hit relaxes the edge-stopping weight, so the base blurs across mid
  // edges and the Laplacian residual (neon edges in passes 2/3) flares.
  let rangeSigma = mix(0.42, 0.07, highAmp * 0.5) * (1.0 + bass * 0.6);
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
  // Passthrough keeps the photo's own alpha (HEAD wrote a constant 1.0).
  let srcA = textureLoad(readTexture, vec2<i32>(gid.xy), 0).a;
  textureStore(writeTexture, gid.xy, vec4<f32>(origRGB, srcA + chainKeep));
  let uv = vec2<f32>(gid.xy) / vec2<f32>(textureDimensions(readTexture));
  let depth_in = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth_in, 0.0, 0.0, 0.0));
}
