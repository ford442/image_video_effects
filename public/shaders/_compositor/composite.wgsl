// composite.wgsl — the layer compositor's one compute pass per parallel group (#1512 Part B).
//
// Not a catalog shader: it is not in any shader list, never takes the 13-binding
// _prelude layout, and is bundled into the renderer by scripts/gen-compositor-wgsl.mjs
// (src/renderer/webgpu/compositorShaders.generated.ts). Source of truth for the
// layer semantics: src/renderer/slotOutput.ts and docs/PARALLEL_SLOTS.md.
//
// All math is in linear light, in the internal color format (rgba16float / rgba32float):
// the output storage format below is rewritten to the active tier at compile time,
// exactly like a catalog shader's writeTexture.

const MAX_LAYERS : u32 = 6u;
const NO_MASK    : u32 = 0xffffffffu;

// Layer.kind
const KIND_REPLACE : u32 = 0u;
const KIND_BLEND   : u32 = 1u;
const KIND_MASK    : u32 = 2u;

// Layer.blend — index into BLEND_MODES (slotOutput.ts).
const BLEND_NORMAL     : u32 = 0u;
const BLEND_ADD        : u32 = 1u;
const BLEND_SCREEN     : u32 = 2u;
const BLEND_MULTIPLY   : u32 = 3u;
const BLEND_OVERLAY    : u32 = 4u;
const BLEND_SOFT_LIGHT : u32 = 5u;
const BLEND_DIFFERENCE : u32 = 6u;
const BLEND_LUMA_KEY   : u32 = 7u;
const BLEND_DEPTH_KEY  : u32 = 8u;

struct Layer {
  kind     : u32, // KIND_*
  blend    : u32, // BLEND_*
  layer    : u32, // array layer in layerTex
  mask     : u32, // mask texture index (== layer) or NO_MASK
  opacity  : f32,
  key      : f32, // luma-key / depth-key threshold
  softness : f32, // half-width of the key ramp
  pad      : f32,
}

struct CompositeParams {
  count  : u32,
  pad0   : u32,
  pad1   : u32,
  pad2   : u32,
  layers : array<Layer, 6>,
}

@group(0) @binding(0)  var baseTex   : texture_2d<f32>;          // the group's input (readTex)
@group(0) @binding(1)  var layerTex  : texture_2d_array<f32>;    // one layer per composited slot
@group(0) @binding(2)  var mask0     : texture_2d<f32>;          // r8unorm masks (1x1 white when unused)
@group(0) @binding(3)  var mask1     : texture_2d<f32>;
@group(0) @binding(4)  var mask2     : texture_2d<f32>;
@group(0) @binding(5)  var mask3     : texture_2d<f32>;
@group(0) @binding(6)  var mask4     : texture_2d<f32>;
@group(0) @binding(7)  var mask5     : texture_2d<f32>;
@group(0) @binding(8)  var depthTex  : texture_2d<f32>;          // DPT depth map (r32float, binding 4 of the catalog)
@group(0) @binding(9)  var outTex    : texture_storage_2d<rgba32float, write>;
@group(0) @binding(10) var<uniform> params : CompositeParams;

fn luma(c : vec3f) -> f32 {
  return dot(c, vec3f(0.2126, 0.7152, 0.0722));
}

// Texture sizes may differ (masks and depth are sampled at the same normalized position).
fn loadAt(tex : texture_2d<f32>, coord : vec2u, size : vec2u) -> vec4f {
  let dim = textureDimensions(tex);
  let p = min(vec2u((vec2f(coord) + 0.5) * vec2f(dim) / vec2f(size)), dim - vec2u(1u));
  return textureLoad(tex, p, 0);
}

fn maskAt(index : u32, coord : vec2u, size : vec2u) -> f32 {
  switch index {
    case 0u: { return loadAt(mask0, coord, size).r; }
    case 1u: { return loadAt(mask1, coord, size).r; }
    case 2u: { return loadAt(mask2, coord, size).r; }
    case 3u: { return loadAt(mask3, coord, size).r; }
    case 4u: { return loadAt(mask4, coord, size).r; }
    case 5u: { return loadAt(mask5, coord, size).r; }
    default: { return 1.0; }
  }
}

// HDR-safe screen: exact in [0,1], monotone above it (a + b - ab would fold values > 1 back down).
fn screen3(b : vec3f, s : vec3f) -> vec3f {
  return b + s - min(b, vec3f(1.0)) * min(s, vec3f(1.0));
}

fn overlay3(b : vec3f, s0 : vec3f) -> vec3f {
  let s = clamp(s0, vec3f(0.0), vec3f(1.0));
  let lo = 2.0 * b * s;
  let hi = vec3f(1.0) - 2.0 * (vec3f(1.0) - b) * (vec3f(1.0) - s);
  return select(hi, lo, b <= vec3f(0.5));
}

// W3C soft-light on the [0,1] part of the base; the HDR excess passes through.
fn softLight3(b0 : vec3f, s0 : vec3f) -> vec3f {
  let b = clamp(b0, vec3f(0.0), vec3f(1.0));
  let s = clamp(s0, vec3f(0.0), vec3f(1.0));
  let d = select(sqrt(b), ((16.0 * b - 12.0) * b + 4.0) * b, b <= vec3f(0.25));
  let lo = b - (vec3f(1.0) - 2.0 * s) * b * (vec3f(1.0) - b);
  let hi = b + (2.0 * s - vec3f(1.0)) * (d - b);
  return select(hi, lo, s <= vec3f(0.5)) + max(b0 - vec3f(1.0), vec3f(0.0));
}

fn blend3(mode : u32, b : vec3f, s : vec3f) -> vec3f {
  switch mode {
    case 1u: { return b + s; }                       // add
    case 2u: { return screen3(b, s); }               // screen
    case 3u: { return b * s; }                       // multiply
    case 4u: { return overlay3(b, s); }              // overlay
    case 5u: { return softLight3(b, s); }            // soft-light
    case 6u: { return abs(b - s); }                  // difference
    default: { return s; }                           // normal, luma-key, depth-key
  }
}

fn keyRamp(value : f32, key : f32, softness : f32) -> f32 {
  let w = max(softness, 1e-4);
  return smoothstep(key - w, key + w, value);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid : vec3u) {
  let size = textureDimensions(outTex);
  if (gid.x >= size.x || gid.y >= size.y) { return; }
  let coord = gid.xy;

  var acc = loadAt(baseTex, coord, size);
  let count = min(params.count, MAX_LAYERS);
  for (var i = 0u; i < count; i = i + 1u) {
    let l = params.layers[i];
    if (l.kind == KIND_MASK) { continue; }
    let src = textureLoad(layerTex, coord, l.layer, 0);
    if (l.kind == KIND_REPLACE) {
      acc = src;
      continue;
    }
    var a = clamp(l.opacity, 0.0, 1.0);
    if (l.mask != NO_MASK) { a = a * maskAt(l.mask, coord, size); }
    if (l.blend == BLEND_LUMA_KEY) {
      a = a * keyRamp(luma(max(src.rgb, vec3f(0.0))), l.key, l.softness);
    } else if (l.blend == BLEND_DEPTH_KEY) {
      a = a * keyRamp(loadAt(depthTex, coord, size).r, l.key, l.softness);
    }
    let rgb = blend3(l.blend, acc.rgb, src.rgb);
    acc = vec4f(mix(acc.rgb, rgb, a), mix(acc.a, src.a, a));
  }
  textureStore(outTex, coord, acc);
}
