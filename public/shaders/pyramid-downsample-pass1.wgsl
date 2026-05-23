// ═══════════════════════════════════════════════════════════════════════════
//  Gaussian-Laplacian Pyramid — Pass 1: Separable Gaussian Downsample
//  Category: image
//  Features: multi-pass-1, shared-memory, gaussian-blur, temporal-feedback
//  Complexity: Medium
//  Part of chain: pyramid-downsample-pass1 → pyramid-bandprocess-pass2 → pyramid-composite-pass3
//
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
  config:      vec4<f32>,   // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,   // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,   // x=HighFreqAmp, y=MidFreqAmp, z=LowFreqAmp, w=ROIRadius
  ripples:     array<vec4<f32>, 50>,
};

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
const K2: f32 = 0.0625;  // ±2 neighbour weight  (clamped to ±1 in shared tile)

// Load one vec3 pixel from readTexture using integer coords (fast path).
fn loadPixelRGB(coord: vec2<i32>) -> vec3<f32> {
  let dims = vec2<i32>(textureDimensions(readTexture, 0));
  let c = clamp(coord, vec2<i32>(0), dims - vec2<i32>(1));
  return textureLoad(readTexture, c, 0).rgb;
}

// Fill the 18×18 shared tile cooperatively.
// Each of the 256 threads loads its own texel plus any needed halo pixels.
fn fillTile(gid: vec3<u32>, lid: vec3<u32>) {
  // Pixel coordinate of top-left corner of the 16×16 block (pre-halo).
  let base = vec2<i32>(gid.xy) - vec2<i32>(i32(HALO));

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

// 3×3 separable Gaussian blur from shared tile (radius-1 per axis).
// X-pass: K1*left + K0*centre + K1*right (then repeat Y).
// Equivalent to a 3×3 tent filter, which is a good approximation to a 2D Gaussian.
fn gaussBlur(lid: vec3<u32>) -> vec3<f32> {
  // Row blur (X direction): 3 taps per row, 3 rows
  let r0 = K1 * tileAt(lid, -1, -1) + K0 * tileAt(lid, 0, -1) + K1 * tileAt(lid, 1, -1);
  let r1 = K1 * tileAt(lid, -1,  0) + K0 * tileAt(lid, 0,  0) + K1 * tileAt(lid, 1,  0);
  let r2 = K1 * tileAt(lid, -1,  1) + K0 * tileAt(lid, 0,  1) + K1 * tileAt(lid, 1,  1);
  // Column blur (Y direction) over the 3 row results
  let blur = K1 * r0 + K0 * r1 + K1 * r2;
  // Re-normalize (sum of weights in 2D: (K1+K0+K1)^2 = (0.875)^2 ≈ 0.766)
  return blur / ((K1 + K0 + K1) * (K1 + K0 + K1));
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

  // ── Step 1: Cooperatively fill the shared-memory tile ──────────────────
  fillTile(gid, lid);

  if (!inBounds) { return; }

  // ── Step 2: Compute separable Gaussian blur from the tile ──────────────
  let blurRGB = gaussBlur(lid);

  // ── Step 3: Write outputs ───────────────────────────────────────────────
  // dataTextureB stores the Gaussian blur for temporal reference.
  // The renderer's post-slot copy (dataTexB → dataTexC) makes the blur
  // available as dataTextureC in the NEXT frame for pass 2 and pass 3.
  textureStore(dataTextureB, gid.xy, vec4<f32>(blurRGB, 1.0));

  // Pass the original image through writeTexture so the slot pipeline
  // has a valid image even if the chain does not run to completion.
  let origRGB = tileAt(lid, 0, 0);
  textureStore(writeTexture, gid.xy, vec4<f32>(origRGB, 1.0));
}
