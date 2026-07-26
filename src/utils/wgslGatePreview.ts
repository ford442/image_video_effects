/**
 * Client-side WGSL gate preview — bindgroup + workgroup convention checks.
 * Mirrors scripts/bindgroup_checker.py / wgsl_precommit_gate.py (no naga in browser).
 */

export interface WgslGatePreviewResult {
  ok: boolean;
  errors: string[];
  warnings: string[];
}

const BINDING_PATTERN =
  /@group\(0\)\s*@binding\((\d+)\)\s*var\s*(<[^>]+>)?\s*(\w+)\s*:\s*([^;]+);/g;

const COMPUTE_PATTERN = /@compute/;
const VERTEX_PATTERN = /@vertex/;
const FRAGMENT_PATTERN = /@fragment/;

const WORKGROUP_ATTR = /@workgroup_size\s*\(([^)]*)\)/g;

const REQUIRED_BINDING_TYPES: Record<number, RegExp> = {
  0: /sampler/,
  1: /texture_2d<f32>/,
  2: /texture_storage_2d<rgba32float,\s*write>/,
  3: /^Uniforms$/,
  4: /texture_2d<f32>/,
  5: /sampler/,
  6: /texture_storage_2d<r32float,\s*write>/,
  7: /texture_storage_2d<rgba32float,\s*write>/,
  8: /texture_storage_2d<rgba32float,\s*write>/,
  9: /texture_2d<f32>/,
  10: /array<f32>/,
  11: /sampler_comparison/,
  12: /array<vec4<f32>>/,
};

const UNIFORMS_FIELDS = ['config', 'zoom_config', 'zoom_params', 'ripples'];

function stripComments(src: string): string {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/\/\/[^\n]*/g, ' ');
}

function countWorkgroupArgs(argList: string): number {
  return argList.split(',').map((a) => a.trim()).filter(Boolean).length;
}

export function checkWgslGatePreview(content: string): WgslGatePreviewResult {
  const errors: string[] = [];
  const warnings: string[] = [];

  if (VERTEX_PATTERN.test(content) || FRAGMENT_PATTERN.test(content)) {
    if (!COMPUTE_PATTERN.test(content)) {
      return { ok: false, errors: ['Render shader without @compute entry'], warnings };
    }
  }

  if (!COMPUTE_PATTERN.test(content)) {
    return { ok: false, errors: ['No @compute entry point'], warnings };
  }

  const stripped = stripComments(content);
  const foundBindings = new Map<number, string>();

  let match: RegExpExecArray | null;
  const bindingRe = new RegExp(BINDING_PATTERN.source, 'g');
  while ((match = bindingRe.exec(content)) !== null) {
    foundBindings.set(parseInt(match[1], 10), match[4].trim());
  }

  for (let i = 0; i <= 12; i++) {
    if (!foundBindings.has(i)) {
      errors.push(`Missing binding ${i}`);
    }
  }

  for (const [num, typeStr] of foundBindings) {
    if (num > 13) {
      errors.push(`Binding ${num} exceeds max index 13`);
    }
    const expected = REQUIRED_BINDING_TYPES[num];
    if (expected && !expected.test(typeStr)) {
      errors.push(`Binding ${num} wrong type: ${typeStr}`);
    }
  }

  const uniformsMatch = content.match(/struct\s+Uniforms\s*\{([^}]+)\}/);
  if (!uniformsMatch) {
    errors.push('Missing Uniforms struct');
  } else {
    for (const field of UNIFORMS_FIELDS) {
      if (!uniformsMatch[1].includes(field)) {
        errors.push(`Uniforms missing field: ${field}`);
      }
    }
  }

  const wgRe = new RegExp(WORKGROUP_ATTR.source, 'g');
  let wgFound = false;
  while ((match = wgRe.exec(stripped)) !== null) {
    wgFound = true;
    const argCount = countWorkgroupArgs(match[1]);
    if (argCount < 2) {
      errors.push(`@workgroup_size needs at least 2 dimensions: ${match[0]}`);
    } else if (argCount === 1) {
      warnings.push(`Non-standard 1-arg @workgroup_size: ${match[0]}`);
    } else if (argCount === 2) {
      warnings.push(`Prefer 3-arg @workgroup_size (use , 1): ${match[0]}`);
    }
  }
  if (!wgFound) {
    errors.push('Missing @workgroup_size on @compute entry');
  }

  return { ok: errors.length === 0, errors, warnings };
}
