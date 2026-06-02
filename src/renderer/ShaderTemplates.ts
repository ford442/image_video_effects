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

const makeBlitWGSL = (flipY: boolean) => /* wgsl */ `
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

@fragment
fn fs(in: VSOut) -> @location(0) vec4f {
  let dim   = vec2i(textureDimensions(src));
  let coord = clamp(vec2i(in.uv * vec2f(dim)), vec2i(0), dim - 1);
  let c     = textureLoad(src, coord, 0);
  // Gamma encode: linear → sRGB (γ = 2.2 approximation)
  let rgb   = pow(clamp(c.rgb, vec3f(0.0), vec3f(1.0)), vec3f(1.0 / 2.2));
  return vec4f(rgb, 1.0);
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
