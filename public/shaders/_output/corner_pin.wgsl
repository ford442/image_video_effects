// ═══════════════════════════════════════════════════════════════════
//  _output/corner_pin.wgsl — stage output present pass (Part A/B of the
//  "leave the tab" plan). One full-screen triangle per output canvas:
//
//    output pixel → inverse corner pin → program UV → program texture
//
//  then per-output colour (gain, gamma, black level) and the sRGB encode.
//  Calibration test patterns are drawn here, in program UV, so they warp
//  with the pin exactly like the picture does. Never a catalog shader;
//  bundled by src/renderer/webgpu/outputs.ts. Layout: src/output/outputConfig.ts.
// ═══════════════════════════════════════════════════════════════════

struct OutputParams {
  // Rows of the inverse homography (output UV → program UV); .w unused.
  h0: vec4<f32>,
  h1: vec4<f32>,
  h2: vec4<f32>,
  // gain, gamma, black level, flipY (1 = the program is Y-up / generative)
  colour: vec4<f32>,
  // pattern id (0 none, 1 grid, 2 crosshatch, 3 bars, 4 white), outline, width px, height px
  misc: vec4<f32>,
};

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var<uniform> op: OutputParams;

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

fn tap(p: vec2<i32>, maxP: vec2<i32>) -> vec4<f32> {
  return textureLoad(src, clamp(p, vec2<i32>(0), maxP), 0);
}

// Manual bilinear (textureLoad: rgba32float is unfilterable), same as the main blit.
fn sampleProgram(uv: vec2<f32>) -> vec3<f32> {
  let dim  = vec2<i32>(textureDimensions(src));
  let p    = uv * vec2<f32>(dim) - 0.5;
  let base = floor(p);
  let f    = p - base;
  let p0   = vec2<i32>(base);
  let maxP = dim - vec2<i32>(1);
  let c = mix(
    mix(tap(p0, maxP), tap(p0 + vec2<i32>(1, 0), maxP), f.x),
    mix(tap(p0 + vec2<i32>(0, 1), maxP), tap(p0 + vec2<i32>(1, 1), maxP), f.x),
    f.y,
  );
  return max(c.rgb, vec3<f32>(0.0));
}

// 1 on a line of the lattice uv * n, ~1.5 output pixels wide (fw = fwidth(uv)).
fn lattice(uv: vec2<f32>, fw: vec2<f32>, n: f32, widthPx: f32) -> f32 {
  let d = abs(fract(uv * n + 0.5) - 0.5) / max(fw * n, vec2<f32>(1e-6));
  return 1.0 - clamp(min(d.x, d.y) - widthPx * 0.5 + 0.5, 0.0, 1.0);
}

fn lineDist(v: f32, fw: f32, widthPx: f32) -> f32 {
  return 1.0 - clamp(abs(v) / max(fw, 1e-6) - widthPx * 0.5 + 0.5, 0.0, 1.0);
}

// SMPTE-style 75 % bars (encoded values), top two thirds; a ramp below.
fn bars(uv: vec2<f32>) -> vec3<f32> {
  if (uv.y > 0.7) {
    return vec3<f32>(uv.x);
  }
  let i = i32(clamp(floor(uv.x * 7.0), 0.0, 6.0));
  var c = array<vec3<f32>, 7>(
    vec3<f32>(0.75, 0.75, 0.75), vec3<f32>(0.75, 0.75, 0.0), vec3<f32>(0.0, 0.75, 0.75),
    vec3<f32>(0.0, 0.75, 0.0),   vec3<f32>(0.75, 0.0, 0.75), vec3<f32>(0.75, 0.0, 0.0),
    vec3<f32>(0.0, 0.0, 0.75),
  );
  return c[i];
}

@fragment
fn fs(in: VSOut) -> @location(0) vec4<f32> {
  let size = max(op.misc.zw, vec2<f32>(1.0));
  let ouv  = in.pos.xy / size;
  let p    = vec3<f32>(ouv, 1.0);
  let q    = vec3<f32>(dot(op.h0.xyz, p), dot(op.h1.xyz, p), dot(op.h2.xyz, p));
  let w    = select(1e-6, q.z, abs(q.z) > 1e-6);
  let uv   = q.xy / w;
  // Derivatives first, in uniform control flow.
  let fw   = fwidth(uv);

  let inside = q.z > 1e-6 && all(uv >= vec2<f32>(0.0)) && all(uv <= vec2<f32>(1.0));
  if (!inside) {
    return vec4<f32>(0.0, 0.0, 0.0, 1.0);
  }

  let pattern = i32(op.misc.x + 0.5);
  var lin: vec3<f32>;
  if (pattern == 0) {
    let suv = select(uv, vec2<f32>(uv.x, 1.0 - uv.y), op.colour.w > 0.5);
    lin = sampleProgram(suv);
  } else if (pattern == 4) {
    lin = vec3<f32>(1.0);
  } else if (pattern == 3) {
    lin = pow(bars(uv), vec3<f32>(2.2));
  } else {
    // Grid: fine 1/16, bold 1/4, a centre cross and circle; crosshatch adds diagonals.
    var v = 0.08;
    v = max(v, 0.55 * lattice(uv, fw, 16.0, 1.0));
    v = max(v, lattice(uv, fw, 4.0, 2.5));
    let c = uv - 0.5;
    let fwl = length(fw);
    v = max(v, lineDist(length(c) - 0.25, fwl, 2.0));
    if (pattern == 2) {
      v = max(v, lineDist(c.x - c.y, fwl, 1.5));
      v = max(v, lineDist(c.x + c.y, fwl, 1.5));
    }
    lin = vec3<f32>(v);
  }

  let gain  = op.colour.x;
  let gamma = max(op.colour.y, 0.01);
  let black = op.colour.z;
  var rgb = pow(clamp(lin * gain, vec3<f32>(0.0), vec3<f32>(1.0)), vec3<f32>(1.0 / 2.2));
  rgb = pow(rgb, vec3<f32>(gamma));
  rgb = black + rgb * (1.0 - black);

  if (op.misc.y > 0.5) {
    // Outline: within ~2 output pixels of the quad's edge.
    let e = min(min(uv.x, 1.0 - uv.x) / max(fw.x, 1e-6), min(uv.y, 1.0 - uv.y) / max(fw.y, 1e-6));
    if (e < 2.0) {
      rgb = vec3<f32>(1.0, 0.35, 0.1);
    }
  }
  return vec4<f32>(rgb, 1.0);
}
