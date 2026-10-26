// mask.wgsl — draws one slot's r8unorm mask for the layer compositor (#1512 Part B).
//
// A full-screen triangle into a working-size r8unorm target (r8unorm is renderable
// everywhere but storage-writable only with texture-formats-tier1, so masks are
// drawn, not stored). Bundled by scripts/gen-compositor-wgsl.mjs.

const SOURCE_LUMA  : u32 = 1u; // the slot's own output luma
const SOURCE_DEPTH : u32 = 2u; // the DPT depth map
const SOURCE_SLOT  : u32 = 3u; // another slot's matte

struct MaskParams {
  source : u32,
  layer  : u32, // layer to read: own (luma) or the source slot's (slot)
  matte  : u32, // SOURCE_SLOT: 0 = alpha, 1 = luma x alpha (the source is a mask slot)
  invert : u32,
}

@group(0) @binding(0) var layerTex : texture_2d_array<f32>;
@group(0) @binding(1) var depthTex : texture_2d<f32>;
@group(0) @binding(2) var<uniform> params : MaskParams;

struct VSOut {
  @builtin(position) pos : vec4f,
}

@vertex
fn vs(@builtin(vertex_index) idx : u32) -> VSOut {
  var p = array<vec2f, 3>(vec2f(-1.0, -1.0), vec2f(3.0, -1.0), vec2f(-1.0, 3.0));
  var out : VSOut;
  out.pos = vec4f(p[idx], 0.0, 1.0);
  return out;
}

fn luma(c : vec3f) -> f32 {
  return dot(c, vec3f(0.2126, 0.7152, 0.0722));
}

@fragment
fn fs(in : VSOut) -> @location(0) vec4f {
  let size = textureDimensions(layerTex);
  let coord = min(vec2u(in.pos.xy), size - vec2u(1u));
  var m = 1.0;
  if (params.source == SOURCE_LUMA) {
    m = luma(textureLoad(layerTex, coord, params.layer, 0).rgb);
  } else if (params.source == SOURCE_DEPTH) {
    let dim = textureDimensions(depthTex);
    let p = min(vec2u((vec2f(coord) + 0.5) * vec2f(dim) / vec2f(size)), dim - vec2u(1u));
    m = textureLoad(depthTex, p, 0).r;
  } else if (params.source == SOURCE_SLOT) {
    let c = textureLoad(layerTex, coord, params.layer, 0);
    m = select(c.a, luma(c.rgb) * c.a, params.matte == 1u);
  }
  m = clamp(m, 0.0, 1.0);
  if (params.invert == 1u) { m = 1.0 - m; }
  return vec4f(m, 0.0, 0.0, 1.0);
}
