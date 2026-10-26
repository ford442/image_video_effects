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

const makeBlitWGSL = (flipY: boolean, holdMix = false, hdr = false) => /* wgsl */ `
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
${holdMix ? `
// Present-only crossfade (webgpu/presentHold.ts). Group 1 is the frozen previous
// picture (already gamma-encoded, canvas-sized, canvas orientation) and the mix factor.
struct HoldMix {
  amount : f32, // 0 = the new frame, 1 = the hold
  pad0   : f32,
  pad1   : f32,
  pad2   : f32,
}
@group(1) @binding(0) var holdTex: texture_2d<f32>;
@group(1) @binding(1) var<uniform> holdMix: HoldMix;
` : ''}${hdr ? `
// HDR present (#1512, canvas_configure.json optIn.hdrCanvas): an rgba16float display-p3
// canvas with extended tone mapping, where 1.0 is SDR white. Scene linear light is scaled
// by paperWhite (paper-white nits / SDR reference nits) and values above 1.0 roll off
// towards peak (peak nits / SDR reference nits) instead of clamping.
struct PresentParams {
  paperWhite : f32,
  peak       : f32,
  pad0       : f32,
  pad1       : f32,
}
@group(1) @binding(0) var<uniform> present: PresentParams;

// Identity up to 1.0; above it a C1 exponential shoulder that never exceeds peak.
fn hdrShoulder(x: vec3f, peak: f32) -> vec3f {
  let h = max(peak - 1.0, 0.0);
  if (h <= 0.0) { return min(x, vec3f(1.0)); }
  let over = max(x - vec3f(1.0), vec3f(0.0));
  return select(vec3f(1.0) + h * (vec3f(1.0) - exp(-over / h)), x, x <= vec3f(1.0));
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
${hdr ? `  // Extended range: the same γ 2.2 encode, without the 1.0 clamp.
  let lin   = hdrShoulder(max(c.rgb, vec3f(0.0)) * present.paperWhite, present.peak);
  let rgb   = pow(lin, vec3f(1.0 / 2.2));` : `  // Gamma encode: linear → sRGB (γ = 2.2 approximation)
  let rgb   = pow(clamp(c.rgb, vec3f(0.0), vec3f(1.0)), vec3f(1.0 / 2.2));`}
${holdMix ? `  // The hold is the canvas as last presented: same size, same pixel, no flip.
  let hdim = vec2i(textureDimensions(holdTex));
  let held = textureLoad(holdTex, clamp(vec2i(in.pos.xy), vec2i(0), hdim - vec2i(1)), 0).rgb;
  return vec4f(mix(rgb, held, clamp(holdMix.amount, 0.0, 1.0)), 1.0);` : '  return vec4f(rgb, 1.0);'}
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
 * The blit with the crossfade hold mixed in after the gamma encode: the standard
 * and Y-up variants are chosen exactly as before (selectPresentPipeline), then the
 * frozen previous picture is mixed over the result. Present-only; never a catalog
 * shader and never part of the compute `Uniforms` struct.
 */
export const BLIT_MIX_WGSL = makeBlitWGSL(true, true);
export const GENERATIVE_BLIT_MIX_WGSL = makeBlitWGSL(false, true);

/** The HDR present (rgba16float canvas, #1512): no 1.0 clamp, paper white + peak roll-off at group 1. */
export const HDR_BLIT_WGSL = makeBlitWGSL(true, false, true);
export const HDR_GENERATIVE_BLIT_WGSL = makeBlitWGSL(false, false, true);

/**
 * Storage present (#1512, canvas_configure.json optIn.storagePresent): the blit as one
 * compute pass writing a bgra8unorm swapchain directly (bgra8unorm-storage). Same
 * sampling, orientation and γ 2.2 encode as BLIT_WGSL / GENERATIVE_BLIT_WGSL.
 */
const makeStoragePresentWGSL = (flipY: boolean) => /* wgsl */ `
@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var dst: texture_storage_2d<bgra8unorm, write>;

fn tap(p: vec2i, maxP: vec2i) -> vec4f {
  return textureLoad(src, clamp(p, vec2i(0), maxP), 0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3u) {
  let out = textureDimensions(dst);
  if (gid.x >= out.x || gid.y >= out.y) { return; }
  var uv = (vec2f(gid.xy) + 0.5) / vec2f(out);
  ${flipY ? '' : 'uv.y = 1.0 - uv.y; // generative output is authored Y-up'}
  let dim  = vec2i(textureDimensions(src));
  let p    = uv * vec2f(dim) - 0.5;
  let base = floor(p);
  let f    = p - base;
  let p0   = vec2i(base);
  let maxP = dim - vec2i(1);
  let c = mix(
    mix(tap(p0, maxP), tap(p0 + vec2i(1, 0), maxP), f.x),
    mix(tap(p0 + vec2i(0, 1), maxP), tap(p0 + vec2i(1, 1), maxP), f.x),
    f.y,
  );
  let rgb = pow(clamp(c.rgb, vec3f(0.0), vec3f(1.0)), vec3f(1.0 / 2.2));
  textureStore(dst, vec2i(gid.xy), vec4f(rgb, 1.0));
}
`;

export const STORAGE_PRESENT_WGSL = makeStoragePresentWGSL(true);
export const GENERATIVE_STORAGE_PRESENT_WGSL = makeStoragePresentWGSL(false);
