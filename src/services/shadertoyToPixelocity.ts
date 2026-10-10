/**
 * Shadertoy GLSL → Pixelocity canonical compute WGSL conversion.
 */

import { glslToWgsl } from './shaderApi';
import { formatNagaError, loadNagaValidator } from '../utils/nagaWasm';

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

const BINDINGS_HEADER = `// Auto-converted from Shadertoy — Pixelocity canonical 13-binding layout
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
`;

// Not in BINDINGS_HEADER: translated user GLSL may declare its own PI / TAU.
const CANONICAL_HEADER = `${BINDINGS_HEADER}
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

/**
 * Prepended to the user's Shadertoy source so naga's GLSL front-end (Vulkan GLSL
 * 450) sees the Shadertoy built-ins. iChannel0 is a separate texture + sampler
 * because naga has no combined image samplers; `texture()` is routed through an
 * explicit-LOD helper so the result stays legal in a compute shader, with the y
 * flip Shadertoy applies to channel inputs.
 */
const NAGA_GLSL_PRELUDE = `#version 450
layout(set = 0, binding = 0) uniform ShadertoyUniforms {
  vec3 iResolution;
  float iTime;
  float iTimeDelta;
  float iFrameRate;
  int iFrame;
  vec4 iMouse;
};
layout(set = 0, binding = 1) uniform texture2D st_iChannel0Tex;
layout(set = 0, binding = 2) uniform sampler st_iChannel0Smp;
layout(location = 0) out vec4 st_fragColor;
vec4 st_channel0(vec2 p) {
  return textureLod(sampler2D(st_iChannel0Tex, st_iChannel0Smp), vec2(p.x, 1.0 - p.y), 0.0);
}
#define iChannel0 sampler2D(st_iChannel0Tex, st_iChannel0Smp)
#define texture(st_c, st_p) st_channel0(st_p)
`;

/** Wrap Shadertoy GLSL (mainImage + helpers, verbatim) as a GLSL 450 fragment shader for naga. */
export function buildFragmentShaderForNaga(shadertoyGlsl: string): string {
  return `${NAGA_GLSL_PRELUDE}
${shadertoyGlsl.replace(/\r\n/g, '\n')}

void main() {
  mainImage(st_fragColor, gl_FragCoord.xy);
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

/**
 * Splits a WGSL module into its top-level declarations (attributes included).
 * naga's writer emits one declaration per blank-line-separated block, but brace
 * depth is tracked so a declaration with blank lines inside still stays whole.
 */
function splitTopLevelItems(wgsl: string): string[] {
  const items: string[] = [];
  let depth = 0;
  let current = '';
  for (const ch of wgsl) {
    current += ch;
    if (ch === '{') depth++;
    else if (ch === '}') {
      depth--;
      if (depth === 0) {
        items.push(current.trim());
        current = '';
      }
    } else if (ch === ';' && depth === 0) {
      items.push(current.trim());
      current = '';
    }
  }
  if (current.trim()) items.push(current.trim());
  return items.filter(Boolean);
}

/**
 * Turn naga's fragment-shader WGSL into a Pixelocity compute shader: drop the
 * fragment entry point and its IO, rebind iChannel0 to readTexture, make the
 * Shadertoy uniform block a private struct that `main` fills from `u`, and call
 * the translated `mainImage` once per pixel.
 */
export function rewriteNagaWgslToPixelocity(nagaWgsl: string): string {
  const items = splitTopLevelItems(nagaWgsl);
  const uniformItem = items.find((item) => /var<uniform>\s+\w+\s*:\s*ShadertoyUniforms\s*;/.test(item));
  const uniformName = uniformItem?.match(/var<uniform>\s+(\w+)\s*:/)?.[1];
  if (!uniformName) {
    throw new Error('naga output has no ShadertoyUniforms block');
  }
  if (!items.some((item) => /^fn\s+mainImage\s*\(/.test(item))) {
    throw new Error('naga output has no mainImage function');
  }

  const kept = items
    .filter((item) => !/^struct\s+FragmentOutput\b/.test(item))
    .filter((item) => !/^@fragment\b/.test(item))
    .filter((item) => !/^fn\s+main_\d*\s*\(/.test(item))
    .filter((item) => !/^var<private>\s+(st_fragColor|gl_FragCoord_?\d*)\s*:/.test(item))
    .filter((item) => !/\bvar\s+st_iChannel0(Tex|Smp)\s*:/.test(item))
    .map((item) =>
      item === uniformItem ? `var<private> ${uniformName}: ShadertoyUniforms;` : item,
    )
    .map((item) =>
      item.replace(/\bst_iChannel0Tex\b/g, 'readTexture').replace(/\bst_iChannel0Smp\b/g, 'u_sampler'),
    );

  const st = uniformName;
  return `${BINDINGS_HEADER}
${kept.join('\n\n')}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) {
    return;
  }

  // Shadertoy's origin is bottom-left; Pixelocity's (and u.zoom_config's) is top-left.
  let mousePx = vec2<f32>(u.zoom_config.y, 1.0 - u.zoom_config.z) * res;
  let mouseDown = select(-1.0, 1.0, u.zoom_config.w > 0.5);
  ${st}.iResolution = vec3<f32>(res, 1.0);
  ${st}.iTime = u.config.x;
  ${st}.iTimeDelta = 1.0 / 60.0;
  ${st}.iFrameRate = 60.0;
  ${st}.iFrame = i32(u.config.x * 60.0);
  ${st}.iMouse = vec4<f32>(mousePx, mousePx * mouseDown);

  let fragCoord = vec2<f32>(f32(global_id.x) + 0.5, res.y - (f32(global_id.y) + 0.5));
  var outColor = vec4<f32>(0.0, 0.0, 0.0, 1.0);
  mainImage(&outColor, fragCoord);

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, pixel, outColor);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
`;
}

/** Wrap hand-written WGSL image logic in the canonical compute entry. */
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

/** Validates the assembled WGSL; resolves to an error message, or null when it is valid. */
export type WgslCheckFn = (wgsl: string) => Promise<string | null>;

/**
 * Full async conversion pipeline from Shadertoy GLSL source: naga translates the
 * GLSL to WGSL, the result is rewritten into a Pixelocity compute shader, and
 * naga validates that before it is returned.
 */
export async function convertShadertoyGlsl(
  glsl: string,
  convertFn: typeof glslToWgsl = glslToWgsl,
  checkFn: WgslCheckFn = checkWgslWithNaga,
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

  if (!extractMainImageGlsl(glsl)) {
    return {
      wgsl: '',
      warnings,
      errors: ['Could not find void mainImage(out vec4 fragColor, in vec2 fragCoord)'],
      unsupportedFeatures,
    };
  }

  try {
    const nagaWgsl = await convertFn(buildFragmentShaderForNaga(glsl), 'fragment');
    const wgsl = rewriteNagaWgslToPixelocity(nagaWgsl);
    const invalid = await checkFn(wgsl);
    if (invalid) {
      errors.push(`Converted WGSL failed validation: ${invalid}`);
      return { wgsl: '', warnings, errors, unsupportedFeatures };
    }
    return { wgsl, warnings, errors, unsupportedFeatures };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    errors.push(`GLSL conversion failed: ${message}`);
    return { wgsl: '', warnings, errors, unsupportedFeatures };
  }
}

async function checkWgslWithNaga(wgsl: string): Promise<string | null> {
  const diag = (await loadNagaValidator()).validate(wgsl);
  return diag.ok ? null : formatNagaError(diag);
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
  // Synchronous placeholder: the real translation is async (naga), see convertShadertoyGlsl.
  const placeholder = `
  // Run the full import (convertShadertoyGlsl) for the naga translation
  outColor = vec4<f32>(uv, 0.5 + 0.5 * sin(u.config.x), 1.0);
`;
  return assembleComputeShader(placeholder);
}
