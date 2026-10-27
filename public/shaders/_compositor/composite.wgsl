// ═══════════════════════════════════════════════════════════════════
//  _compositor/composite.wgsl — Pixelocity layer compositor (#1512)
//
//  One dispatch per composite group (a parallel group, or one chained
//  slot over its input). `baseTex` is the image under the group; each
//  layer is a slot output captured into `layerTex`. Values are linear
//  light in the internal colour format, the convention the present pass
//  already assumes (it applies the transfer function), so HDR (>1.0)
//  survives to the canvas. Bundled into the renderer (compositor.ts);
//  not a catalog shader and never in the shader lists.
//
//  The storage format below is rewritten to the active tier at compile
//  time (rewriteWgslStorageFormats), like every catalog shader.
// ═══════════════════════════════════════════════════════════════════

const MAX_LAYERS: u32 = 6u;

const OUT_REPLACE: u32 = 0u;
const OUT_BLEND: u32 = 1u;
const OUT_MATTE: u32 = 2u;

// Blend mode indices: layerState.ts BLEND_MODES order.
const BLEND_NORMAL: u32 = 0u;
const BLEND_ADD: u32 = 1u;
const BLEND_SCREEN: u32 = 2u;
const BLEND_MULTIPLY: u32 = 3u;
const BLEND_OVERLAY: u32 = 4u;
const BLEND_SOFT_LIGHT: u32 = 5u;
const BLEND_DIFFERENCE: u32 = 6u;
const BLEND_LUMA_KEY: u32 = 7u;
const BLEND_DEPTH_KEY: u32 = 8u;

struct Layer {
  // x output (OUT_*), y blend mode, z 1 when the layer has a mask (maskTex layer w), w stack layer
  mode: vec4<u32>,
  // x opacity, y key threshold, z key softness, w unused
  amount: vec4<f32>,
};

struct Params {
  // x layer count
  info: vec4<u32>,
  layers: array<Layer, 6>,
};

@group(0) @binding(0) var baseTex: texture_2d<f32>;
@group(0) @binding(1) var layerTex: texture_2d_array<f32>;
@group(0) @binding(2) var maskTex: texture_2d_array<f32>;
@group(0) @binding(3) var depthTex: texture_2d<f32>;
@group(0) @binding(4) var outTex: texture_storage_2d<rgba32float, write>;
@group(0) @binding(5) var<uniform> params: Params;

fn luma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// Depth map (binding 4 of the catalog layout) is canvas-sized; the working
// texture may be smaller, so map the coordinate.
fn depthAt(p: vec2<u32>, outSize: vec2<u32>) -> f32 {
  let dsize = textureDimensions(depthTex);
  let q = min(vec2<u32>((vec2<f32>(p) + 0.5) / vec2<f32>(outSize) * vec2<f32>(dsize)), dsize - vec2<u32>(1u));
  return textureLoad(depthTex, vec2<i32>(q), 0).r;
}

// The [0,1] part of an HDR value goes through the classic formula; anything
// above 1.0 (HDR highlight) is carried through unchanged.
fn excess(c: vec3<f32>) -> vec3<f32> {
  return max(c - vec3<f32>(1.0), vec3<f32>(0.0));
}

fn overlayChannel(a: f32, b: f32) -> f32 {
  return select(1.0 - 2.0 * (1.0 - a) * (1.0 - b), 2.0 * a * b, a <= 0.5);
}

fn softLightD(a: f32) -> f32 {
  return select(sqrt(a), ((16.0 * a - 12.0) * a + 4.0) * a, a <= 0.25);
}

// W3C compositing spec soft-light.
fn softLightChannel(a: f32, b: f32) -> f32 {
  return select(a + (2.0 * b - 1.0) * (softLightD(a) - a), a - (1.0 - 2.0 * b) * a * (1.0 - a), b <= 0.5);
}

fn blendRgb(mode: u32, a: vec3<f32>, b: vec3<f32>, depth: f32, key: f32, soft: f32) -> vec3<f32> {
  let sa = clamp(a, vec3<f32>(0.0), vec3<f32>(1.0));
  let sb = clamp(b, vec3<f32>(0.0), vec3<f32>(1.0));
  switch mode {
    case BLEND_ADD: { return a + b; }
    // a + b − a·b on the [0,1] parts: never darker than either input, HDR-safe.
    case BLEND_SCREEN: { return a + b - sa * sb; }
    case BLEND_MULTIPLY: { return a * b; }
    case BLEND_OVERLAY: {
      return vec3<f32>(overlayChannel(sa.r, sb.r), overlayChannel(sa.g, sb.g), overlayChannel(sa.b, sb.b)) + excess(a);
    }
    case BLEND_SOFT_LIGHT: {
      return vec3<f32>(softLightChannel(sa.r, sb.r), softLightChannel(sa.g, sb.g), softLightChannel(sa.b, sb.b)) + excess(a);
    }
    case BLEND_DIFFERENCE: { return abs(a - b); }
    case BLEND_LUMA_KEY: {
      let k = smoothstep(key - soft, key + soft, luma(b));
      return mix(a, b, k);
    }
    case BLEND_DEPTH_KEY: {
      let k = smoothstep(key - soft, key + soft, depth);
      return mix(a, b, k);
    }
    default: { return b; }
  }
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = textureDimensions(outTex);
  if (gid.x >= size.x || gid.y >= size.y) { return; }
  let p = vec2<i32>(gid.xy);
  var acc = textureLoad(baseTex, p, 0);
  let depth = depthAt(gid.xy, size);
  let count = min(params.info.x, MAX_LAYERS);
  for (var i = 0u; i < count; i = i + 1u) {
    let layer = params.layers[i];
    if (layer.mode.x == OUT_MATTE) { continue; }
    let stackLayer = i32(layer.mode.w);
    let c = textureLoad(layerTex, p, stackLayer, 0);
    if (layer.mode.x == OUT_REPLACE) {
      acc = c;
      continue;
    }
    var a = clamp(layer.amount.x, 0.0, 1.0);
    if (layer.mode.z != 0u) {
      a = a * textureLoad(maskTex, p, stackLayer, 0).r;
    }
    let rgb = blendRgb(layer.mode.y, acc.rgb, c.rgb, depth, layer.amount.y, layer.amount.z);
    acc = vec4<f32>(mix(acc.rgb, rgb, a), mix(acc.a, c.a, a));
  }
  textureStore(outTex, p, acc);
}
