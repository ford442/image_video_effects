/**
 * ShaderTemplates.ts
 *
 * Built-in WGSL shader templates used by the WebGPU renderer.
 * These are used for internal operations like blitting and video import.
 */

/**
 * Video copy shader
 * Copies from external video texture to rgba32float compute texture.
 * Used for zero-copy video import (importExternalTexture → sourceTex).
 */
export const VIDEO_COPY_WGSL = /* wgsl */ `
struct VSOut {
  @builtin(position) pos : vec4f,
  @location(0)       uv  : vec2f,
}

@vertex
fn vs_main(@builtin(vertex_index) vi : u32) -> VSOut {
  // Full-screen triangle
  var pos = array<vec2f, 3>(
    vec2f(-1.0, -1.0),
    vec2f( 3.0, -1.0),
    vec2f(-1.0,  3.0)
  );
  var uv = array<vec2f, 3>(
    vec2f(0.0, 1.0),
    vec2f(2.0, 1.0),
    vec2f(0.0, -1.0)
  );
  return VSOut(vec4f(pos[vi], 0.0, 1.0), uv[vi]);
}

@group(0) @binding(0) var videoTex: texture_external;
@group(0) @binding(1) var videoSampler: sampler;

@fragment
fn fs_main(in: VSOut) -> @location(0) vec4f {
  // Sample from external video texture (handles YUV conversion automatically)
  let color = textureSampleBaseClampToEdge(videoTex, videoSampler, in.uv);
  return color;
}
`;

/**
 * Source→read downscale shader for resolutionScale < 1.0.
 * Samples the full-resolution rgba32float sourceTex with textureLoad
 * (nearest — no filterable-float requirement) and writes raw linear values,
 * matching the identity orientation of copyTextureToTexture at scale = 1.
 */
export const SCALE_COPY_WGSL = /* wgsl */ `
struct VSOut {
  @builtin(position) pos : vec4f,
  @location(0)       uv  : vec2f,
}

@vertex
fn vs(@builtin(vertex_index) idx: u32) -> VSOut {
  var p = array<vec2f,3>(
    vec2f(-1.0, -1.0),
    vec2f( 3.0, -1.0),
    vec2f(-1.0,  3.0),
  );
  var out: VSOut;
  out.pos = vec4f(p[idx], 0.0, 1.0);
  out.uv  = p[idx] * vec2f(0.5, -0.5) + vec2f(0.5);
  return out;
}

@group(0) @binding(0) var src: texture_2d<f32>;

@fragment
fn fs(in: VSOut) -> @location(0) vec4f {
  let dim   = vec2i(textureDimensions(src));
  let coord = clamp(vec2i(in.uv * vec2f(dim)), vec2i(0), dim - 1);
  return textureLoad(src, coord, 0);
}
`;

const makeBlitWGSL = (flipY: boolean, hdr = false) => /* wgsl */ `
struct VSOut {
  @builtin(position) pos : vec4f,
  @location(0)       uv  : vec2f,
}

@vertex
fn vs(@builtin(vertex_index) idx: u32) -> VSOut {
  // Full-screen triangle
  var p = array<vec2f,3>(
    vec2f(-1.0, -1.0),
    vec2f( 3.0, -1.0),
    vec2f(-1.0,  3.0),
  );
  var out: VSOut;
  out.pos = vec4f(p[idx], 0.0, 1.0);
  out.uv  = p[idx] * vec2f(0.5, ${flipY ? '-0.5' : '0.5'}) + vec2f(0.5);
  return out;
}

@group(0) @binding(0) var src: texture_2d<f32>;
${hdr ? `// x exposure (paper white / SDR white), y headroom (peak / SDR white): hdrOutput.ts
@group(0) @binding(1) var<uniform> presentParams: vec4f;

// Identity up to 1.0 (SDR white), then a soft shoulder that approaches the
// display headroom asymptotically with slope 1 at the knee.
fn shoulder(x: f32, headroom: f32) -> f32 {
  if (x <= 1.0 || headroom <= 1.0) { return min(x, max(headroom, 1.0)); }
  let r = headroom - 1.0;
  return 1.0 + r * (1.0 - exp(-(x - 1.0) / r));
}
` : ''}
fn tap(p: vec2i, maxP: vec2i) -> vec4f {
  return textureLoad(src, clamp(p, vec2i(0), maxP), 0);
}

@fragment
fn fs(in: VSOut) -> @location(0) vec4f {
  // Manual bilinear (textureLoad, so unfilterable rgba32float works too). The
  // working texture is often smaller than the canvas (resolution scale, 1024
  // working cap); at equal sizes p lands on texel centres and this is exact.
  let dim  = vec2i(textureDimensions(src));
  let p    = in.uv * vec2f(dim) - 0.5;
  let base = floor(p);
  let f    = p - base;
  let p0   = vec2i(base);
  let maxP = dim - vec2i(1);
  let c = mix(
    mix(tap(p0, maxP), tap(p0 + vec2i(1, 0), maxP), f.x),
    mix(tap(p0 + vec2i(0, 1), maxP), tap(p0 + vec2i(1, 1), maxP), f.x),
    f.y,
  );
${hdr ? `  // HDR canvas (rgba16float, extended tone mapping): canvas 1.0 is SDR white and
  // values above it are highlights. Tonemap on the max channel (keeps hue), then
  // the same γ = 2.2 encode as SDR, extended past 1.0.
  let lin   = max(c.rgb, vec3f(0.0)) * presentParams.x;
  let peak  = max(lin.r, max(lin.g, lin.b));
  let toned = select(lin, lin * (shoulder(peak, presentParams.y) / peak), peak > 1.0);
  return vec4f(pow(toned, vec3f(1.0 / 2.2)), 1.0);` : `  // Gamma encode: linear → sRGB (γ = 2.2 approximation)
  let rgb   = pow(clamp(c.rgb, vec3f(0.0), vec3f(1.0)), vec3f(1.0 / 2.2));
  return vec4f(rgb, 1.0);`}
}
`;

/**
 * Full-screen blit shader for sampled media and shader outputs that already
 * match texture-space Y-down coordinates.
 */
export const BLIT_WGSL = makeBlitWGSL(true);

/**
 * Full-screen blit shader for procedural/generative output that is authored in
 * screen-space Y-up coordinates and should not be vertically flipped at present.
 */
export const GENERATIVE_BLIT_WGSL = makeBlitWGSL(false);

/**
 * HDR present (#1512): the blit for an rgba16float / extended-tone-mapping
 * canvas. Same sampling and orientation as BLIT_WGSL / GENERATIVE_BLIT_WGSL, but
 * keeps values above 1.0 and applies the paper-white / peak tonemap.
 */
export const HDR_BLIT_WGSL = makeBlitWGSL(true, true);
export const HDR_GENERATIVE_BLIT_WGSL = makeBlitWGSL(false, true);
