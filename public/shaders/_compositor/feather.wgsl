// feather.wgsl — one direction of the optional mask feather (#1512 Part B).
//
// Separable 13-tap Gaussian over an r8unorm mask, run twice (horizontal into a
// scratch mask, vertical back). r8unorm is filterable, so taps between texels
// use the bilinear sampler. Bundled by scripts/gen-compositor-wgsl.mjs.

struct FeatherParams {
  dir    : vec2f, // texel step: (1/w, 0) or (0, 1/h), times the radius scale
  radius : f32,   // in texels; 0 never reaches this shader
  pad    : f32,
}

@group(0) @binding(0) var srcMask : texture_2d<f32>;
@group(0) @binding(1) var linearSampler : sampler;
@group(0) @binding(2) var<uniform> params : FeatherParams;

struct VSOut {
  @builtin(position) pos : vec4f,
  @location(0) uv : vec2f,
}

@vertex
fn vs(@builtin(vertex_index) idx : u32) -> VSOut {
  var p = array<vec2f, 3>(vec2f(-1.0, -1.0), vec2f(3.0, -1.0), vec2f(-1.0, 3.0));
  var out : VSOut;
  out.pos = vec4f(p[idx], 0.0, 1.0);
  // Render-target space: +y down, so uv follows the pixel rows.
  out.uv = p[idx] * vec2f(0.5, -0.5) + vec2f(0.5);
  return out;
}

@fragment
fn fs(in : VSOut) -> @location(0) vec4f {
  // sigma = radius / 2; taps at -6..6 spread over the radius.
  let stepSize = params.radius / 6.0;
  var sum = 0.0;
  var weight = 0.0;
  for (var i = -6; i <= 6; i = i + 1) {
    let t = f32(i) / 6.0;
    let w = exp(-2.0 * t * t);
    let uv = in.uv + params.dir * (f32(i) * stepSize);
    sum = sum + w * textureSampleLevel(srcMask, linearSampler, uv, 0.0).r;
    weight = weight + w;
  }
  return vec4f(sum / weight, 0.0, 0.0, 1.0);
}
