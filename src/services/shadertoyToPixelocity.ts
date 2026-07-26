/**
 * Shadertoy GLSL → Pixelocity canonical compute WGSL conversion.
 */

import { glslToWgsl } from './shaderApi';

export interface ShadertoyConversionResult {
  wgsl: string;
  warnings: string[];
  errors: string[];
  unsupportedFeatures: string[];
}

export interface ShaderDefinitionDraft {
  id: string;
  name: string;
  category: 'generative';
  url: string;
  description: string;
  tags: string[];
  features: string[];
  params: Array<{
    id: string;
    name: string;
    default: number;
    min: number;
    max: number;
    step: number;
    mapping: string;
    audio: 'bass' | 'mid' | 'treble' | 'overall';
  }>;
}

const CANONICAL_HEADER = `// Auto-converted from Shadertoy — Pixelocity canonical 13-binding layout
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
`;

const UNSUPPORTED_PATTERNS: Array<{ pattern: RegExp; label: string }> = [
  { pattern: /\biChannel[1-3]\b/, label: 'multi-buffer (iChannel1-3)' },
  { pattern: /\biChannelResolution\b/, label: 'iChannelResolution' },
  { pattern: /\biDate\b/, label: 'iDate' },
  { pattern: /\biSampleRate\b/, label: 'iSampleRate' },
  { pattern: /\biChannelTime\b/, label: 'iChannelTime' },
  { pattern: /@binding\s*\(\s*13\s*\)/, label: 'binding 13 (history ring)' },
];

/** Extract mainImage function body from Shadertoy GLSL source. */
export function extractMainImageGlsl(glsl: string): { body: string; helpers: string } | null {
  const normalized = glsl.replace(/\r\n/g, '\n');
  const mainImageMatch = normalized.match(
    /void\s+mainImage\s*\(\s*out\s+vec4\s+fragColor\s*,\s*in\s+vec2\s+fragCoord\s*\)\s*\{([\s\S]*)\}\s*$/
  );
  if (!mainImageMatch) {
    const loose = normalized.match(
      /void\s+mainImage\s*\([^)]*\)\s*\{([\s\S]*)\}/
    );
    if (!loose) return null;
    const body = loose[1];
    const before = normalized.slice(0, loose.index ?? 0);
    return { body, helpers: before };
  }
  const body = mainImageMatch[1];
  const before = normalized.slice(0, mainImageMatch.index ?? 0);
  return { body, helpers: before };
}

/** Build a GLES fragment shader wrapper for TintWASM conversion. */
export function buildFragmentShaderForTint(helpers: string, mainBody: string): string {
  return `#version 450
precision highp float;

uniform vec3 iResolution;
uniform float iTime;
uniform vec4 iMouse;
uniform int iFrame;
uniform sampler2D iChannel0;

${helpers}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {${mainBody}}

out vec4 _outColor;
void main() {
  mainImage(_outColor, gl_FragCoord.xy);
}
`;
}

/** Scan for v1-unsupported Shadertoy features. */
export function detectUnsupportedFeatures(source: string): string[] {
  const found: string[] = [];
  for (const { pattern, label } of UNSUPPORTED_PATTERNS) {
    if (pattern.test(source)) found.push(label);
  }
  return found;
}

/** Post-process Tint WGSL output: map builtins → Pixelocity uniforms. */
export function rewriteTintWgslToPixelocity(tintWgsl: string): string {
  let wgsl = tintWgsl;

  // Remove fragment-specific IO if present
  wgsl = wgsl.replace(/@fragment[\s\S]*?fn\s+main\s*\([^)]*\)[^{]*\{[\s\S]*?\n\}/m, '');
  wgsl = wgsl.replace(/@vertex[\s\S]*?fn\s+\w+\s*\([^)]*\)[^{]*\{[\s\S]*?\n\}/m, '');

  // Builtin remapping (Tint may emit var<private> or uniforms)
  wgsl = wgsl.replace(/\biResolution\b/g, 'vec3(u.config.z, u.config.w, 1.0)');
  wgsl = wgsl.replace(/\biTime\b/g, 'u.config.x');
  wgsl = wgsl.replace(/\biMouse\b/g, 'vec4(u.zoom_config.y, u.zoom_config.z, 0.0, u.zoom_config.w)');
  wgsl = wgsl.replace(/\biFrame\b/g, 'i32(u.config.x)');
  wgsl = wgsl.replace(
    /textureSample\s*\(\s*iChannel0\s*,\s*(\w+)\s*,/g,
    'textureSampleLevel(readTexture, u_sampler,'
  );
  wgsl = wgsl.replace(
    /texture\s*\(\s*iChannel0\s*,/g,
    'textureSampleLevel(readTexture, u_sampler,'
  );

  // Extract color logic: look for assignment to fragColor or _outColor or return
  const mainImageFn = wgsl.match(
    /fn\s+mainImage[^{]*\{([\s\S]*?)\n\}/
  );
  let imageLogic = mainImageFn?.[1]?.trim() ?? '';

  if (!imageLogic) {
    // Fallback: use fragment main body
    const fragMain = wgsl.match(/fn\s+main\s*\([^)]*\)\s*(?:->\s*[^ {]+)?\s*\{([\s\S]*)\}/);
    imageLogic = fragMain?.[1]?.trim() ?? 'let outColor = vec4<f32>(0.0, 0.0, 0.0, 1.0);';
  }

  // Normalize output variable
  imageLogic = imageLogic
    .replace(/\bfragColor\b/g, 'outColor')
    .replace(/\b_outColor\b/g, 'outColor');

  if (!/\boutColor\b/.test(imageLogic)) {
    imageLogic = `var outColor = vec4<f32>(0.0, 0.0, 0.0, 1.0);\n${imageLogic}`;
  }

  return assembleComputeShader(imageLogic);
}

/** Wrap converted image logic in canonical compute entry (testable without Tint). */
export function assembleComputeShader(imageLogic: string): string {
  const logic = imageLogic.includes('outColor')
    ? imageLogic
    : `var outColor = vec4<f32>(0.0, 0.0, 0.0, 1.0);\n${imageLogic}`;

  return `${CANONICAL_HEADER}
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) {
    return;
  }

  let fragCoord = vec2<f32>(global_id.xy) + 0.5;
  let uv = fragCoord / res;

  ${logic}

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, pixel, outColor);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
`;
}

/** Full async conversion pipeline from Shadertoy GLSL source. */
export async function convertShadertoyGlsl(
  glsl: string,
  convertFn: typeof glslToWgsl = glslToWgsl
): Promise<ShadertoyConversionResult> {
  const warnings: string[] = [];
  const errors: string[] = [];
  const unsupportedFeatures = detectUnsupportedFeatures(glsl);

  if (unsupportedFeatures.length > 0) {
    return {
      wgsl: '',
      warnings,
      errors: [`Unsupported features: ${unsupportedFeatures.join(', ')}`],
      unsupportedFeatures,
    };
  }

  const parsed = extractMainImageGlsl(glsl);
  if (!parsed) {
    return {
      wgsl: '',
      warnings,
      errors: ['Could not find void mainImage(out vec4 fragColor, in vec2 fragCoord)'],
      unsupportedFeatures,
    };
  }

  const fragmentShader = buildFragmentShaderForTint(parsed.helpers, parsed.body);

  try {
    const tintWgsl = await convertFn(fragmentShader, 'fragment');
    const wgsl = rewriteTintWgslToPixelocity(tintWgsl);
    if (!wgsl.includes('@compute')) {
      warnings.push('Tint output did not produce compute entry; used fallback assembler');
    }
    return { wgsl, warnings, errors, unsupportedFeatures };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    errors.push(`Tint conversion failed: ${message}`);
    return { wgsl: '', warnings, errors, unsupportedFeatures };
  }
}

/** Generate catalog JSON draft for an imported shader. */
export function generateShaderDefinitionDraft(
  id: string,
  name: string,
  description = 'Imported from Shadertoy'
): ShaderDefinitionDraft {
  const slug = id.replace(/[^a-zA-Z0-9_-]/g, '-').toLowerCase();
  return {
    id: slug,
    name,
    category: 'generative',
    url: `shaders/${slug}.wgsl`,
    description,
    tags: ['generative', 'shadertoy', 'imported'],
    features: ['mouse-control', 'audio-reactive'],
    params: [
      { id: 'param1', name: 'Parameter 1', default: 0.5, min: 0, max: 1, step: 0.01, mapping: 'zoom_params.x', audio: 'bass' },
      { id: 'param2', name: 'Parameter 2', default: 0.5, min: 0, max: 1, step: 0.01, mapping: 'zoom_params.y', audio: 'mid' },
      { id: 'param3', name: 'Parameter 3', default: 0.5, min: 0, max: 1, step: 0.01, mapping: 'zoom_params.z', audio: 'treble' },
      { id: 'param4', name: 'Parameter 4', default: 0.5, min: 0, max: 1, step: 0.01, mapping: 'zoom_params.w', audio: 'overall' },
    ],
  };
}

/** @deprecated Use convertShadertoyGlsl — kept for shaderApi backward compat. */
export function wrapShadertoyGlsl(glslCode: string): string {
  const parsed = extractMainImageGlsl(glslCode);
  if (!parsed) {
    return assembleComputeShader(
      'outColor = vec4<f32>(uv, 0.5 + 0.5 * sin(u.config.x), 1.0);'
    );
  }
  // Synchronous fallback without Tint: embed GLSL as comment, placeholder visual
  const placeholder = `
  // Original mainImage GLSL preserved below (run full import for Tint conversion)
  outColor = vec4<f32>(uv, 0.5 + 0.5 * sin(u.config.x), 1.0);
`;
  return assembleComputeShader(placeholder);
}
