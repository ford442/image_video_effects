// ═══════════════════════════════════════════════════════════════════
//  _std/_std_sample.wgsl — textureLoad filtering, edge-aware taps,
//                          history-ring taps, triad mask
//  @std-module sample
//  @std-version 1
//  @requires prelude
//
//  Textures are passed as parameters, so these work on readTexture,
//  dataTextureC or any texture_2d<f32>. Coordinates named `px` are in
//  pixels with texel centres at +0.5 (px = uv * size). Loads clamp to
//  the edge. historyLoad reads the ring head from extraBuffer[4] and so
//  needs the prelude; the shader must still declare binding 13 itself
//  (docs/BINDING_CONTRACT.md) and pass that texture in.
// ═══════════════════════════════════════════════════════════════════

/// textureLoad with edge clamping.
/// @cost 1 load
fn loadClamped(tex: texture_2d<f32>, c: vec2<i32>) -> vec4<f32> {
  let dim = vec2<i32>(textureDimensions(tex));
  return textureLoad(tex, clamp(c, vec2<i32>(0), dim - vec2<i32>(1)), 0);
}

/// Bilinear filter via 4 textureLoads (works on unfilterable formats).
/// @cost 4 loads
fn loadBilinear(tex: texture_2d<f32>, px: vec2<f32>) -> vec4<f32> {
  let q = px - 0.5;
  let i = vec2<i32>(floor(q));
  let f = fract(q);
  let a = loadClamped(tex, i);
  let b = loadClamped(tex, i + vec2<i32>(1, 0));
  let c = loadClamped(tex, i + vec2<i32>(0, 1));
  let d = loadClamped(tex, i + vec2<i32>(1, 1));
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

/// loadBilinear with a [0, 1] uv.
/// @cost 4 loads
fn loadBilinearUv(tex: texture_2d<f32>, uv: vec2<f32>) -> vec4<f32> {
  return loadBilinear(tex, uv * vec2<f32>(textureDimensions(tex)));
}

/// Catmull-Rom weights for fractional offset t.
/// @cost ~10 ALU
fn catmullRomWeights(t: f32) -> vec4<f32> {
  return vec4<f32>(
    t * (-0.5 + t * (1.0 - 0.5 * t)),
    1.0 + t * t * (-2.5 + 1.5 * t),
    t * (0.5 + t * (2.0 - 1.5 * t)),
    t * t * (-0.5 + 0.5 * t));
}

/// Bicubic (Catmull-Rom) filter via 16 textureLoads. Can overshoot slightly at edges.
/// @cost 16 loads
fn loadBicubic(tex: texture_2d<f32>, px: vec2<f32>) -> vec4<f32> {
  let q = px - 0.5;
  let i = vec2<i32>(floor(q));
  let f = fract(q);
  let wx = catmullRomWeights(f.x);
  let wy = catmullRomWeights(f.y);
  var acc = vec4<f32>(0.0);
  for (var y = 0; y < 4; y++) {
    var row = vec4<f32>(0.0);
    for (var x = 0; x < 4; x++) {
      row += wx[x] * loadClamped(tex, i + vec2<i32>(x - 1, y - 1));
    }
    acc += wy[y] * row;
  }
  return acc;
}

/// Range (bilateral) weight between a centre and a tap colour.
/// @range (0, 1]
/// @cost 1 exp
fn bilateralWeight(center: vec3<f32>, tap: vec3<f32>, sigma: f32) -> f32 {
  let d = tap - center;
  return exp(-dot(d, d) / max(2.0 * sigma * sigma, 1e-8));
}

/// Edge-aware 3×3 blur: neighbours weighted by colour similarity to the centre.
/// @cost 9 loads, 9 exp
fn loadEdgeAware3x3(tex: texture_2d<f32>, c: vec2<i32>, sigma: f32) -> vec4<f32> {
  let center = loadClamped(tex, c);
  var acc = vec4<f32>(0.0);
  var wsum = 0.0;
  for (var y = -1; y <= 1; y++) {
    for (var x = -1; x <= 1; x++) {
      let t = loadClamped(tex, c + vec2<i32>(x, y));
      let w = bilateralWeight(center.rgb, t.rgb, sigma);
      acc += w * t;
      wsum += w;
    }
  }
  return acc / max(wsum, 1e-8);
}

/// History-ring layer holding the frame `framesAgo` frames back (0 = newest).
/// head is the ring write pointer (extraBuffer[4]); depth = textureNumLayers.
/// @range [0, depth)
/// @cost ~4 int ops
fn historyLayer(head: u32, framesAgo: u32, depth: u32) -> u32 {
  let d = max(depth, 1u);
  return (head % d + d - 1u - framesAgo % d) % d;
}

/// Load from the history ring (binding 13) `framesAgo` frames back, edge-clamped.
/// @cost 1 load
fn historyLoad(hist: texture_2d_array<f32>, c: vec2<i32>, framesAgo: u32) -> vec4<f32> {
  let depth = max(textureNumLayers(hist), 1u);
  let head = select(0u, u32(max(extraBuffer[4], 0.0)), arrayLength(&extraBuffer) > 4u);
  let dim = vec2<i32>(textureDimensions(hist));
  let cc = clamp(c, vec2<i32>(0), dim - vec2<i32>(1));
  return textureLoad(hist, cc, historyLayer(head, framesAgo, depth), 0);
}

/// RGB triad / aperture-grille mask from the integer pixel column.
/// Uses the pixel index, not fract(uv.x * resX): that is 0 at every pixel and
/// gave the catalog its dead-mask bug. strength 0 = no mask, 1 = full triad.
/// @range [0, 1] per channel
/// @cost ~6 ALU
fn triadMask(pixel: vec2<u32>, cellPx: u32, strength: f32) -> vec3<f32> {
  let k = (pixel.x / max(cellPx, 1u)) % 3u;
  let m = vec3<f32>(f32(k == 0u), f32(k == 1u), f32(k == 2u));
  return mix(vec3<f32>(1.0), m, saturate(strength));
}
