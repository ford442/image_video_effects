// ═══════════════════════════════════════════════════════════════════
//  _compositor/mask.wgsl — draw one layer's mask into its r8unorm
//  maskTex layer (#1512). Full-screen triangle; one draw per masked
//  layer, before the composite dispatch reads the mask.
//
//  Sources:  1 luma of the layer itself
//            2 the DPT depth map (catalog binding 4)
//            3 another slot's matte: its luma when that slot is a matte
//              ('mask' output), otherwise its alpha
// ═══════════════════════════════════════════════════════════════════

const SRC_LUMA: u32 = 1u;
const SRC_DEPTH: u32 = 2u;
const SRC_SLOT: u32 = 3u;

struct MaskParams {
  // x source (SRC_*), y source stack layer, z invert, w source slot is a matte
  src: vec4<u32>,
  // x this layer's stack layer
  info: vec4<u32>,
};

@group(0) @binding(0) var layerTex: texture_2d_array<f32>;
@group(0) @binding(1) var depthTex: texture_2d<f32>;
@group(0) @binding(2) var<uniform> mp: MaskParams;

struct VSOut {
  @builtin(position) pos: vec4<f32>,
};

@vertex
fn vs(@builtin(vertex_index) idx: u32) -> VSOut {
  var p = array<vec2<f32>, 3>(vec2<f32>(-1.0, -1.0), vec2<f32>(3.0, -1.0), vec2<f32>(-1.0, 3.0));
  var out: VSOut;
  out.pos = vec4<f32>(p[idx], 0.0, 1.0);
  return out;
}

fn luma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

@fragment
fn fs(in: VSOut) -> @location(0) vec4<f32> {
  let size = textureDimensions(layerTex);
  let p = min(vec2<u32>(in.pos.xy), size - vec2<u32>(1u));
  var m = 1.0;
  if (mp.src.x == SRC_LUMA) {
    m = luma(textureLoad(layerTex, vec2<i32>(p), i32(mp.info.x), 0).rgb);
  } else if (mp.src.x == SRC_DEPTH) {
    let dsize = textureDimensions(depthTex);
    let q = min(vec2<u32>((vec2<f32>(p) + 0.5) / vec2<f32>(size) * vec2<f32>(dsize)), dsize - vec2<u32>(1u));
    m = textureLoad(depthTex, vec2<i32>(q), 0).r;
  } else if (mp.src.x == SRC_SLOT) {
    let s = textureLoad(layerTex, vec2<i32>(p), i32(mp.src.y), 0);
    m = select(s.a, luma(s.rgb), mp.src.w != 0u);
  }
  m = clamp(m, 0.0, 1.0);
  if (mp.src.z != 0u) { m = 1.0 - m; }
  return vec4<f32>(m, 0.0, 0.0, 1.0);
}
