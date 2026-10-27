// ═══════════════════════════════════════════════════════════════════
//  _compositor/feather.wgsl — optional mask feather (#1512).
//  Separable 13-tap Gaussian: pass 1 maskTex[layer] → scratch along x,
//  pass 2 scratch → maskTex[layer] along y. r8unorm is filterable, so the
//  taps use the linear sampler. The source is always bound as a whole
//  2d-array and the layer picked by index (compat mode cannot bind a
//  single-layer view of an array).
// ═══════════════════════════════════════════════════════════════════

struct FeatherParams {
  // xy texel step direction (1,0) or (0,1), z radius in pixels, w source layer (as f32)
  dir: vec4<f32>,
};

@group(0) @binding(0) var src: texture_2d_array<f32>;
@group(0) @binding(1) var srcSampler: sampler;
@group(0) @binding(2) var<uniform> fp: FeatherParams;

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

@fragment
fn fs(in: VSOut) -> @location(0) vec4<f32> {
  let size = vec2<f32>(textureDimensions(src));
  let uv = in.pos.xy / size;
  let layer = i32(fp.dir.w);
  let radius = max(fp.dir.z, 0.5);
  let sigma = radius * 0.5;
  let stepPx = radius / 6.0;
  var sum = 0.0;
  var weight = 0.0;
  for (var i = -6; i <= 6; i = i + 1) {
    let x = f32(i) * stepPx;
    let w = exp(-(x * x) / (2.0 * sigma * sigma));
    let offset = fp.dir.xy * x / size;
    sum = sum + w * textureSampleLevel(src, srcSampler, uv + offset, layer, 0.0).r;
    weight = weight + w;
  }
  return vec4<f32>(sum / weight, 0.0, 0.0, 1.0);
}
